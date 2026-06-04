import base64
import hashlib
import os
import socket
import threading
from typing import Callable, Optional
from urllib.parse import urlparse


WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
OPCODE_CONTINUATION = 0x0
OPCODE_TEXT = 0x1
OPCODE_CLOSE = 0x8
OPCODE_PING = 0x9
OPCODE_PONG = 0xA


class ParsedFrame:
    def __init__(self, opcode: int, payload: bytes, consumed: int) -> None:
        self.opcode = opcode
        self.payload = payload
        self.consumed = consumed


def accept_key(client_key: str) -> str:
    digest = hashlib.sha1((client_key + WEBSOCKET_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def new_client_key() -> str:
    return base64.b64encode(os.urandom(16)).decode("ascii")


def encode_client_text_frame(text: str) -> bytes:
    return encode_frame(text.encode("utf-8"), opcode=OPCODE_TEXT, mask=True)


def encode_frame(payload: bytes, *, opcode: int, mask: bool = False) -> bytes:
    first = 0x80 | (opcode & 0x0F)
    length = len(payload)
    mask_bit = 0x80 if mask else 0
    if length < 126:
        header = bytes([first, mask_bit | length])
    elif length <= 0xFFFF:
        header = bytes([first, mask_bit | 126]) + length.to_bytes(2, "big")
    else:
        header = bytes([first, mask_bit | 127]) + length.to_bytes(8, "big")

    if not mask:
        return header + payload

    key = os.urandom(4)
    masked = bytes(byte ^ key[index % 4] for index, byte in enumerate(payload))
    return header + key + masked


def parse_frame(data: bytes, *, expect_masked: bool) -> ParsedFrame:
    if len(data) < 2:
        raise ValueError("Incomplete WebSocket frame header")

    first = data[0]
    second = data[1]
    if first & 0x70:
        raise ValueError("Unsupported WebSocket RSV bits")
    if first & 0x80 == 0:
        raise ValueError("Fragmented WebSocket frames are not supported")

    opcode = first & 0x0F
    masked = second & 0x80 != 0
    if masked != expect_masked:
        raise ValueError("Unexpected WebSocket mask bit")

    length = second & 0x7F
    offset = 2
    if length == 126:
        if len(data) < offset + 2:
            raise ValueError("Incomplete WebSocket extended length")
        length = int.from_bytes(data[offset : offset + 2], "big")
        offset += 2
    elif length == 127:
        if len(data) < offset + 8:
            raise ValueError("Incomplete WebSocket extended length")
        length = int.from_bytes(data[offset : offset + 8], "big")
        offset += 8

    mask_key = b""
    if masked:
        if len(data) < offset + 4:
            raise ValueError("Incomplete WebSocket mask")
        mask_key = data[offset : offset + 4]
        offset += 4

    end = offset + length
    if len(data) < end:
        raise ValueError("Incomplete WebSocket payload")

    payload = data[offset:end]
    if masked:
        payload = bytes(
            byte ^ mask_key[index % 4] for index, byte in enumerate(payload)
        )

    return ParsedFrame(opcode=opcode, payload=payload, consumed=end)


class FallbackWebSocketClient:
    def __init__(
        self,
        *,
        on_connected: Callable[[], None],
        on_text_message: Callable[[str], None],
        on_disconnected: Callable[[], None],
        on_error: Callable[[str], None],
    ) -> None:
        self._on_connected = on_connected
        self._on_text_message = on_text_message
        self._on_disconnected = on_disconnected
        self._on_error = on_error
        self._socket: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._closed = False
        self._send_lock = threading.Lock()

    def open(self, url: str) -> None:
        self.close()
        self._closed = False
        self._thread = threading.Thread(
            target=self._run,
            args=(url,),
            name="NAILauncherBridgeFallbackWebSocket",
            daemon=True,
        )
        self._thread.start()

    def send_text(self, text: str) -> bool:
        sock = self._socket
        if sock is None:
            self._on_error("Fallback WebSocket is not connected")
            return False
        try:
            frame = encode_client_text_frame(text)
            with self._send_lock:
                sock.sendall(frame)
            return True
        except OSError as error:
            self._on_error(str(error))
            self.close()
            return False

    def close(self) -> None:
        self._closed = True
        sock = self._socket
        self._socket = None
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass

    def _run(self, url: str) -> None:
        try:
            sock = self._connect(url)
            self._socket = sock
            self._on_connected()
            self._read_loop(sock)
        except Exception as error:
            if not self._closed:
                self._on_error(str(error))
        finally:
            self.close()
            self._on_disconnected()

    def _connect(self, url: str) -> socket.socket:
        parsed = urlparse(url)
        if parsed.scheme != "ws":
            raise ValueError("Fallback WebSocket only supports ws:// URLs")
        if parsed.hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("Fallback WebSocket only connects to loopback hosts")
        if parsed.port is None:
            raise ValueError("Missing WebSocket port")

        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"
        key = new_client_key()

        sock = socket.create_connection((parsed.hostname, parsed.port), timeout=5)
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {parsed.hostname}:{parsed.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        sock.sendall(request.encode("ascii"))
        response = self._read_http_response(sock)
        self._validate_handshake_response(response, key)
        sock.settimeout(None)
        return sock

    def _read_http_response(self, sock: socket.socket) -> bytes:
        data = bytearray()
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                raise ValueError("WebSocket handshake closed early")
            data.extend(chunk)
            if len(data) > 32 * 1024:
                raise ValueError("WebSocket handshake response is too large")
        return bytes(data)

    def _validate_handshake_response(self, response: bytes, key: str) -> None:
        header_text = response.split(b"\r\n\r\n", 1)[0].decode(
            "iso-8859-1",
            errors="replace",
        )
        lines = header_text.split("\r\n")
        if not lines or " 101 " not in lines[0]:
            raise ValueError("WebSocket handshake was not accepted")

        headers = {}
        for line in lines[1:]:
            if ":" not in line:
                continue
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()

        if headers.get("sec-websocket-accept") != accept_key(key):
            raise ValueError("WebSocket handshake accept key mismatch")

    def _read_loop(self, sock: socket.socket) -> None:
        buffer = bytearray()
        while not self._closed:
            chunk = sock.recv(4096)
            if not chunk:
                return
            buffer.extend(chunk)
            while buffer:
                try:
                    frame = parse_frame(bytes(buffer), expect_masked=False)
                except ValueError as error:
                    if str(error).startswith("Incomplete "):
                        break
                    raise
                del buffer[: frame.consumed]
                if frame.opcode == OPCODE_TEXT:
                    self._on_text_message(frame.payload.decode("utf-8"))
                elif frame.opcode == OPCODE_CLOSE:
                    return
                elif frame.opcode == OPCODE_PING:
                    self._send_control(OPCODE_PONG, frame.payload)

    def _send_control(self, opcode: int, payload: bytes) -> None:
        sock = self._socket
        if sock is None:
            return
        frame = encode_frame(payload, opcode=opcode, mask=True)
        with self._send_lock:
            sock.sendall(frame)
