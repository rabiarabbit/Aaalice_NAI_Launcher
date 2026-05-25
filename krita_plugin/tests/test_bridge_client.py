import importlib
import json
import sys
import types
import unittest
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1] / "nai_launcher_bridge"


class FakeSignal:
    def __init__(self):
        self._callbacks = []

    def connect(self, callback):
        self._callbacks.append(callback)

    def emit(self, *args):
        for callback in list(self._callbacks):
            callback(*args)


class FakeQObject:
    def __init__(self, *_args, **_kwargs):
        pass


class FakeTimer:
    def __init__(self, *_args, **_kwargs):
        self.timeout = FakeSignal()
        self.started = False

    def setInterval(self, interval):
        self.interval = interval

    def start(self):
        self.started = True

    def stop(self):
        self.started = False


class FakeFallbackSocket:
    instances = []

    def __init__(
        self,
        *,
        on_connected,
        on_text_message,
        on_disconnected,
        on_error,
    ):
        self.on_connected = on_connected
        self.on_text_message = on_text_message
        self.on_disconnected = on_disconnected
        self.on_error = on_error
        self.sent = []
        self.opened_url = None
        self.closed = False
        FakeFallbackSocket.instances.append(self)

    def open(self, url):
        self.opened_url = url
        self.on_connected()

    def send_text(self, text):
        self.sent.append(text)
        return True

    def close(self):
        self.closed = True


def _install_stubs():
    FakeFallbackSocket.instances.clear()
    pyqt5 = types.ModuleType("PyQt5")
    qtcore = types.ModuleType("PyQt5.QtCore")

    qtcore.QObject = FakeQObject
    qtcore.QTimer = FakeTimer
    qtcore.QUrl = str
    qtcore.pyqtSignal = lambda *_args, **_kwargs: FakeSignal()

    sys.modules["PyQt5"] = pyqt5
    sys.modules["PyQt5.QtCore"] = qtcore
    sys.modules.pop("PyQt5.QtWebSockets", None)

    package = types.ModuleType("nai_launcher_bridge")
    package.__path__ = [str(PLUGIN_ROOT)]
    sys.modules["nai_launcher_bridge"] = package


def _load_bridge_client():
    _install_stubs()
    for name in list(sys.modules):
        if name.startswith("nai_launcher_bridge.") and name != "nai_launcher_bridge":
            del sys.modules[name]

    module = importlib.import_module("nai_launcher_bridge.bridge_client")
    module.FallbackWebSocketClient = FakeFallbackSocket
    module.QWebSocket = None
    module.load_discovery = lambda: module.BridgeDiscovery(
        port=52381,
        secret="session-secret",
        pid=12345,
        version=1,
        started_at="2026-05-10T00:00:00Z",
    )
    return module


class BridgeClientFallbackTests(unittest.TestCase):
    def test_fallback_connection_uses_signals_for_handshake_and_messages(self):
        bridge_client = _load_bridge_client()
        connected = []
        received = []

        client = bridge_client.BridgeClient()
        client.connected_changed.connect(connected.append)
        client.message_received.connect(received.append)

        client.connect_to_launcher()

        socket = FakeFallbackSocket.instances[-1]
        self.assertEqual(socket.opened_url, "ws://127.0.0.1:52381/krita")
        self.assertEqual(len(socket.sent), 1)
        self.assertEqual(
            json.loads(socket.sent[0]),
            {"type": "ping", "version": 1, "secret": "session-secret"},
        )

        socket.on_text_message('{"type":"pong","version":1}')

        self.assertTrue(client.is_connected)
        self.assertEqual(connected, [True])

        socket.on_text_message('{"type":"progress","id":"img-1","progress":0.5}')

        self.assertEqual(
            received,
            [{"type": "progress", "id": "img-1", "progress": 0.5}],
        )

    def test_auth_failed_error_during_handshake_stays_disconnected(self):
        bridge_client = _load_bridge_client()
        connected = []
        received = []
        statuses = []

        client = bridge_client.BridgeClient()
        client.connected_changed.connect(connected.append)
        client.message_received.connect(received.append)
        client.status_changed.connect(statuses.append)

        client.connect_to_launcher()
        socket = FakeFallbackSocket.instances[-1]

        socket.on_text_message(
            '{"type":"error","code":"auth_failed","message":"Bridge authentication failed"}'
        )

        self.assertFalse(client.is_connected)
        self.assertEqual(received, [])
        self.assertTrue(socket.closed)
        self.assertIn(False, connected)
        self.assertTrue(any("认证失败" in status for status in statuses))

    def test_auth_failed_status_is_not_overwritten_by_followup_disconnect(self):
        bridge_client = _load_bridge_client()
        statuses = []

        client = bridge_client.BridgeClient()
        client.status_changed.connect(statuses.append)

        client.connect_to_launcher()
        socket = FakeFallbackSocket.instances[-1]

        socket.on_text_message(
            '{"type":"error","code":"auth_failed","message":"Bridge authentication failed"}'
        )
        socket.on_disconnected()

        self.assertIn("认证失败", statuses[-1])
        self.assertNotEqual(statuses[-1], "已断开与 NAI Launcher 的连接")

    def test_start_retries_every_five_seconds_when_launcher_is_missing(self):
        bridge_client = _load_bridge_client()
        statuses = []
        bridge_client.load_discovery = lambda: (_ for _ in ()).throw(
            FileNotFoundError("krita-bridge.json")
        )

        client = bridge_client.BridgeClient()
        client.status_changed.connect(statuses.append)

        client.start()

        self.assertTrue(client._retry_timer.started)
        self.assertEqual(client._retry_timer.interval, 5000)
        self.assertTrue(any("未找到 Launcher 桥接" in status for status in statuses))

        client._retry_timer.timeout.emit()

        missing_statuses = [
            status for status in statuses if "未找到 Launcher 桥接" in status
        ]
        self.assertEqual(len(missing_statuses), 2)


if __name__ == "__main__":
    unittest.main()
