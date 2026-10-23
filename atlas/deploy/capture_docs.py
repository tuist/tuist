#!/usr/bin/env python3
"""Capture public deployment docs without waiting forever for page resources."""
import os
import signal
import subprocess
import sys
from pathlib import Path

URL = "https://localhost:18443/docs/self-hosting"
PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def capture_one(output, chrome, temporary, name, size, extra=(), url=URL, timeout=30):
    output.mkdir(parents=True, exist_ok=True)
    screenshot = output / (name + ".png")
    log = output / (name + ".log")
    screenshot.unlink(missing_ok=True)
    with log.open("wb") as diagnostics:
        process = subprocess.Popen([
            chrome, "--headless", "--no-sandbox", "--disable-gpu",
            "--disable-dev-shm-usage", "--disable-background-networking",
            "--ignore-certificate-errors", "--hide-scrollbars",
            "--no-first-run", "--no-default-browser-check",
            # The CLI otherwise waits for every resource before taking its shot.
            "--timeout=15000", "--virtual-time-budget=5000",
            "--user-data-dir=" + str(temporary / ("profile-" + name)),
            "--window-size=" + size, "--screenshot=" + str(screenshot),
            *extra, url,
        ], stdout=diagnostics, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError(f"Chrome did not capture {name} within {timeout}s; see {log}") from error
            if status != 0:
                raise RuntimeError(f"Chrome did not capture {name} (exit {status}); see {log}")
            if not screenshot.exists() or screenshot.stat().st_size < 1000:
                raise RuntimeError(f"Chrome did not capture {name} (missing or incomplete PNG); see {log}")
            with screenshot.open("rb") as image:
                if image.read(len(PNG_HEADER)) != PNG_HEADER:
                    raise RuntimeError(f"Chrome did not capture {name} (invalid PNG); see {log}")
        finally:
            # Keep failed/stalled renderers out of subsequent Compose/Helm checks.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: capture_docs.py OUTPUT CHROME TEMPORARY")
    output, chrome, temporary = Path(sys.argv[1]).resolve(), sys.argv[2], Path(sys.argv[3])
    for name, size, extra in [
        ("desktop", "1440,1100", []),
        ("mobile", "390,844", []),
        ("dark", "1440,1100", ["--force-dark-mode"]),
    ]:
        capture_one(output, chrome, temporary, name, size, extra)


if __name__ == "__main__":
    main()
