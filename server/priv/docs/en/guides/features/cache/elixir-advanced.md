---
title: Advanced Elixir cache configuration
titleTemplate: ":title · Cache · Guides · Tuist"
description: Configure additional compilation inputs, dependency selection and portable reuse.
---

# Advanced Elixir cache configuration

Start with <.localized_link href="/guides/features/cache/elixir">the Elixir cache setup guide</.localized_link>.
The options below are only needed when your project has additional compilation
inputs, dependency exceptions or different checkout paths.

## Select dependencies

`cache: true` caches supported dependencies automatically. A keyword list has the
same automatic selection, with optional overrides:

```elixir
cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
```

To limit caching to specific dependencies instead:

```elixir
cache: [dependencies: [:nimble_options, :nimble_parsec]]
```

`dependencies: :all` explicitly selects all supported dependencies;
`dependencies: []` selects none. `exclude:` takes precedence over either selection.
Omitting `cache`, or setting it to `false` or `nil`, disables caching.

Supported dependencies are fetched through Hex or Git and use the standard Mix
compiler pipeline with Elixir/Erlang sources, or rebar3's ordinary pure-BEAM
compilation. Mix dependencies can also reuse artifacts when their upstream
dependencies use rebar3. Rebar configuration, source/header files and the rebar3
executable fingerprint participate in keys. Packaged `ebin/*.app` metadata and
passive Makefiles are supported too. Rebar configuration scripts have already
been evaluated by Mix before lookup; their source and effective configuration
enter keys. Application source scripts (`*.app.src.script`) are evaluated later
by rebar3 and require an audited builder contract, as do build plugins and
compilation hooks. A missing rebar3 launcher is installed before fingerprinting,
using Mix's normal installer; cold workers still need access to that installer.

Custom tracers, source symlinks, umbrella roots and chains containing local
dependencies compile normally. Tuist's own bootstrap dependencies also compile
normally on cold workers. Structural eligibility does not prove that arbitrary
compilation code is hermetic.

## Declare additional inputs

Source trees, locked dependency identities, upstream sources, BEAMs and resources,
dependency runtime/optional/application flags, resolved application metadata,
explicit effective application configuration, compiler options (including lexer
and parser options), Mix environment
and target, and toolchain identity are included automatically. Dependency-specific
`env:` and `system_env:` enter the key and configuration is evaluated under that
environment. Application defaults enter through source inputs, not VM loading state.

For dependencies that read files outside their source tree or additional
environment variables at compile time, declare those inputs:

```elixir
cache: [
  inputs: ["schemas", "config/compiler-input.json"],
  env: ["YOUR_COMPILER_OPTION"]
]
```

Elixir macros and module bodies can read arbitrary files, environment, ambient
code paths, network responses and time. Tuist does not automatically discover
these reads. Changing undeclared inputs can produce stale outputs. Exclude
dependencies with time/network-dependent compilation or side effects that must
execute on every build; use `dependencies:` for an audited dependency allowlist
when you need tighter control.

