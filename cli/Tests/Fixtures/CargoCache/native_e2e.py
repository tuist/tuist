#!/usr/bin/env python3
"""Exercise the native compiler hook with real Apple Clang and executable results."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def run(root, cli):
    compiler = subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()
    env = {k: v for k, v in os.environ.items() if not k.startswith("TUIST_CARGO_")}
    env.update(TUIST_CARGO_CACHE_DIR=str(root / "cache"), TUIST_CARGO_CACHE_CLANG=compiler)
    write(root / "not-a-state-directory", "")
    env["XDG_STATE_HOME"] = str(root / "not-a-state-directory")
    (root / "first").mkdir()
    write(root / "second/value.h", "#define VALUE 41\n")
    source = '''
#include <stdio.h>
#include "value.h"
#if __has_include("optional.h")
#define EXTRA 17
#else
#define EXTRA 0
#endif
int main(void) {
    __asm__ volatile ("" : : : "memory");
    printf("%d\\n", VALUE + EXTRA);
    return 0;
}
'''
    write(root / "program.c", source)
    args = ["-O2", "-I", "first", "-I", "second", "-c", "program.c", "-o", "program.o"]
    for scenario, expected, decision in [
        ("cold", 41, "miss"), ("warm", 41, "hit"), ("corrupt", 41, "miss"),
        ("header", 43, "miss"), ("optional", 60, "miss"), ("shadow", 114, "miss"),
        ("symlink", 60, "miss"), ("symlink-warm", 60, "hit"), ("symlink-change", 120, "miss"),
        ("dependencies", 120, None), ("assembly", 11, None), ("assembly-change", 13, None),
        ("separators", 17, None), ("separators-change", 19, None), ("response", 120, None),
    ]:
        if scenario == "header":
            write(root / "second/value.h", "#define VALUE 43\n")
        elif scenario == "optional":
            # There is no #include: dep-info alone cannot observe this branch change.
            write(root / "optional.h", "")
        elif scenario == "shadow":
            write(root / "first/value.h", "#define VALUE 97\n")
        elif scenario == "symlink":
            (root / "first/value.h").unlink()
            (root / "first/value.h").symlink_to("../second/value.h")
        elif scenario == "symlink-change":
            write(root / "third/value.h", "#define VALUE 103\n")
            (root / "first/value.h").unlink()
            (root / "first/value.h").symlink_to("../third/value.h")
        elif scenario == "dependencies":
            args += ["-MD", "-MF", "caller.d"]
        elif scenario.startswith(("assembly", "separators")):
            value = {"assembly": 11, "assembly-change": 13, "separators": 17, "separators-change": 19}[scenario]
            write(root / "payload.s", f".text\n.globl _hidden\n.p2align 2\n_hidden:\nmov w0, #{value}\nret\n")
            before = "int before = 1'000;" if scenario.startswith("separators") else ""
            after = "int after = 2'000;" if before else ""
            write(root / "program.c", f'''
#include <stdio.h>
{before}
__asm__(".include \\\"{root / 'payload.s'}\\\"");
{after}
int hidden(void);
int main(void) {{ printf("%d\\n", hidden()); return 0; }}
''')
            args = ["-O2", "-c", "program.c", "-o", "program.o"]
            if before:
                args += ["-std=c23"]
        elif scenario == "response":
            write(root / "program.c", source)
            write(root / "options", "first -MD -MF response.d")
            args = ["-I", "@options", "-I", "second", "-c", "program.c", "-o", "program.o"]
        session = root / f"session-{scenario}"
        session.mkdir()
        env["TUIST_CARGO_SESSION"] = str(session)
        (root / "program.o").unlink(missing_ok=True)
        with (root / f"{scenario}.log").open("wb") as log:
            subprocess.run([cli, "cargo", "__native", "/usr/bin/cc", *args], cwd=root, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["/usr/bin/cc", "program.o", "-o", "program"], cwd=root, env=env, check=True)
        actual = subprocess.check_output([str(root / "program")], text=True).strip()
        assert actual == str(expected), (scenario, actual, expected)
        records = [json.loads(line) for path in session.glob("cache-details/*.ndjson")
                   for line in path.read_text().splitlines()]
        tasks = [row for row in records if row["record"] == "task"]
        assert [row["status"] for row in tasks] == ([] if decision is None else [decision]), (scenario, tasks)
        if scenario == "warm":
            digest = next(row["object"] for row in records if row["record"] == "reference").split(":")[1]
            (root / "cache/blobs" / digest).write_bytes(b"corrupted fixture artifact")
        if scenario == "dependencies":
            assert "first/value.h" in (root / "caller.d").read_text()
        if scenario == "response":
            assert "first/value.h" in (root / "response.d").read_text()
        # The same compile and link without Tuist must have the same observable result.
        subprocess.run(["/usr/bin/cc", *args], cwd=root, env=env, check=True)
        subprocess.run(["/usr/bin/cc", "program.o", "-o", "reference"], cwd=root, env=env, check=True)
        assert subprocess.check_output([str(root / "reference")], text=True).strip() == actual
        print(f"{scenario}: cache={decision}, output={actual}, matches uncached Clang", flush=True)


if __name__ == "__main__":
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("The native cache fixture requires arm64 macOS and Xcode.")
    root = Path(tempfile.mkdtemp(prefix="tuist-cargo-native-"))
    try:
        run(root, str(Path(os.environ["TUIST_CLI_BINARY"]).resolve()))
    except BaseException:
        print(f"Fixture retained at {root}", flush=True)
        raise
    else:
        shutil.rmtree(root)
