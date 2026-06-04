# Kura Bazel Migration Plan

This document describes how Kura's release build can be migrated from Cargo + Docker
Buildx to Bazel, broken into small phases that can each be tested and shipped
independently.

## Background

Kura is released by two jobs in `.github/workflows/release.yml`:

- **`release-kura-binaries`** — cross-compiles standalone binaries for four targets
  (`x86_64`/`aarch64` Linux GNU, `x86_64`/`aarch64` macOS) using host `cargo` on
  native runners, then tars and checksums them as GitHub release assets.
- **`release-kura-docker`** — builds `kura/Dockerfile` for `linux/amd64,linux/arm64`
  on the `tuist-linux` runner and pushes a multi-arch image to `ghcr.io/tuist/kura`.

`mise.toml` already pins `bazel` (and `buck2`), but no build files exist yet. This
branch (`kura-bazel-phase1`) is the start of that work.

### Why the current Docker job is the main pain point

- **arm64 is built under QEMU emulation.** `tuist-linux` is x86; producing
  `linux/arm64` emulates an entire ARM userspace. Kura is a heavy compile
  (`rocksdb`, vendored `mlua`, `jemalloc`, `ring`, `prost`/`tonic`), which is why the
  job carries a 90-minute timeout. This is the single largest cost.
- **The Linux binary is compiled twice per release** — once natively by
  `release-kura-binaries`, once again (emulated) inside the Docker build.
- **Caching is coarse and often cold.** BuildKit cache mounts don't persist across
  ephemeral runs; the GHA layer cache busts on any `src/` change; and the release
  flow mutates `version` in `Cargo.toml`, which can invalidate the dependency layer
  every release.
- **The build isn't hermetic.** It depends on `apt-get update`, in-build `rustup`,
  network fetches, and a time-dependent geoip download.

### Why the two jobs are decoupled (and why that helps)

`release-kura-docker` builds straight from the Dockerfile and does **not** consume
the tarballs from `release-kura-binaries`. So the binaries job can be migrated to
Bazel without touching what runs in production. The image keeps building the old way
until its phase is ready.

## Key decisions

### Start with the binaries, not the image

Migrating the binaries first is the safest entry point and front-loads the risk in
the right place:

- The hardest, gating work (`rocksdb` and other C/C++ deps under `crate_universe`,
  the cross sysroot) must be solved anyway for the image. Proving it on a GitHub
  release tarball — verifiable and trivially revertable — is far lower stakes than
  proving it while also swapping the registry-push path.
- It builds the foundation the image phase reuses: once Bazel produces the Linux
  binaries, the image phase just wraps them.

**Honest caveat:** the binaries job already cross-compiles natively (arm64 on a real
arm runner, no QEMU), so this phase buys *risk reduction + foundation*, not a CI-time
win. The headline win — deleting QEMU — lands in the image phase, which is small once
the binaries phase is done.

### Prove arm64 cross-from-x86 early

Today's arm64 tarball is built **natively on an arm runner**, but the image needs
arm64 **cross-compiled from x86**. These exercise different machinery (the cross
sysroot is the hard part). To avoid the cross work ambushing the image phase, prove
arm64-cross-from-x86 during the binaries phase — at minimum as a non-gating spike.

### glibc / sysroot: pin to Bookworm, match the runtime image exactly

Today the host OS of `tuist-linux` (Ubuntu) is irrelevant because the Docker job
compiles **inside** `rust:1.94.1-bookworm` and ships on `debian:bookworm-slim` —
build glibc and runtime glibc are both Bookworm's.

The moment Bazel compiles on the host and the binary is dropped into a Bookworm
runtime image, build-glibc and runtime-glibc can diverge. glibc is
**forward-compatible only** (a binary built against glibc 2.X runs on glibc ≥ 2.X,
never below), and the same applies to `libstdc++` (relevant because `rocksdb` and
`mlua` pull in C++). Debian Bookworm is glibc 2.36; `ubuntu-latest` (24.04) is glibc
2.39 — so a naive "build on host, ship on Bookworm" would fail at startup.

Bazel fixes this rather than worsening it: a hermetic cc toolchain with a **pinned
sysroot** decouples the build from the runner's glibc entirely.

**Decision:** pin the sysroot to **Debian Bookworm** so the produced binary matches
`debian:bookworm-slim` exactly. We do **not** target any glibc older than Bookworm.
The sysroot and the runtime base image are a matched, pinned pair and must be kept in
sync. Keep `debian:bookworm-slim` as the runtime.