Standard compiler/runtime variables (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`,
`ERL_AFLAGS`, `ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH`
and `MIX_ARCHIVES`) are captured automatically. Toolchain identity includes the
Elixir build, full OTP version when available, ERTS, compiler bytecode, OS/version,
architecture, word size and byte order. The effective context is captured before
each lookup. Per-dependency input models may be shared for lookup planning within
one preparation; compilation clears the plan and restoration invalidates the
installed application's records. Staged installation and publication always check
fresh inputs without reusing the lookup plan. A lookup miss also captures a fresh
key before compilation. Changed inputs reject a staged hit rather than installing
code built for the earlier inputs.

Keys use deterministic term encoding and sorted filesystem traversal. Unordered
builder declarations and declared input sets are sorted and deduplicated; ordered
compiler options retain their order. File contents, names, executable bits and
missing paths matter, not filesystem timestamps. File declarations do not model
ownership, timestamps or other filesystem metadata; exclude builders that derive
outputs from those values. Upstream compiler manifests are
excluded as incremental bookkeeping; code that deliberately reads their contents
must declare them as additional inputs. Regex configuration uses its source and
options, never VM-local compiled references. Other opaque runtime values bypass
caching. Updated key models invalidate older entries without a migration.

Deterministic key encoding is separate from deterministic compiler output. If
upstream BEAM metadata changes between otherwise identical builds on recent
Elixir versions, consider setting `ERL_COMPILER_OPTIONS='[deterministic]'` before
SDK bootstrap, seeding and cache consumption. Merge it with any existing compiler
options and rebuild dependency outputs once when changing the setting. The SDK
does not set it automatically; its exact value remains part of the key. Complete
upstream bytes are still hashed, not normalized or stripped. This is not a
cross-checkout or arbitrary-builder reproducibility guarantee. The compiler option
also omits source/options from `module_info(:compile)`, so validate coverage,
debugging and source-discovery tools before adopting it.

Lexer and parser outputs are treated as derived files only when they are absent
from the locked Git tree or Hex package file manifest. Shipped `.erl` files and
opaque directory/submodule contents remain ordinary inputs; regenerated shipped
files must pass the same post-staging input reconciliation. Generator templates
from OTP's `parsetools` also enter toolchain identity. Keep dependency source
checkouts isolated between concurrent builds: generators and native builders may
write into `deps/`. Nested/custom rebar generator layouts may still need an
audited `generated` declaration.

## Native and custom builders

For an audited Mix, rebar3 or Make builder, declare a per-dependency contract:

```elixir
cache: [
  builders: [
    bcrypt_elixir: [
      platform: "build-image@sha256:YOUR_IMMUTABLE_IMAGE_DIGEST",
      outputs: ["priv/bcrypt_nif.so"],
      tools: ["cc", "make"],
      env: ["YOUR_BUILDER_OPTION"]
    ]
  ]
]
```

`platform` identifies the compatible native build environment. Use an immutable
image/toolchain identity covering compilers, SDKs, system headers and shared
libraries, not a reusable label such as `linux`. Elixir/OTP and the usual
platform checks still apply. This is an explicit audit of the builder, not
automatic discovery of native inputs or required side effects. Invalid explicit
builder contracts raise an actionable configuration error instead of silently
leaving caching disabled.

`outputs` lists required paths relative to the dependency's application build
directory. List the actual libraries/executables needed at runtime. Missing
outputs trigger restoration or compilation even if Mix considers the BEAMs
current; incomplete snapshots are rejected. Declare additional environment
variables with the builder's `env` and external files/directories with its
`inputs`, relative to the consuming project. Native keys automatically include
standard build environment variables such as `PATH`, `CC`, `CXX`, `CFLAGS`,
`LDFLAGS`, `SDKROOT` and `RUSTFLAGS`, using the dependency's effective `system_env`
overrides. Resolved Mix project configuration also enters native builder keys;
opaque function-valued configuration cannot be cached.

Optional `tools` names are resolved on that effective `PATH`; relative tool paths
are relative to the dependency source directory. The executable bytes and resolved
paths enter the key, and unavailable declared tools bypass caching. A launcher or
compiler wrapper fingerprint does not cover its SDKs, subprocesses or system
libraries: the immutable `platform` and additional `inputs` must cover those.
`MAKEFLAGS` is retained verbatim because custom builders can read it. Inherited
GNU make jobserver identifiers can therefore cause safe cache misses between
runs; use stable build flags in an isolated cache job rather than assuming those
values are removed from the key.

Some builders generate files under `deps/` instead of only `_build/`. List those
paths relative to that dependency's source directory in `generated`, for example
`generated: ["priv/native"]`. Only those generated paths are excluded from source
inputs. Do not exclude original resources or source files: they must remain
inputs. Paths are literal, without globs or traversal. The contract, platform,
additional inputs, environment values and any custom dependency compile command
all participate in keys. `compile: false` remains an opt-out from compilation.

Audited snapshots materialize source-backed `ebin`, `priv`, `include` and `src`
resources into the restored application. Native libraries, port executables,
headers and generated resources therefore survive a cold checkout, without
modifying its dependency sources. Executable modes and contained relative
resource symlinks are preserved; escaping, absolute and cyclic links are rejected.
All upstream application resources enter downstream keys, including ordinary
`priv` resources and custom output directories, not just native libraries or BEAMs.
Code that directly reads producer source paths is not relocated; builders with
mandatory side effects outside the application artifact still need those steps.

Keep custom builders excluded until their inputs and outputs are audited. A
contract does not remove cold SDK bootstrap compilation, the 64 MiB artifact
limit, or the need for a compatible build environment.

## Reuse across checkout paths

Checkout paths participate in keys by default. If your dependencies don't rely
on producer paths, opt into reuse between different checkout locations:

```elixir
cache: [portable: true]
```

Cached BEAMs retain producer debug/source paths and compile-time `__DIR__`,
`__ENV__.file` and `File.cwd!()` values. Portable reuse does not rewrite them.
Resource links point to the current source checkout. Upstream BEAM bytes also
enter keys and may embed paths, so reuse can require restoring the upstream
closure from the same cache rather than recompiling it independently.

## Storage and access

| Option | Default | Purpose |
| --- | --- | --- |
| `remote` | `true` | Use the shared remote cache after a local miss. |
| `upload` | `true` | Publish new bundles remotely. `false` still allows reads and local snapshots. |
| `path` | Tuist's cache directory, under `mix/dependencies/v1` | Choose a different local store. |
| `endpoint` | Discovered automatically | Override the account's HTTPS REAPI endpoint. |

`upload: false` controls client behavior, not authorization. Project cache
permissions are enforced by the server. Project `endpoint:` options and discovered
endpoints require HTTPS, except for loopback (`localhost`, `127.0.0.1`, `::1`)
development endpoints.

A nonempty `TUIST_CACHE_ENDPOINT` overrides both `endpoint:` and discovery. Hosted
runners use it to reach their private in-cluster cache. This operator-controlled
environment override also permits HTTP on non-loopback hosts. HTTP sends the
project-scoped cache token and artifacts unencrypted, so only use it on a trusted
network. An invalid override falls back to local snapshots without trying discovery.

Local snapshots and remote bundles are limited to 64 MiB; larger
artifacts compile without being cached. The local store has no automatic eviction;
remove its contents when needed. Remote artifacts use Kura's existing retention,
eviction and project-cleanup rules.

> [!IMPORTANT]
> Compiler manifests and BEAMs can embed producer paths and compile-time values,
> including secrets. Project cache readers can access those artifacts. Cache
> writers are trusted code producers: digest checks detect corruption, not
> malicious executable BEAMs. Don't expose cache-write credentials to untrusted
> PR jobs or compile untrusted dependencies with those credentials available.

## Troubleshoot missing hits

- Run `mix tuist.setup` after installing the package and commit the generated
  Mix configuration. Setup preserves other aliases and Tuist options; it refuses
  customized compile actions rather than silently removing them.
- Keep the generated compile alias. Direct `mix tuist.compile` task
  discovery can compile dependencies before caching can inspect them.
- Already-current, valid outputs for selected, supported dependencies count as
  local hits with reason `up_to_date`. They aren't published retrospectively and
  carry no artifact key, transfer bytes, restore latency or estimated time saved. To test a
  snapshot restore, clean just a supported dependency's build with
  `mix deps.clean NAME --build` after it has populated the cache, then compile again.
- Match `MIX_ENV`, `MIX_TARGET`, compiler settings and declared inputs. Path changes
  also change keys unless portable reuse is enabled.
- Unsupported dependencies appear as **Not cached**, not misses. They are excluded
  from hit rate. A build with neither lookups nor up-to-date local hits has an
  unavailable rate, not 0%.
- Missing credentials, unavailable endpoints and corrupt snapshots fall back to
  compilation. Compiler failures still fail the build.
- CAS records can arrive after the build report. Refresh to see newly ingested
  transfers. Local hits and legacy builds have no remote CAS outputs.

Servers need support for compile-report contract `0.2` to record `up_to_date`
local hits. If an older server explicitly rejects the cache data or a schema
enumeration value, the package retries the report once without these new reuse
observations. Compilation details and other cache results are preserved; the
new local reuse remains unavailable until the server is upgraded. Deploying the
server first avoids this extra request. The contract version does not negotiate
support, and authentication failures, transport failures and other validation
messages are not retried. Enumeration errors do not identify their field on older
servers; a retained invalid field still fails on the single retry.

## Manual compile integration

If setup cannot edit your project's configuration safely, integrate this alias
manually, preserving any custom compile actions:

```elixir
compile: [
  "deps.compile tuist_ex --include-children",
  "deps.loadpaths --no-compile --no-deps-check",
  "tuist.compile"
]
```

These steps compile and load Tuist before other dependencies, including on cold
parallel builds. The wrapper restores normal dependency checks afterward. The
same alias works with Hex, Git and path installations; no script path is needed.

For jobs that prepare an uploaded build and then run with `--no-compile`, guard
all bootstrap work too. Mix forwards arguments only to the final task of a list
alias, so its earlier `deps.compile` otherwise runs unconditionally. Use a local
function in your Mix project module instead:

```elixir
# In aliases/0:
compile: &compile/1

# In the same Mix project module:
defp compile(args) do
  if "--no-compile" not in args do
    Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
  end

  Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
  Mix.Task.run("tuist.compile", args)
end
```

This is a project-local function, not a capture of an SDK function that is not
loaded yet. Treat it as a custom integration: `tuist.setup` refuses customized
compile aliases rather than replacing them.

## How it works

Elixir caching uses the shared REAPI ActionCache/CAS pipeline, authentication and
Kura-signed analytics used by Bazel, not a separate Mix storage service. A modeled
input key references an ActionResult containing the raw-byte SHA-256 digest of a
complete compilation bundle. Tuist verifies its files, application metadata,
declared BEAMs and SCM manifest before staged installation. Corrupt entries are
repaired after successful compilation.

On OTP 28 and later, remote sessions negotiate zstd compression for ByteStream
transfers of at least 1 KiB. Incompressible uploads, older OTP runtimes and servers
without compression use identity transport. Digests, artifact limits and reported
bytes refer to uncompressed content. Decoded bytes are bounded and verified before
installation. Each dependency remains a single CAS bundle, avoiding per-file or
chunk requests for small artifacts.

Remote credentials/connections are resolved lazily; idle builds and local hits
(including already-current outputs) don't contact remote endpoints. One session is closed on every exit, including
compiler failure. Client RPCs have a 30-second deadline. Mix remains responsible
for lock checks, local dependency compilation and unsupported work.

Dashboard latency/bytes preserve local versus remote provenance and distinguish
unavailable values from measured zero. Remote timing measures client CAS transfers,
while local timing includes verification and installation; neither includes
compilation. CAS Outputs uses successful Kura-signed transfers, not local copies
or action-input keys. Throughput is bytes divided by measured time; compressed
sizes are unavailable. Estimated compilation time avoided is the producer's
original compile duration, not measured end-to-end build savings.

Independent, ready dependencies are fetched in windows of up to four concurrent
requests over the same HTTP/2 connection. This bounds decoded bundle buffering to
four artifacts, each subject to the 64 MiB limit. Key planning, Mix state and
installation remain serialized. Downstream keys wait for upstream artifacts;
prefetched bytes are consumed only under their exact input key, with inputs
rechecked before remote installation. Already-current outputs and local snapshots
do not cause speculative remote requests. Compilation and uploads remain serial
for selected cache misses; concurrency is not a promise that every build is faster.

## Can every dependency skip compilation?

A compatible hit can skip a supported dependency's compilation, but `cache: true`
is fail-open, not a zero-compilation guarantee. Missing/evicted entries,
unsupported builders and the cold SDK bootstrap can still compile. A high hit
rate alone does not establish a wall-clock speedup.

For build-once/test-many CI, use
<.localized_link href="/guides/features/test-sharding/elixir">Elixir test sharding</.localized_link>
to distribute the exact prepared build rather than expecting every worker to
reconstruct it from per-dependency cache hits. Reusing a complete build, especially
one containing native libraries, still requires a compatible platform, toolchain
and configuration. Arbitrary custom builds cannot safely skip their build steps
without modeling their external inputs, outputs and required side effects.
