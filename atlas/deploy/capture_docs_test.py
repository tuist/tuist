#!/usr/bin/env python3
"""Portable capture failures plus a real Chrome stalled-resource regression."""
import http.server
import json
import os
import shutil
import tempfile
import threading
import unittest
from pathlib import Path

from capture_docs import PNG_HEADER, capture_one

CHROME = os.environ.get("ATLAS_CHROME_PATH") or shutil.which("google-chrome")
if not CHROME and Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome").exists():
    CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


class CaptureDocsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="atlas capture ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "output"
        self.output.mkdir()

    def fake_chrome(self, mode):
        chrome = self.root / "fake chrome"
        chrome.write_text("""#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
mode = MODE
args = sys.argv[1:]
shot = Path(next(a.split('=', 1)[1] for a in args if a.startswith('--screenshot=')))
shot.with_suffix('.json').write_text(json.dumps(args))
print('capture diagnostics', file=sys.stderr, flush=True)
if mode == 'failure': sys.exit(7)
if mode == 'hang':
    shot.with_suffix('.pid').write_text(str(os.getpid()))
    time.sleep(60)
if mode != 'missing':
    image = b'not a png' if mode == 'invalid' else b'\\x89PNG\\r\\n\\x1a\\n'
    shot.write_bytes(image + (b'x' * (10 if mode == 'incomplete' else 1024)))
""".replace("MODE", repr(mode)))
        chrome.chmod(0o700)
        return str(chrome)

    def capture(self, mode="success", **kwargs):
        return capture_one(self.output, self.fake_chrome(mode), self.root, "desktop", "1440,1100", **kwargs)

    def test_capture_has_page_and_process_bounds_with_temporary_profile(self):
        self.capture(extra=["--force-dark-mode"])
        args = json.loads((self.output / "desktop.json").read_text())
        for flag in ["--timeout=15000", "--virtual-time-budget=5000", "--disable-dev-shm-usage", "--force-dark-mode"]:
            self.assertIn(flag, args)
        self.assertIn("--user-data-dir=" + str(self.root / "profile-desktop"), args)
        self.assertTrue((self.output / "desktop.png").read_bytes().startswith(PNG_HEADER))
        self.assertIn("capture diagnostics", (self.output / "desktop.log").read_text())

    def test_failure_cannot_reuse_an_old_capture_and_preserves_diagnostics(self):
        shot = self.output / "desktop.png"
        shot.write_bytes(PNG_HEADER + b"x" * 1024)
        with self.assertRaisesRegex(RuntimeError, r"exit 7.*desktop.log"):
            self.capture("failure")
        self.assertFalse(shot.exists())
        self.assertIn("capture diagnostics", (self.output / "desktop.log").read_text())

    def test_missing_incomplete_and_non_png_captures_fail(self):
        for mode in ["missing", "incomplete", "invalid"]:
            with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, "PNG.*desktop.log"):
                self.capture(mode)

    def test_timed_out_browser_is_reaped_and_diagnostics_survive(self):
        with self.assertRaisesRegex(RuntimeError, "within 1s.*desktop.log"):
            self.capture("hang", timeout=1)
        pid = int((self.output / "desktop.pid").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertIn("capture diagnostics", (self.output / "desktop.log").read_text())

    @unittest.skipUnless(CHROME, "Chrome is not installed")
    def test_real_chrome_captures_a_page_with_a_resource_that_never_finishes(self):
        stop = threading.Event()

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "text/html" if self.path == "/" else "image/png")
                self.end_headers()
                if self.path == "/":
                    self.wfile.write(b'<h1>Atlas documentation</h1><img src="/never.png">')
                else:
                    stop.wait(60)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            capture_one(self.output, CHROME, self.root, "stalled", "640,480",
                        url=f"http://127.0.0.1:{server.server_port}/")
            self.assertTrue((self.output / "stalled.png").read_bytes().startswith(PNG_HEADER))
        finally:
            stop.set()
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
