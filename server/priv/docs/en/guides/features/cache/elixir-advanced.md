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
compiler pipeline with pure Elixir sources. Native/custom compilers, custom
tracers, source symlinks, umbrella roots and chains containing local dependencies
compile normally. Tuist's own bootstrap dependencies also compile normally.
Structural eligibility does not prove that arbitrary compilation code is hermetic.

## Declare additional inputs

Source trees, locked dependency identities, upstream sources and BEAMs,
explicit effective application configuration, compiler options, Mix environment
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
architecture, word size and byte order. Inputs are captured before each lookup
and checked again before publication, including changes from earlier compilations.

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
