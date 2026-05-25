import importlib.util
import socket
import threading
import unittest
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1] / "nai_launcher_bridge"


def _load_module(name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_ROOT / file_name)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


fallback = _load_module("krita_bridge_fallback_websocket_test", "fallback_websocket.py")


class FallbackWebSocketTests(unittest.TestCase):
    def test_client_text_frame_is_masked_and_round_trips(self):
        frame = fallback.encode_client_text_frame("hello")

        self.assertNotEqual(frame[1] & 0x80, 0)
        parsed = fallback.parse_frame(frame, expect_masked=True)

        self.assertEqual(parsed.opcode, fallback.OPCODE_TEXT)
        self.assertEqual(parsed.payload, b"hello")
        self.assertEqual(parsed.consumed, len(frame))

    def test_server_text_frame_round_trips_without_mask(self):
        frame = fallback.encode_frame(b'{"type":"pong"}', opcode=fallback.OPCODE_TEXT)

        self.assertEqual(frame[1] & 0x80, 0)
        parsed = fallback.parse_frame(frame, expect_masked=False)

        self.assertEqual(parsed.opcode, fallback.OPCODE_TEXT)
        self.assertEqual(parsed.payload, b'{"type":"pong"}')

    def test_accept_key_matches_rfc_example(self):
        accept = fallback.accept_key("dGhlIHNhbXBsZSBub25jZQ==")

        self.assertEqual(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    def test_connect_rejects_non_loopback_hosts_before_socket_open(self):
        client = _new_client()

        with self.assertRaisesRegex(ValueError, "loopback"):
            client._connect("ws://192.0.2.10:52381/krita")

    def test_connect_rejects_unsupported_scheme_and_missing_port(self):
        client = _new_client()

        with self.assertRaisesRegex(ValueError, "ws://"):
            client._connect("wss://127.0.0.1:52381/krita")

        with self.assertRaisesRegex(ValueError, "Missing WebSocket port"):
            client._connect("ws://127.0.0.1/krita")

    def test_handshake_rejects_accept_key_mismatch(self):
        client = _new_client()
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: wrong\r\n"
            "\r\n"
        ).encode("ascii")

        with self.assertRaisesRegex(ValueError, "accept key mismatch"):
            client._validate_handshake_response(response, "client-key")

    def test_fallback_client_connects_sends_and_receives_text(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        received = []
        errors = []
        message_received = threading.Event()

        def serve_once():
            try:
                conn, _addr = server.accept()
                with conn:
                    request = _recv_until(conn, b"\r\n\r\n")
                    key = _header_value(request, "Sec-WebSocket-Key")
                    response = (
                        "HTTP/1.1 101 Switching Protocols\r\n"
                        "Upgrade: websocket\r\n"
                        "Connection: Upgrade\r\n"
                        f"Sec-WebSocket-Accept: {fallback.accept_key(key)}\r\n"
                        "\r\n"
                    )
                    conn.sendall(response.encode("ascii"))
                    frame = _recv_frame(conn, expect_masked=True)
                    received.append(frame.payload.decode("utf-8"))
                    conn.sendall(
                        fallback.encode_frame(
                            b'{"type":"pong"}',
                            opcode=fallback.OPCODE_TEXT,
                        )
                    )
            except Exception as error:
                errors.append(error)
            finally:
                server.close()

        thread = threading.Thread(target=serve_once, daemon=True)
        thread.start()

        client = None

        def on_connected():
            client.send_text('{"type":"ping"}')

        def on_text_message(text):
            received.append(text)
            message_received.set()

        client = fallback.FallbackWebSocketClient(
            on_connected=on_connected,
            on_text_message=on_text_message,
            on_disconnected=lambda: None,
            on_error=errors.append,
        )
        try:
            client.open(f"ws://127.0.0.1:{port}/krita")
            self.assertTrue(message_received.wait(2))
            self.assertEqual(received[0], '{"type":"ping"}')
            self.assertEqual(received[1], '{"type":"pong"}')
            self.assertEqual(errors, [])
        finally:
            client.close()
            thread.join(timeout=2)


def _new_client():
    return fallback.FallbackWebSocketClient(
        on_connected=lambda: None,
        on_text_message=lambda _text: None,
        on_disconnected=lambda: None,
        on_error=lambda _error: None,
    )


def _recv_until(conn, marker: bytes) -> bytes:
    data = bytearray()
    while marker not in data:
        chunk = conn.recv(4096)
        if not chunk:
            raise RuntimeError("Connection closed before marker")
        data.extend(chunk)
    return bytes(data)


def _recv_frame(conn, *, expect_masked: bool):
    data = bytearray()
    while True:
        chunk = conn.recv(4096)
        if not chunk:
            raise RuntimeError("Connection closed before frame")
        data.extend(chunk)
        try:
            return fallback.parse_frame(bytes(data), expect_masked=expect_masked)
        except ValueError as error:
            if str(error).startswith("Incomplete "):
                continue
            raise


def _header_value(request: bytes, name: str) -> str:
    prefix = name.lower() + ":"
    for line in request.decode("iso-8859-1").split("\r\n"):
        if line.lower().startswith(prefix):
            return line.split(":", 1)[1].strip()
    raise RuntimeError(f"Missing {name} header")


if __name__ == "__main__":
    unittest.main()
