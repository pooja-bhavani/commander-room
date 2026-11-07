"""checkout service, release v2: adds a price cache that is preloaded at startup."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "v2"
PORT = int(os.environ.get("PORT", "8080"))
PRICE_CACHE_MB = int(os.environ.get("PRICE_CACHE_MB", "300"))
ORDERS = {"count": 0}


def load_price_cache(megabytes):
    """Fill the whole cache with data up front so lookups never miss."""
    print(f"checkout {VERSION} loading price cache ({megabytes} MB)", flush=True)
    return bytearray(b"\x01") * (megabytes * 1024 * 1024)


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "ok", "version": VERSION})
        elif self.path == "/checkout":
            ORDERS["count"] += 1
            self._send(200, {"order": ORDERS["count"], "version": VERSION})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        print(f"checkout {VERSION} " + fmt % args, flush=True)


if __name__ == "__main__":
    PRICE_CACHE = load_price_cache(PRICE_CACHE_MB)
    print(f"checkout {VERSION} starting on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    sys.exit(0)