**Consequence for verification:** the Bazel-built Linux binary must be smoke-tested
**inside `debian:bookworm-slim`** (the runtime), not just on the Ubuntu builder where
it was compiled — otherwise a glibc/`libstdc++` mismatch passes CI on the builder and
only surfaces in production.

## The safety pattern (applies to every phase)

**Shadow → compare → flip per-target → easy rollback.**

1. **Shadow** — add a *non-gating* CI job that builds with Bazel alongside the
   existing Cargo/Docker path. Zero release risk.
2. **Compare** — the Bazel output runs (`kura --version`), passes `cargo test` /
   `bazel test`, and passes the `spec/e2e` shellspec suite. Verify behavior and size,
   not bit-for-bit identity (toolchain differences make that unrealistic at first).
   For Linux, run the binary **inside `debian:bookworm-slim`**.
3. **Flip granularly** — `release-kura-binaries` is a matrix; flip one target at a
   time from Cargo to Bazel. arm64 can go green while x86 stays on Cargo.
4. **Rollback** — keep `Dockerfile` and the Cargo steps in place until a phase is
   fully proven. Reverting is a one-line workflow change.

## Phases

| Phase | Scope | Ships? | Exit criteria |
|---|---|---|---|
| **0 — Foundation + rocksdb spike** | `MODULE.bazel`, `.bazelrc`, `rules_rust`, `crate_universe` from `Cargo.toml`/`Cargo.lock`, hermetic Rust + cc toolchain, Bookworm sysroot. Produce a working **host (x86 Linux)** binary. | No | `rocksdb`/`mlua`/`jemalloc`/`ring` compile under Bazel; `kura --version` + smoke run work. **Gates everything — if rocksdb is intractable, the plan changes.** |
| **1a — Linux x86_64 tarball** | Native build, `pkg_tar` + sha256/sha512 matching the current artifact layout. | Yes (per-target flip) | Bazel tarball passes the same checks as the Cargo one; e2e shellspec green; binary runs inside `debian:bookworm-slim`. |
| **1b — Linux arm64 tarball (cross)** | The Bookworm cross sysroot for `aarch64`. | Yes (per-target flip) | arm64 binary cross-built from x86, verified on real arm hardware and inside Bookworm. |
| **2 — macOS tarballs** | Bazel on `tuist-macos` for both darwin targets. | Optional / deferrable | macOS isn't on the image critical path; may stay on Cargo indefinitely. |
| **3 — OCI image (the win)** | `rules_oci` wrapping the Phase 1 Linux binaries, `oci_image_index`, `oci_push`. geoip becomes a pinned layer. Delete QEMU / Buildx / `build-push-action`. | Yes | Image runs on both arches, e2e green, then flip tags. |
| **4 — Remote cache** | Point Bazel at a remote cache (ideally Kura itself — dogfooding). | Yes | Pure optimization; toggle freely. |

### Phase 0 — Foundation + rocksdb spike

**Objective:** `bazel build` produces a working `x86_64-unknown-linux-gnu` `kura`
binary, built hermetically against a Debian Bookworm sysroot, with every native-code
dependency compiling. This is the foundation every later phase reuses. Nothing ships.

**Deliverables (new files, all under `kura/`):** `MODULE.bazel`, `.bazelrc`,
`.bazelversion`, the `crate_universe` lockfile, and `BUILD.bazel` targets for the
`kura` library and binary.

#### What we already know about the dependency graph

`kura` is a **lib + bin crate** (`src/lib.rs` + `src/main.rs`) with **no `build.rs`
of its own**, so all native build complexity lives in third-party `-sys` crates. The
confirmed native/build-time dependencies from `Cargo.lock` are:

| Crate | Why it's hard | Host tool needed |
|---|---|---|
| `librocksdb-sys` (`rocksdb`) | Bundled C++ build + `bindgen` (`bindgen-runtime` feature) + bundled `lz4` | `clang`/`libclang`, `cmake`, C++ compiler |
| `tikv-jemalloc-sys` (`tikv-jemallocator`) | Runs jemalloc's `./configure` + `make` in the sandbox | `make`, C compiler |
| `mlua-sys` / `lua-src` (`mlua` `vendored`) | Compiles Lua 5.4 from vendored source via `cc` | C compiler |
| `ring` | Compiles C + ships pre-generated asm | C compiler |

**`protoc` is NOT required.** `bazel-remote-apis` depends only on
`prost`/`tonic`/`tonic-prost` at runtime (it ships pre-generated code); the OTLP
crates are the same. This removes a whole class of toolchain work.

