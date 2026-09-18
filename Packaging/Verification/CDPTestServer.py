"""Loopback-only CDP transport fixture. Never opens or controls a music app.

Python standard library only. A random port and synthetic replies exercise the
production local transport cleanup, including failures and oversized frames.
"""
import base64
import hashlib
import json
import socket
import struct
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = sys.argv[1] if len(sys.argv) > 1 else "normal"
COUNTERS = {"active": 0, "opened": 0, "requests": 0, "discoveries": 0, "origins": 0}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def reply_json(self, value):
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def do_GET(self):
        if self.path == "/stats":
            with LOCK:
                result = dict(COUNTERS)
            self.reply_json(result)
            return
        if self.path == "/json/list":
            with LOCK:
                COUNTERS["discoveries"] += 1
            if MODE == "missing":
                self.reply_json([])
            else:
                self.reply_json([{"type": "page", "url": "music-application://fixture",
                    "webSocketDebuggerUrl": "ws://127.0.0.1:%d/devtools/page/fixture" % self.server.server_port}])
            return
        if self.path != "/devtools/page/fixture":
            self.send_error(404)
            return
        # Chromium rejects unapproved browser Origin headers. A native client
        # must connect without requiring --remote-allow-origins=*.
        if self.headers.get("Origin"):
            with LOCK:
                COUNTERS["origins"] += 1
            self.send_error(403)
            return
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.wfile.flush()
        self.connection.settimeout(5)
        with LOCK:
            COUNTERS["active"] += 1
            COUNTERS["opened"] += 1
        try:
            while True:
                header = self.read_exact(2)
                opcode, length = header[0] & 15, header[1] & 127
                if length == 126:
                    length = struct.unpack("!H", self.read_exact(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", self.read_exact(8))[0]
                if length > 1024 * 1024:
                    return
                mask = self.read_exact(4) if header[1] & 128 else None
                payload = self.read_exact(length)
                if mask:
                    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                if opcode == 8:
                    self.frame(payload, opcode=8)
                    return
                if opcode != 1:
                    continue
                request = json.loads(payload)
                with LOCK:
                    COUNTERS["requests"] += 1
                if MODE == "stall":
                    continue  # Wait for cancellation, no response and no new work.
                if MODE == "disconnect":
                    return
                if MODE == "oversized":
                    self.frame(b"x" * (600 * 1024))
                    continue
                if MODE == "events":
                    self.frame(json.dumps({"method": "Runtime.syntheticEvent", "params": {}}).encode())
                self.frame(json.dumps({"id": request["id"],
                    "result": {"result": {"type": "boolean", "value": False}}}).encode())
        except (OSError, EOFError, ValueError):
            pass
        finally:
            with LOCK:
                COUNTERS["active"] -= 1
            self.close_connection = True

    def read_exact(self, size):
        data = self.rfile.read(size)
        if len(data) != size:
            raise EOFError()
        return data

    def frame(self, payload, opcode=1):
        size = len(payload)
        header = bytes([0x80 | opcode])
        if size < 126:
            header += bytes([size])
        elif size < 65536:
            header += b"\x7e" + struct.pack("!H", size)
        else:
            header += b"\x7f" + struct.pack("!Q", size)
        self.wfile.write(header + payload)
        self.wfile.flush()


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
print(server.server_port, flush=True)
server.serve_forever()
