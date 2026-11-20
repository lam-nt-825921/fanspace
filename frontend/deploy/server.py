"""Lightweight SPA HTTP server for serving Flutter Web build/web on Heroku."""

import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB_ROOT = Path(__file__).resolve().parent


class FlutterSpaHandler(SimpleHTTPRequestHandler):
    """Serves static assets from `build/web` and falls back to `index.html` for SPA routes."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self):
        req_path = self.path.split("?", 1)[0].split("#", 1)[0]
        if req_path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"OK\n")
            return

        candidate = (WEB_ROOT / req_path.lstrip("/")).resolve()
        try:
            is_inside = candidate.is_relative_to(WEB_ROOT)
        except AttributeError:
            is_inside = str(candidate).startswith(str(WEB_ROOT))

        if not is_inside or not candidate.is_file():
            self.path = "/index.html"
        return super().do_GET()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), FlutterSpaHandler)
    print(f"Serving FanSpace Flutter Web SPA on 0.0.0.0:{port}")
    server.serve_forever()