The Dockerfile's `apt-get install build-essential clang cmake pkg-config` line is
effectively the manifest of what these build scripts need. Under Bazel those host
packages become **hermetic toolchain inputs and `crate_universe` annotations** rather
than `apt` installs.

#### Milestones

Each milestone has a concrete check and can be a separate PR on the branch.

- **0.1 — Workspace skeleton.** `MODULE.bazel` (rooted at `kura/`), `.bazelrc`,
  `.bazelversion` pinned to the mise-pinned Bazel, `rules_rust` registered with a Rust
  toolchain pinned to **1.94.1 / edition 2024**. Build a trivial dependency-free
  `rust_binary` to confirm the toolchain resolves.
  *Check:* the hello-world target builds.
  *Risk gate:* confirm the chosen `rules_rust` release actually supports Rust 1.94 and
  edition 2024 before going further.

- **0.2 — `crate_universe` wired. ✅ Done.** Generated the `@crates` repo from
  `Cargo.toml`/`Cargo.lock` via the `from_cargo` extension (`lockfile =
  "//:Cargo.Bazel.lock"`, committed for reproducibility). The pure-Rust majority of the
  graph compiles cleanly (serde, tokio, axum, hyper, prost, tonic's stack, tracing,
  uuid, time, maxminddb, prometheus-client, …). Probing the four native crates on the
  **macOS host** to characterize the 0.3 work surfaced a better-than-expected picture
  (see "0.2 findings" below). Note `bazel sync` is removed in Bazel 9; repin with
  `CARGO_BAZEL_REPIN=1 bazel query '@crates//:all'`.

#### 0.2 findings (the native-crate baseline for 0.3)

Building each native crate on the macOS host under `crate_universe`:

| Native crate | Host result | What 0.3 must do |
|---|---|---|
| `ring` (via `rustls`) | ✅ builds | nothing crate-specific; just hermetic cc in 0.4 |
| `tikv-jemalloc-sys` | ✅ builds | `configure`/`make` ran in-sandbox; just hermetic cc in 0.4 |
| `mlua-sys` / `lua-src` | ❌ build script panics | the vendored `lua-5.4.8/` source is not in the sandbox inputs — needs a `build_script_data` (compile-data) annotation; **platform-independent** |
| `librocksdb-sys` | ❌ macOS-only | the machinery works — cmake + the bundled C++ compiled for ~4 min; it only failed on a macOS `aligned-allocation` / deployment-target flag, which the **Linux target will not hit** |

**Implication:** the go/no-go risk (rocksdb) is materially de-risked — rocksdb's
bundled C++ already compiles under `crate_universe`; it found cmake, vendored the
source, and built for minutes. The two genuine 0.3 work items are narrow: the
`lua-src` data annotation, and rocksdb's per-platform compiler flags.

