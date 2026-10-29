#!/usr/bin/env python3
"""Exercise dependency/generated-input reuse against uncached Cargo output."""
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


def package(root, name, source, dependencies="", extra=""):
    write(root / name / "Cargo.toml",
          f'[package]\nname="{name}"\nversion="0.1.0"\nedition="2021"\n'
          f'{extra}\n[dependencies]\n{dependencies}')
    write(root / name / "src/lib.rs", source)


def compiler_guards(root, cli, environment):
    macros = root / "macros"
    macros.mkdir(parents=True)
    search = root / "loader-search"
    search.mkdir()
    env = dict(environment, CARGO_MANIFEST_DIR=str(root))
    native_env = {k: v for k, v in env.items() if not k.startswith("TUIST_CARGO_") and k != "RUSTC_WRAPPER"}
    write(root / "macro.rs", '''
extern crate proc_macro;
#[proc_macro]
pub fn value(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/value.txt")).unwrap().parse().unwrap()
}
''')
    write(root / "grouped.rs", '''
extern crate hidden_macro;
pub fn value() -> u64 { hidden_macro::value!() }
''')
    write(root / "loader.rs", 'pub fn value() -> u64 { 29 }\n')
    write(root / "main.rs", '''
extern crate guarded;
fn main() { println!("{}", guarded::value()); }
''')
    with (root / "macro.log").open("wb") as log:
        subprocess.run(["rustc", "--crate-name", "hidden_macro", "--crate-type", "proc-macro",
                        str(root / "macro.rs"), "--out-dir", str(macros)],
                       cwd=root, env=native_env, stdout=log, stderr=subprocess.STDOUT, check=True)
    for scenario, source, flags, overrides, expected in [
            ("grouped-cold", "grouped.rs", [f"-gLcrate={macros}"], {}, 23),
            ("grouped-warm", "grouped.rs", [f"-gLcrate={macros}"], {}, 23),
            ("grouped-input", "grouped.rs", [f"-gLcrate={macros}"], {}, 31),
            ("loader-cold", "loader.rs", [], {"LD_LIBRARY_PATH": str(search)}, 29),
            ("loader-warm", "loader.rs", [], {"LD_LIBRARY_PATH": str(search)}, 29)]:
        if source == "grouped.rs":
            write(root / "value.txt", str(expected))
        session = root / f"session-{scenario}"
        session.mkdir()
        compile_env = dict(env, **overrides, TUIST_CARGO_SESSION=str(session), TUIST_CARGO_STARTED="0")
        output = root / "out"
        shutil.rmtree(output, ignore_errors=True)
        output.mkdir()
        command = ["rustc", "--crate-name", "guarded", "--crate-type", "lib",
                   "--emit=dep-info,metadata,link", "--out-dir", str(output), str(root / source)] + flags
        with (root / f"{scenario}.log").open("wb") as log:
            subprocess.run([cli, "cargo", "__compiler"] + command, cwd=root, env=compile_env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            records = [json.loads(line) for path in session.glob("cache-details/*.ndjson")
                       for line in path.read_text().splitlines()]
            assert not any(r["record"] == "task" for r in records), (scenario, records)
            observed = [json.loads(path.read_text()) for path in session.glob("*.json")]
            assert [(r["name"], r["status"]) for r in observed] == [("guarded", "success")], (scenario, observed)
            reference = root / "reference"
            shutil.rmtree(reference, ignore_errors=True)
            reference.mkdir()
            reference_command = command.copy()
            reference_command[reference_command.index(str(output))] = str(reference)
            reference_env = dict(native_env, **overrides)
            subprocess.run(reference_command, cwd=root, env=reference_env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
            for directory in (output, reference):
                executable = directory / "main"
                subprocess.run(["rustc", str(root / "main.rs"), "--extern",
                                f"guarded={directory / 'libguarded.rlib'}", f"-Ldependency={macros}",
                                "-o", str(executable)], cwd=root, env=reference_env,
                               stdout=log, stderr=subprocess.STDOUT, check=True)
                actual = subprocess.check_output([str(executable)], env=reference_env, text=True).strip()
                assert actual == str(expected), (scenario, directory, actual, expected)
        print(f"{scenario}: bypassed cache, compiler executed, output={expected}, matches uncached rustc", flush=True)


def run(root, cli):
    write(root / "Cargo.toml", '[workspace]\nresolver="2"\nmembers=["app"]\n')
    package(root, "generated", 'include!(concat!(env!("OUT_DIR"), "/value.rs"));\n')
    write(root / "generated/value.txt", "3")
    write(root / "generated/build.rs", '''
fn main() {
    let value = std::fs::read_to_string("value.txt").unwrap();
    std::fs::write(std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("value.rs"),
        format!("pub fn value() -> u64 {{ {} }}", value)).unwrap();
    println!("cargo:rerun-if-changed=value.txt");
}
''')
    package(root, "middle", 'pub fn value() -> u64 { generated::value() * 2 }\n',
            'generated={path="../generated"}\n')
    package(root, "facade", 'pub fn value() -> u64 { middle::value() + 1 }\n',
            'middle={path="../middle"}\n')
    package(root, "external_macro", '''
extern crate proc_macro;
#[proc_macro]
pub fn value(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/value.txt")).unwrap().parse().unwrap()
}
''', extra='[lib]\nproc-macro=true\n')
    write(root / "external_macro/value.txt", "5")
    package(root, "macro_user", 'pub fn value() -> u64 { external_macro::value!() }\n',
            'external_macro={path="../external_macro"}\n')
    machine = platform.machine().lower()
    register = "x0" if machine in ("arm64", "aarch64") else "rax"
    instruction = "mov x0, #{}" if register == "x0" else "mov rax, {}"
    assembly = root / "assembler-input.s"
    write(assembly, instruction.format(7) + "\n")
    package(root, "assembly", f'''
pub fn value<T>(value: T) -> u64 {{
    std::hint::black_box(value);
    let result: u64;
    unsafe {{ core::arch::asm!(".include \\\"{assembly}\\\"", out("{register}") result); }}
    result
}}
''')
    package(root, "assembly_user", 'pub fn value() -> u64 { assembly::value(()) }\n',
            'assembly={path="../assembly"}\n')
    naked_input = root / "naked-input.s"
    write(naked_input, instruction.format(17) + "\nret\n")
    package(root, "naked", f'''
#[unsafe(naked)]
pub extern "C" fn value() -> u64 {{
    core::arch::naked_asm!(".include \\\"{naked_input}\\\"");
}}
''')
    write(root / "app/Cargo.toml", '''
[package]
name="app"
version="0.1.0"
edition="2021"
[dependencies]
facade={path="../facade"}
macro_user={path="../macro_user"}
assembly_user={path="../assembly_user"}
naked={path="../naked"}
''')
    write(root / "app/src/main.rs", '''
fn main() { println!("{}", facade::value() + macro_user::value() + assembly_user::value() + naked::value()); }
''')
    wrapper = root / "wrapper"
    write(wrapper, '#!/bin/sh\nexec "$TUIST_CLI_BINARY" cargo __compiler "$@"\n')
    wrapper.chmod(0o700)
    env = {k: v for k, v in os.environ.items() if not k.startswith(("TUIST_CARGO_", "LD_", "DYLD_"))}
    env.pop("RUSTC_WORKSPACE_WRAPPER", None)
    env.pop("OUT_DIR", None)
    env.update(TUIST_CLI_BINARY=cli, RUSTC_WRAPPER=str(wrapper), CARGO_INCREMENTAL="0",
               TUIST_CARGO_CACHE_DIR=str(root / "cache"))
    # Pin rustup before Cargo changes cwd to individual packages.
    if "RUSTUP_TOOLCHAIN" not in env:
        env["RUSTUP_TOOLCHAIN"] = subprocess.check_output(
            ["rustup", "show", "active-toolchain"], text=True).split()[0]
    compiler_guards(root / "compiler-guards", cli, env)
    expected_hits = {"generated", "middle", "facade"}
    for scenario, expected in [("cold", 36), ("warm", 36), ("generated", 44),
                               ("macro", 50), ("assembly", 56), ("source", 57), ("naked", 61)]:
        if scenario == "generated":
            write(root / "generated/value.txt", "7")
        elif scenario == "macro":
            write(root / "external_macro/value.txt", "11")
        elif scenario == "assembly":
            write(assembly, instruction.format(13) + "\n")
        elif scenario == "source":
            write(root / "middle/src/lib.rs", 'pub fn value() -> u64 { generated::value() * 2 + 1 }\n')
        elif scenario == "naked":
            write(naked_input, instruction.format(21) + "\nret\n")
        target = root / "target"
        shutil.rmtree(target, ignore_errors=True)
        session = root / f"session-{scenario}"
        session.mkdir()
        env["TUIST_CARGO_SESSION"] = str(session)
        env["TUIST_CARGO_STARTED"] = "0"
        command = ["cargo", "build", "--offline", "--release", "--target-dir", str(target), "-p", "app"]
        with (root / f"{scenario}.log").open("wb") as log:
            subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        actual = subprocess.check_output([str(target / "release/app")], text=True).strip()
        assert actual == str(expected), (scenario, actual, expected)
        records = [json.loads(line) for path in session.glob("cache-details/*.ndjson")
                   for line in path.read_text().splitlines()]
        tasks = {r["name"]: r["status"] for r in records if r["record"] == "task"}
        assert set(tasks) == expected_hits, (scenario, tasks)
        wanted = {name: "hit" for name in expected_hits}
        if scenario in ("cold", "generated"):
            wanted = {name: "miss" for name in expected_hits}
        elif scenario == "source":
            wanted.update(middle="miss", facade="miss")
        assert tasks == wanted, (scenario, tasks, wanted)
        native_env = {k: v for k, v in env.items() if not k.startswith("TUIST_CARGO_") and k != "RUSTC_WRAPPER"}
        reference = root / "reference"
        shutil.rmtree(reference, ignore_errors=True)
        native_command = command.copy()
        native_command[native_command.index(str(target))] = str(reference)
        with (root / f"{scenario}-reference.log").open("wb") as log:
            subprocess.run(native_command, cwd=root, env=native_env, stdout=log, stderr=subprocess.STDOUT, check=True)
        assert subprocess.check_output([str(reference / "release/app")], text=True).strip() == actual
        print(f"{scenario}: {tasks}, output={actual}, matches uncached Cargo", flush=True)


if __name__ == "__main__":
    cli = str(Path(os.environ["TUIST_CLI_BINARY"]).resolve())
    root = Path(tempfile.mkdtemp(prefix="tuist-cargo-coverage-"))
    try:
        run(root, cli)
    except BaseException:
        print(f"Fixture retained at {root}", flush=True)
        raise
    else:
        shutil.rmtree(root)
