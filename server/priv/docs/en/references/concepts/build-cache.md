---
{
  "title": "What is a build cache? Local and remote build caches explained",
  "titleTemplate": ":title · Tuist",
  "description": "A build cache reuses outputs of earlier builds. How local and remote build caches work in Xcode, Gradle, and Bazel, what Xcode caches are, and when caching pays off."
}
---
# What is a build cache? {#what-is-a-build-cache}

A build cache stores the outputs of individual build steps, such as compiled object files, modules, libraries, or test results, under a key computed from everything that went into producing them: source files, compiler flags, dependencies, environment, and toolchain version. When a later build needs a step whose inputs produce the same key, the build system takes the stored output instead of running the step again. A **local build cache** lives on one machine and speeds up that machine's later builds. A **remote build cache** is a shared server that many machines read from and write to, so a CI job, a teammate, or a coding agent can reuse outputs that someone else already built.

## Build cache, incremental build, and CI cache {#build-cache-incremental-build-and-ci-cache}

Three ideas are often called "the cache", and they behave differently:

- **Incremental builds** reuse the outputs that are already sitting in your own build directory and rebuild only what changed since the last build in that directory. They usually rely on file timestamps or a dependency graph kept with the build products. Switching branches, moving the checkout, or starting from a fresh machine loses that state.
- **A build cache** looks outputs up by the content of their inputs, not by what happened to be built last in the same directory. That makes outputs reusable across branches, checkouts, and machines, as long as the inputs match.
- **CI directory caching** (for example `actions/cache` on GitHub Actions) saves a directory at the end of a job and restores it at the start of the next one, under a key you choose, such as a lockfile hash. It is a file transfer, not a build cache: the build system still decides what to rebuild, and a restored directory can be partly or entirely stale.

Dependency caches, such as downloaded packages or a Gradle or Swift package cache, are different again: they save the network fetch, not the compilation.

## How a build cache works {#how-a-build-cache-works}

Build systems that support caching split the build into steps (Bazel calls them actions, Gradle calls them tasks) and do the same thing for each one:

1. **Compute a cache key.** The build system hashes every input that can affect the output: the contents of input files, the command line or task configuration, relevant environment variables, and the toolchain.
2. **Look the key up.** It checks the local cache first and, if one is configured, the remote cache.
3. **Hit or miss.** On a hit, it downloads or copies the stored outputs and skips the step. On a miss, it runs the step and, if allowed, uploads the outputs under that key.

Most caches store outputs in **content-addressable storage** (CAS), where each blob is stored under the hash of its own content, plus a separate index from cache keys to the outputs they produced. Identical files are stored once, and a client can verify what it downloaded.

The model has one strict requirement: the key must include every input that changes the output. If a step reads an input the build system does not know about, such as an undeclared file, an environment variable, the current time, or a tool installed on the machine, the cache can return an output that does not match the current inputs. Build systems call steps that only depend on declared inputs **hermetic**. The opposite problem is more common and less dangerous: a key that includes something irrelevant, such as an absolute path or a timestamp, produces a different key on every machine, so the cache never hits.

## How build caches work per build system {#how-it-works-per-build-system}

### Gradle build cache {#gradle}