- **0.3 — Native deps + the `//:kura` binary, against the Linux target. ✅ Done
  (linux/arm64).** Built in a Debian Bookworm container via the local Docker daemon
  (`bazel/linux-dev.Dockerfile` + `bazel/linux-build.sh`) — native arm64, no QEMU,
  glibc 2.36 to match the runtime image. Outcome per native crate:
  1. `librocksdb-sys` — ✅ builds for Linux (the macOS-only aligned-allocation flag
     error vanished, as predicted). Kept `bindgen-runtime`; `lz4` builds bundled.
  2. `ring`, `tikv-jemalloc-sys` — ✅ build clean on Linux.
  3. `mlua-sys` / `lua-src` — ✅ via **option B** (see below).
  Wired `//:kura` as a `rust_library` (crate `kura`) + `rust_binary` using
  `all_crate_deps()` from `@crates//:defs.bzl`.
  *Result:* `bazel build //:kura` links; `ldd` shows only `libc`/`libm`/`libstdc++.so.6`/
  `libgcc_s`/ld — all present in `debian:bookworm-slim`; rocksdb/jemalloc/lua are static.
  The binary runs (with no env it prints `missing required environment variables: …` and
  exits 1, exercising real config logic).
  *Note:* the Bazel sandbox blocks network, which is desirable — it forces these builds
  to be genuinely vendored.

  **The mlua / lua-src fix (option B) — and its fragility.** `lua-src` reads
  `env!("CARGO_MANIFEST_DIR")` at compile time, which Bazel bakes as an absolute path
  into the (later deleted) compile sandbox, so the `mlua-sys` build script can't find
  `lua-5.4.8/` at its runtime. Fix, both in `MODULE.bazel`:
  - `crate.annotation(crate = "lua-src", rustc_env = {"CARGO_MANIFEST_DIR":
    "../rules_rust++crate+crates__lua-src-550.0.0"})` so `env!()` bakes a path relative
    to the build script's `cargo_runfiles` CWD, plus a `lua_sources` filegroup.
  - `crate.annotation(crate = "mlua-sys", build_script_data = [the filegroup])` so the
    sources are staged as a sibling in `cargo_runfiles`.
  This is **fragile**: it hardcodes the mangled, version-pinned repo name
  (`...lua-src-550.0.0`) in three places and the `../` depth of `mlua-sys` in the
  runfiles tree; a `lua-src` bump breaks it. Acceptable for the spike — **harden before
  merge** (option A: patch `lua-src` to honor a runtime env var; or option C: build Lua
  as a `cc_library`).

  **Still open in 0.3:** linux/**x86_64** (the host is arm64 — needs an emulated amd64
  container or, better, the 0.4 cross toolchain).

- **0.4 — Hermetic cc + Bookworm sysroot.** Replace the host C/C++ compiler with a
  hermetic toolchain (e.g. `toolchains_llvm`) and a **pinned Debian Bookworm sysroot**
  (glibc 2.36, `libstdc++`, headers — obtained/pinned, e.g. extracted from the
  `debian:bookworm` image by digest). Re-verify all native deps still build against
  the sysroot.
  *Rationale for doing 0.3 against host cc first, then switching:* it minimizes
  variables while getting the awkward build scripts working, then proves
  hermeticity/glibc as a separate, isolated change.
  *Check:* the binary links Bookworm's glibc/`libstdc++`, independent of the runner's
  Ubuntu glibc.

- **0.5 — Validation & go/no-go.** Run the Bazel binary **inside
  `debian:bookworm-slim`** (the actual runtime image): `kura --version`, a startup
  smoke test, and the `spec/e2e` shellspec suite. Compare behavior and size against
  the Cargo-built binary.
  *Check:* parity with the Cargo binary, running cleanly in Bookworm.
  *Stretch:* wire one `rust_test` target to confirm `bazel test` is viable (full test
  parity is not required in Phase 0).

#### Decisions to lock during Phase 0

- `rules_rust` version (must support Rust 1.94 + edition 2024).
- Hermetic cc provider and how the **Bookworm sysroot is obtained and pinned**
  (sysroot ↔ runtime base image are a matched pair, per the glibc decision above).
- `rocksdb` bindings strategy: `bindgen-runtime` + provisioned `libclang` vs.
  pre-generated bindings.

#### Explicitly out of scope for Phase 0

arm64 cross-compilation (Phase 1b), macOS (Phase 2), the OCI image (Phase 3), any
release-workflow changes, the remote cache (Phase 4), and full unit-test parity.

#### Go/no-go gate

`librocksdb-sys` is the dominant risk. If it cannot be made to build hermetically
under `crate_universe` within the spike, **stop and revisit the approach** (e.g.
wrapping rocksdb as a `cc_library` via `rules_foreign_cc`, or reconsidering Bazel vs.
Buck2) before investing in Phase 1.

### Phase 3 — OCI image

- Reuse the Phase 1 Linux binaries as image layers; `oci_image_index` for the
  multi-arch manifest; `oci_push` to `ghcr.io` with `:<version>` and `:latest`,
  version injected via `--stamp` / `workspace_status` (so version bumps no longer bust
  the cache by mutating `Cargo.toml`).
- The geoip layer (currently a time-dependent DB-IP download) becomes a pinned
  external artifact (`http_file` / oci layer by digest) or a deliberate non-Bazel
  step — don't let it silently break reproducibility.
- Base layers pulled by digest; no Docker daemon, Buildx, or QEMU.

### Phase 4 — Remote cache

Point Bazel at a remote cache shared between CI and local dev so a version bump or a
one-file edit recompiles only affected units, not the whole `rocksdb`/`jemalloc`
graph. Kura itself speaks the Bazel Remote Execution API (`bazel-remote-apis`
dependency), so a Kura-backed remote cache is dogfooding. On the persistent
`tuist-linux` runner even a local disk cache stays warm across runs.

## Open questions / risks

- **rocksdb under Bazel** is the gating risk (Phase 0).
- **Cross sysroot for `aarch64-linux-gnu`** must be hermetic and Bookworm-based; the
  C deps link `libstdc++`.
- **protobuf codegen** may or may not need a `protoc` toolchain — to confirm in
  Phase 0.
- **Bazel vs. Buck2** — both are pinned in `mise.toml`. This plan assumes
  `rules_rust` + `rules_oci` (the more mature path today). The same native-cross + OCI
  story is achievable with Buck2 (reindeer + the buck2 prelude) if that becomes the
  target.
