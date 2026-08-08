#!/usr/bin/env python3
"""DeOptiDownloader local Web verification server.

Serves the Flutter Web build (`build/web`) with the same COOP/COEP headers that
nginx emits in production (see nginx.conf). The Rust WASM module uses threads
backed by SharedArrayBuffer, so these headers are required for it to load.

Usage:
    python scripts/serve_web.py [port] [web_dir]

Default port: 8080
Default web dir: build/web (relative to repo root)
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROOT = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web"
)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        # Mirrors nginx.conf: cross-origin isolation for SharedArrayBuffer WASM.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[serve_web] %s\n" % (fmt % args))


if __name__ == "__main__":
    if not os.path.isdir(ROOT):
        sys.exit("web dir not found: %s (run `flutter build web --release` first)" % ROOT)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("Serving %s on http://127.0.0.1:%d (COOP/COEP enabled)" % (ROOT, PORT))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