The [Gradle build cache](https://docs.gradle.org/current/userguide/build_cache.html) stores the outputs of cacheable tasks, such as Java and Kotlin compilation and test execution, keyed by the task's type, implementation, input properties, and normalized input files. It is off by default. Enable it with `org.gradle.caching=true` in `gradle.properties` or with `--build-cache` for a single build.

- **Local.** The built-in local cache is a directory in the Gradle user home (`~/.gradle` by default). It is enabled once the build cache is on, and Gradle periodically removes entries that have not been used recently.
- **Remote.** A remote cache is configured in `settings.gradle(.kts)`, for example with `HttpBuildCache`. Gradle downloads outputs from the remote cache on a local miss and stores them locally for next time. The remote cache does not accept uploads by default; a common setup lets CI push (`isPush = true` when running in CI) and developer machines only read.

Gradle reports a task restored from the cache as `FROM-CACHE`, which is different from `UP-TO-DATE`: up-to-date means Gradle's incremental build found the task's outputs already in place, without consulting the cache. The configuration cache is a third, separate feature that caches the result of the configuration phase, not task outputs.

### Bazel remote cache {#bazel}

Bazel caches every action. Its action cache maps an action's key, a digest of its command line, environment, and input files, to the action's outputs, and the outputs themselves live in a content-addressable store.

- **Local.** Bazel keeps an action cache and the build outputs in its output base, which gives you fast incremental builds in one workspace. `--disk_cache=<path>` adds a disk cache that is shared across workspaces and branches on the same machine.
- **Remote.** `--remote_cache=grpcs://…` (or `https://…`) points Bazel at a remote cache that implements the [Remote Execution API](https://github.com/bazelbuild/remote-apis) or a plain HTTP cache. `--remote_upload_local_results=false` makes a machine read-only, which is how many teams keep developer machines from writing to the shared cache. `--remote_download_minimal` or `--remote_download_toplevel` ("build without the bytes") avoids downloading intermediate outputs that the local build never needs.

Bazel also caches test results: a test whose inputs have not changed is reported as `(cached) PASSED` without running. A remote cache is not the same as remote execution, where actions also run on remote machines; a cache only stores results.

### What are Xcode caches? {#xcode}

Xcode uses several caches and directories that are easy to confuse. The ones that affect build times are:

- **DerivedData** (`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`) holds each project's build products, intermediate files, index, logs, and resolved Swift packages. It is the state that incremental builds reuse. Deleting it is safe, but the next build of that project is a full rebuild, and indexing and package resolution run again.
- **The Clang module cache** (`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`) holds precompiled Clang modules (`.pcm` files) for imported C and Objective-C modules and SDK frameworks, shared between projects. With explicitly built modules enabled, Xcode instead builds modules as regular build tasks and keeps them with each project's intermediates. Deleting it is safe; modules are rebuilt on demand.
- **The compilation cache** (Xcode 26 and later, `CompilationCache.noindex` inside DerivedData by default, configurable with `COMPILATION_CACHE_CAS_PATH`) holds content-addressed compilation outputs for Swift, C, and Objective-C when `COMPILATION_CACHE_ENABLE_CACHING = YES`. Deleting it is safe; compilations that could have been replayed run again.
- **The Swift Package Manager cache** (`~/Library/Caches/org.swift.swiftpm/`) holds downloaded package repositories and manifests shared across projects. Deleting it is safe; packages are fetched again.

Other large directories under `~/Library/Developer` are not build caches but often come up when cleaning disk space: `Xcode/Archives` holds archived app builds and their debug symbols (keep the ones you may need to symbolicate crashes), `Xcode/iOS DeviceSupport` holds symbols for connected devices' OS versions, and `CoreSimulator/Devices` holds simulators and their data (`xcrun simctl delete unavailable` removes simulators for runtimes that are no longer installed).

DerivedData is Xcode's incremental build state, not a content-addressed cache: it is tied to the project's location on disk and to file timestamps. Restoring DerivedData from a CI cache at a different path, or after a fresh checkout changes every file's modification time, often leads to a full rebuild anyway.

The **compilation cache**, introduced in Xcode 26, is Xcode's build cache in the sense of this page. It stores compilation results by the content of their inputs and replays them on a hit, so outputs survive branch switches and cleaned build products. It caches compilation, not every build step: linking, resource processing, and script phases still run. By default the store is local to one machine and lives inside DerivedData, so deleting all of DerivedData throws it away; deleting only a project's build products keeps it. Xcode can also connect the compilation cache to a remote cache service through a plugin (`COMPILATION_CACHE_ENABLE_PLUGIN` and `COMPILATION_CACHE_REMOTE_SERVICE_PATH`), which turns it into a shared remote cache.

Before the compilation cache, Xcode projects reused work across machines mostly by **binary caching** whole modules: building dependencies as prebuilt frameworks or XCFrameworks and linking those instead of compiling the sources. This works at the granularity of a module rather than a compilation, and it changes how the project is built.

## Latency, blob size, and blob count {#latency-blob-size-and-blob-count}

A remote cache hit is not free. Fetching an output costs a fixed delay for every request that has to wait for the previous one, plus the time to move its bytes:

**time ≈ R × L + S / B**

where *R* is the number of round trips that cannot overlap, *L* is the round-trip latency to the cache, *S* is the number of bytes transferred, and *B* is the bandwidth. Which term dominates depends on how the build system cuts its work into blobs:

- **Few, large blobs are bandwidth-bound.** Caches that store coarse outputs, such as a Gradle task's packed outputs or a prebuilt framework in a binary module cache, make fewer requests that each move megabytes. A 200 MB set of outputs takes about 16 seconds at 100 Mbit/s and under 2 seconds at 1 Gbit/s, while a few extra milliseconds of latency barely matter.
- **Many small blobs are latency-bound.** Fine-grained caches, such as Bazel's per-action cache and Xcode's compilation cache, make thousands of requests for blobs of a few kilobytes, many of them only to ask whether a key exists. With 2,000 lookups, 8 in flight at a time, and 40 ms of latency, a build waits about 10 seconds on round trips alone, regardless of how small the blobs are. With 2 ms of latency, the same lookups take about half a second. More bandwidth does not help here; a closer cache does.
- **Misses cost a round trip too.** Every lookup that misses adds latency without saving any work. A distant cache with a low hit rate can make a build slower than having no remote cache at all.
- **Volume multiplies both.** The number of blobs grows with the structure of the project: a graph of many small modules or targets produces more, smaller outputs than a few large ones. Splitting a project improves parallelism and invalidation, but it makes the build more sensitive to cache latency.

A hit is only worth it when fetching the output is faster than recomputing it, and that comparison changes with distance. A compilation that takes 50 ms locally is a good hit from a cache on the same network and a poor one from a cache on another continent. That is why the levers for remote caches are mostly about latency and request count rather than raw bandwidth:

- **Put the cache close to where builds run**, in the same region or network as CI runners, and as close as practical to developers.
- **Overlap requests.** Bazel's Remote Execution API batches existence checks (`FindMissingBlobs`) and small reads, and `--remote_max_connections` bounds concurrency. Xcode's `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` runs compilation cache lookups alongside the rest of the build instead of on its execution lanes. HTTP/2 multiplexes many requests over one connection.
- **Download less.** Bazel's `--remote_download_minimal` skips intermediate outputs, and a local cache layer, such as Bazel's `--disk_cache` or Gradle's local build cache, serves repeat hits without a network request.
- **Compress large blobs.** Bazel's `--remote_cache_compression` uses zstd when the cache supports it, which helps bandwidth-bound transfers and does little for latency-bound ones.

## Common pitfalls {#common-pitfalls}

- **Undeclared inputs.** A step reads a file, environment variable, or tool that is not part of its key. The cache can then return outputs built from different inputs. In Gradle, declare every input of custom tasks; in Bazel, keep actions hermetic and consider `--incompatible_strict_action_env` so the host `PATH` does not leak in.
- **Machine-specific keys.** Absolute paths, user names, and build timestamps embedded in inputs or outputs make keys differ between machines, so the remote cache never hits. Gradle's path sensitivity, Bazel's relative execution paths, and the Clang and Swift prefix-mapping settings in Xcode exist to remove those differences.
- **Volatile inputs near the root of the graph.** Stamping a build number, commit hash, or date into a module that everything depends on invalidates everything above it on every build. Inject volatile values as late as possible, ideally only into release builds.
- **Toolchain mismatches.** Different compiler, JDK, or Xcode versions produce different keys. That is correct behavior, but a fleet with mixed versions effectively splits the cache.
- **Poisoned or untrusted writes.** A developer machine with uncommitted changes or a non-hermetic setup can upload outputs that others then reuse. Many teams let only CI on trusted branches write to the remote cache and make every other machine read-only. Builds of untrusted pull requests should not write to a cache that trusted builds read.
- **Ignoring transfer cost.** A step that takes 50 milliseconds to run can take longer to fetch from a distant cache. See [Latency, blob size, and blob count](#latency-blob-size-and-blob-count).
- **Hidden test runs.** Caching test results is correct when tests are deterministic, but it also means a flaky test that passed once keeps passing without running. See <.localized_link href="/references/concepts/flaky-test">What is a flaky test?</.localized_link>.

## How to measure a build cache {#how-to-measure-a-build-cache}

A cache is worth what it saves end to end, not its hit rate alone:

- **Hit rate, weighted by work.** Count hits and misses per step, but weight them by how long each step takes to run. A 95% hit rate on cheap steps can save less than a 50% hit rate on the slowest compilations.
- **Cold, warm, and typical builds.** Compare a build with an empty cache, a build with a fully warm cache, and the builds people actually run, such as CI on a pull request after a small change. The last one is the number that matters.
- **Time spent on the cache itself.** Measure request count, latency, bytes, and the time spent downloading and uploading. If most of that time is waiting on many small requests, a closer cache helps more than more bandwidth; if it is moving a few large blobs, bandwidth and compression matter more.
- **Why misses happen.** Compare cache keys for the same step on two machines. Gradle can print the inputs behind each key with `-Dorg.gradle.caching.debug=true`, Bazel can write execution logs (`--execution_log_compact_file`) that you can diff between two builds, and Xcode reports compilation cache hits and misses in the build log when `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES`.

## When it isn't worth it {#when-it-isnt-worth-it}

A build cache adds infrastructure, a security boundary, and a new class of bugs. It is not always the right tool:

- **Small or fast builds.** If a clean build takes a minute, a remote cache saves little, and the network round trips can make it slower.
- **Builds that miss by design.** If most builds change an input near the root of the graph, the cache cannot help until that is fixed. Fix the invalidation first; a cache only skips work whose inputs match.
- **Persistent build machines.** A CI machine that keeps its build directory between jobs on the same branch already gets incremental builds. A shared cache helps when machines are ephemeral, when there are many branches, or when developers and CI should reuse each other's work.
- **Non-hermetic builds you cannot fix yet.** A cache that occasionally returns wrong outputs costs more trust than it saves time. Make the steps you cache reproducible first, or leave the problematic ones uncached (for example with Bazel's `no-remote-cache` tag).
- **Slow or distant networks.** If the cache is far from where builds run, measure transfer time before rolling it out to everyone.

## Build caching with Tuist {#build-caching-with-tuist}

[Tuist](https://tuist.dev) provides a remote cache that plugs into each build system's own caching, so developer machines, CI, and coding agents reuse each other's outputs, and it records hits, misses, and transfer times so you can measure the effect:

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> connects Xcode's compilation cache to a shared remote cache, for any Xcode project on Xcode 26 or later.
- <.localized_link href="/guides/features/cache/module-cache">Module cache</.localized_link> replaces whole modules with prebuilt binaries in projects generated with Tuist.
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle cache</.localized_link> and <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link> serve as a Gradle remote build cache and a Remote Execution API cache for Bazel.
- <.localized_link href="/guides/features/cache">Cache</.localized_link> lists every supported build system, including Elixir and Struo.
- [Slow builds](https://tuist.dev/solutions/slow-builds) is a practical guide to finding the work worth removing before choosing a cache.
- [The physics of build systems](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) and [Kura](https://tuist.dev/blog/2026/09/14/kura) explain, with measurements from Tuist's cache, how artifact size and request volume differ between the module cache, Xcode's compilation cache, Bazel, and Gradle.
