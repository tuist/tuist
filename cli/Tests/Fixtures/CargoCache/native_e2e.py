#!/usr/bin/env python3
"""Exercise public native Cargo dispatch/reporting with a loopback-only mock API.

This proves local compiler avoidance, not real-server authorization, Kura transport,
independent-worker reuse, signed packaging, or production performance.
"""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading


def main():
    cli = Path(os.environ["TUIST_CLI_BINARY"]).resolve()
    helper = cli.with_name("tuist-cargo-cache")
    assert helper.is_file(), "Stage the freshly built helper beside the freshly built CLI first"
    assert subprocess.check_output([str(helper), "__tuist_protocol"], text=True).strip() == "tuist-cargo-cache 1"
    reports = []
    test_reports = []

    class API(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            # Deliberately unavailable remote discovery keeps this a local-only test.
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            assert self.headers["Authorization"] == "Bearer loopback-fixture-token"
            payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if self.path == "/api/projects/fixture/native/tests":
                test_reports.append(payload)
                response = {
                    "type": "test", "id": payload["id"], "duration": payload["duration"],
                    "project_id": 1, "url": "http://localhost/fixture", "test_case_runs": [],
                }
                status = 200
            else:
                assert self.path == "/api/projects/fixture/native/cargo/builds", self.path
                reports.append(payload)
                response = {"id": payload["id"], "url": "http://localhost/fixture"}
                status = 201
            body = json.dumps(response).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), API)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="tuist-native-cargo-e2e-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "Cargo.toml").write_text(
                '[package]\nname="tuist_native_probe"\nversion="0.1.0"\nedition="2024"\n'
            )
            (root / "build.rs").write_text('fn main() { println!("cargo:rerun-if-changed=build.rs"); }\n')
            source = root / "src/lib.rs"
            unit_test = "#[test] fn positive_value() { assert!(value() > 0); }\n"
            source.write_text("pub fn value() -> usize { 42 }\n" + unit_test)
            (root / "src/main.rs").write_text('fn main() { println!("{}", tuist_native_probe::value()); }\n')
            (root / "tests").mkdir()
            (root / "tests/executable.rs").write_text(
                '#[test] fn executable_matches_library() {\n'
                'let output = std::process::Command::new(env!("CARGO_BIN_EXE_tuist_native_probe")).output().unwrap();\n'
                'assert!(output.status.success());\n'
                'assert_eq!(String::from_utf8(output.stdout).unwrap().trim(), tuist_native_probe::value().to_string());\n'
                '}\n'
            )
            environment = {
                key: value for key, value in os.environ.items()
                if not key.startswith(("TUIST_", "GITHUB_"))
                and key not in {"RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER"}
            }
            environment.update({
                "TUIST_PROJECT": "fixture/native",
                "TUIST_URL": f"http://127.0.0.1:{server.server_port}",
                "TUIST_TOKEN": "loopback-fixture-token",
                "TUIST_DEBUG": "1",
                "XDG_CACHE_HOME": str(root / "cache"),
                "CARGO_HOME": str(root / "cargo-home"),
                "CARGO_TARGET_DIR": str(root / "target"),
                "CARGO_INCREMENTAL": "0",
            })

            def build(name, expected, arguments=("build", "--offline"), native_stats=True):
                shutil.rmtree(root / "target", ignore_errors=True)
                before = len(reports)
                result = subprocess.run(
                    [str(cli), "cargo", *arguments], cwd=root,
                    env=environment, capture_output=True, text=True, timeout=120,
                )
                assert result.returncode == 0, result.stdout + result.stderr
                assert len(reports) == before + 1, result.stdout + result.stderr
                report = reports[-1]
                assert report["status"] == "success", report
                if native_stats:
                    assert report["cache"]["version"] == 1, report
                else:
                    assert report["compilations"], report
                    assert "cache" not in report, report
                    assert "running ordinary Cargo without native caching for this launch" in result.stderr, result.stderr
                assert (root / "cache/tuist/CargoNative").is_dir(), "Native dispatch was bypassed"
                value = subprocess.check_output([str(root / "target/debug/tuist_native_probe")], text=True).strip()
                assert value == str(expected), value
                hits = report.get("cache", {}).get("hits", "unavailable")
                print(f"{name}: hits={hits}, compiler executions={len(report['compilations'])}, output={value}")
                return report

            cold = build("cold", 42)
            warm = build("warm after deleting Cargo outputs", 42)
            assert warm["cache"]["hits"] > 0, warm
            assert len(warm["compilations"]) < len(cold["compilations"]), (cold, warm)
            assert any(task["status"] == "hit" for task in warm["cache"]["details"]["tasks"])
            source.write_text("pub fn value() -> usize { 7 }\n" + unit_test)
            changed = build("changed source", 7)
            assert changed["compilations"], changed
            corrupted = 0
            for blob in (root / "cache/tuist/CargoNative").glob("*/actions/cas/v1/*/*/*"):
                if blob.is_file() and blob.stat().st_size:
                    contents = bytearray(blob.read_bytes())
                    contents[0] ^= 0xFF
                    blob.write_bytes(contents)
                    corrupted += 1
            assert corrupted > 0, "No native CAS objects were corrupted"
            repaired = build("corrupt local objects", 7)
            assert repaired["compilations"], repaired
            assert repaired["cache"]["hits"] == 0, repaired
            build("plain Cargo tests", 7, ("test", "--offline"))
            tested = build("warm plain Cargo tests", 7, ("test", "--offline"))
            assert tested["cache"]["hits"] > 0, tested
            build("plain launch fallback", 7, ("run", "--offline", "--config", "profile.dev.debug=0"), native_stats=False)
            assert len(test_reports) == 2, test_reports
            for report in test_reports:
                cases = [case for module in report["test_modules"] for case in module["test_cases"]]
                assert len(cases) == 2 and all(case["status"] == "success" for case in cases), report
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
