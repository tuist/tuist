# Bazel remote cache: how it works, setup, and self-hosted or managed

Tuist provides a managed Bazel remote cache that developers, CI runners, and coding agents share, so a build downloads action results another machine already produced instead of running them again. Connect a workspace with `tuist bazel setup` and Bazel talks to the cache over its standard Remote Execution API, with short-lived credentials, compressed transfers, and a dashboard that shows the hit rate and what each invocation fetched. Keep your `BUILD` files and your usual `bazel build` and `bazel test` commands.

Improve the project first and the environment second. A remote cache only helps when the same action produces the same key on every machine, so measure hit rates and fix the inputs that differ before adding cache capacity, larger runners, or more parallelism.

## How a Bazel remote cache works

Bazel breaks a build into actions, such as compiling a file or running a test. Each action has declared inputs, a command line, and environment variables, and Bazel hashes them into an action key. Bazel's [remote caching guide](https://bazel.build/remote/caching) describes two stores:

- The **action cache** maps action keys to action results: the output names and the hashes of their contents.
- The **content-addressable store (CAS)** holds the output files, keyed by the hash of their contents.

Before running an action, Bazel looks up its key. On a hit it downloads the result, or only the outputs it needs, and skips the action. On a miss it runs the action and, when allowed, uploads the result. Hits only happen when the inputs match exactly, so an absolute path, timestamp, or environment variable that differs between machines gives every machine its own keys.

Bazel speaks two protocols to a cache. The **HTTP protocol** stores action results under `/ac/` and files under `/cas/` with plain `GET` and `PUT` requests, so any HTTP server that supports both can serve as a basic cache. The **gRPC protocol** is the cache part of the [Remote Execution API](https://github.com/bazelbuild/remote-apis) (REAPI), which adds batched lookups, streamed uploads, and compressed transfers.

Three related ideas are often confused:

- **Disk cache versus remote cache.** `--disk_cache` keeps action results in a directory on one machine, which helps when switching branches or working in several checkouts. A remote cache shares results between machines. Bazel can use both together.
- **Remote cache versus remote execution.** A remote cache reuses results that already exist. Remote execution runs cache misses on other machines. Configuring a cache does not run anything remotely.
- **Remote cache versus saving Bazel directories in CI.** Restoring an output base or disk cache from a CI cache moves a whole archive in and out of each job. A remote cache transfers only the results of matching actions. [Bazel on GitHub Actions](/marketing-markdown/solutions/bazel-github-actions) compares the two on ephemeral runners.

## How Tuist addresses it

- **A managed REAPI cache.** The [Tuist Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) serves Bazel's remote cache over gRPC from the cache region closest to the machine that ran setup. Developers, CI, and agents in the same project read and write the same action results.
- **Authentication without stored passwords.** Setup configures a credential helper that exchanges the machine's Tuist session for short-lived, project-scoped cache tokens. On GitHub Actions, CircleCI, and Bitrise, the CLI can exchange the job's [OIDC token](/en/docs-markdown/guides/server/authentication) instead of a long-lived secret.
- **Smaller transfers.** Setup turns on `--remote_cache_compression`, so blobs travel zstd-compressed. It also routes dependency archive downloads through the cache's Remote Asset API with local fallback, so a fetched archive is served from the cache on later builds; `--no-remote-downloader` opts out.
- **Evidence for every invocation.** The project's **Bazel Cache** page shows transfer volume, read and write latency, throughput, and the action-cache hit rate. Each invocation separates action-cache lookups from CAS downloads, so a cold action cache looks different from a slow download. With [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel), which setup also enables, the same invocation shows its critical path and the actions that dominated it. Pass `--no-build-insights` for a cache-only configuration.
- **One platform across build systems.** The same account serves the [Gradle](/en/docs-markdown/guides/features/cache/gradle-cache) and [Xcode](/en/docs-markdown/guides/features/cache/xcode-cache) caches, so organizations running several build systems manage one cache and one set of insights.

## Set up a Bazel remote cache with Tuist

[Install the Tuist CLI](/en/docs-markdown/guides/install-tuist) on macOS or Linux, then run this from the root of the Bazel workspace:

```sh
tuist init      # or: tuist auth login && tuist bazel setup
bazel build //...
```

Setup writes `.bazelrc.tuist` with the remote cache, credential helper, compression, and Build Event Service settings, and adds `try-import %workspace%/.bazelrc.tuist` to `.bazelrc`. Commit the `try-import` line and `tuist.toml`, and add `.bazelrc.tuist` to `.gitignore`: it holds a machine-local credential-helper path and the nearest cache region, so every developer machine and CI job runs `tuist bazel setup` itself. Setup leaves a `.bazelrc` alone when it already configures a remote cache. The [Bazel getting-started guide](/en/docs-markdown/guides/get-started/bazel-project) covers the full flow, and the [CI guide](/en/docs-markdown/guides/integrations/continuous-integration) covers authentication per provider.

These Bazel flags shape how any remote cache behaves, including Tuist's:

| Flag or tag | What it does |
| --- | --- |
| `--remote_cache=grpcs://…` or `https://…` | Points Bazel at the cache and selects gRPC or HTTP. |
| `--credential_helper`, `--remote_header` | Supplies credentials or headers to the cache. Tuist setup writes both. |
| `--remote_cache_compression` | Sends blobs zstd-compressed when the server supports it. |
| `--remote_download_toplevel` | Downloads only top-level outputs (Build without the Bytes), the default since [Bazel 7](https://blog.bazel.build/2023/12/11/bazel-7-release.html). |
| `--remote_upload_local_results=false` | Reads from the cache without writing to it. |
| `--disk_cache` | Adds a local cache directory in front of the remote cache. |
| `no-remote-cache` tag | Keeps a target's actions out of the remote cache. |

## Self-hosted or managed

A remote cache stores your build outputs, so the choice is mostly about who operates it and where the bytes live:

| Option | What you operate | Notes |
| --- | --- | --- |
| HTTP server or object storage, such as nginx with WebDAV or Google Cloud Storage | Storage, eviction, TLS, and credentials | The [Bazel guide](https://bazel.build/remote/caching) documents both. HTTP only, without gRPC batching. |
| An open-source cache server, such as [bazel-remote](https://github.com/buchgr/bazel-remote) | Servers, disks, upgrades, authentication, and monitoring | bazel-remote serves HTTP and gRPC from a size-limited disk cache, can proxy to S3, GCS, or Azure, and supports htpasswd and mTLS authentication. |
| Tuist managed cache | Nothing beyond `tuist bazel setup` | Regional endpoints, token-based access, per-invocation evidence, and the same account for Gradle and Xcode caches. |
| Tuist with [self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) | Cache nodes on your Kubernetes cluster or hosts | Artifacts stay on your disks, near your runners or offices, and nodes replicate to each other. Nodes run [Kura](https://github.com/tuist/tuist/tree/main/kura), Tuist's AGPL-licensed cache server, from a Helm chart or container image. Connecting nodes to Tuist is available on the Enterprise plan; you can also run Kura yourself, for example locally. |

Teams that must keep everything on their own infrastructure can also self-host the Tuist server on the Enterprise plan. Compare total cost, not only storage: include the hours spent on upgrades, capacity, and incident response, the network egress your provider charges, and Tuist's metered cache downloads on the live [pricing table](/pricing).

## Diagnose

Run the same commit twice on two different machines, for example a CI job and a developer laptop, then compare the second run's hits and transfers.

| Symptom | First investigation | Reference |
| --- | --- | --- |
| Hit rate stays low on repeat builds | Inputs that differ between machines: absolute paths, timestamps, stamped version info, environment variables passed with `--action_env`, or different toolchains. | [Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) |
| CI hits but laptops miss | Flags that change between environments, such as `--config`, `--compilation_mode`, or the host platform; actions built for different platforms have different keys. | [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel) |
| Hits are high but builds stay slow | Download volume and latency on the invocation page, then the critical path; consider `--remote_download_toplevel` and compression. | [Bazel build insights](/en/docs-markdown/guides/features/build-insights/bazel) |
| Builds stall before the first action | Dependency fetching and analysis; check whether the remote downloader is serving archives. | [Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) |
| Authentication errors | Whether this machine ran `tuist bazel setup` itself, and whether CI authenticated before setup. | [Authentication](/en/docs-markdown/guides/server/authentication) |

## Investigate with an agent

Connect the [Tuist MCP server](/en/docs-markdown/guides/features/agentic-coding/mcp) to your coding agent and ask it why a build missed the cache. `list_bazel_invocations` finds invocations by branch, commit, or CI, `get_bazel_invocation` returns build metrics, remote-cache totals, and critical-path diagnostics, and `list_bazel_cache_events` shows the cache traffic behind one invocation. Ask for the actions that missed, the input that most likely differed, and one fix with a before/after measurement.

The MCP credential is separate from Bazel's cache credentials; the agent should read `get_bazel_integration_guide` before changing the Bazel configuration. Reading evidence does not authorize changes, so review proposed edits before applying them.

## First experiment

1. Run `tuist bazel setup` on a branch, keeping the current configuration as the baseline.
2. Build the same commit twice in CI and once on a developer machine.
3. Compare wall-clock time, action-cache hit rate, and download volume on the **Bazel Cache** page and in [build insights](/en/docs-markdown/guides/features/build-insights/bazel).
4. Fix the largest source of misses, then measure again before changing runners or adding capacity.

## Further reading

- [Bazel with Tuist](/marketing-markdown/build-systems/bazel) on what Tuist adds to Bazel.
- [Bazel on GitHub Actions](/marketing-markdown/solutions/bazel-github-actions) for ephemeral runners and OIDC.
- [Remote caching for Bazel](/blog/2026/09/09/bazel) on how the Tuist cache works.
- [BuildBuddy](/marketing-markdown/compare/buildbuddy) and [EngFlow](/marketing-markdown/compare/engflow) comparisons, and the [slow builds](/marketing-markdown/solutions/slow-builds) guide.

## Frequently asked questions

### Is there a free Bazel remote cache?

Tuist's Air plan is free within its tier limits, includes the Bazel cache, and needs no credit card. The live [pricing table](/pricing) lists the current allowances; under the newer billing model, cache downloads are metered and uploads and storage are free. Open-source servers such as bazel-remote, or Tuist's own [Kura](https://github.com/tuist/tuist/tree/main/kura), are free to run yourself, and you pay for the machines, storage, and time to operate them.

### Can I use S3 as a Bazel remote cache?

Bazel talks to a cache over HTTP or gRPC, not the S3 API. You can put a server in front of a bucket, such as bazel-remote with its S3 proxy backend, or use a managed cache such as Tuist's, which needs no bucket or server.

### How does Bazel authenticate to a remote cache?

Bazel supports credentials in the cache URL, headers with `--remote_header`, mTLS, Google credentials, and external credential helpers with `--credential_helper`. Tuist setup configures a credential helper that issues short-lived, project-scoped tokens, and CI can authenticate with OIDC on GitHub Actions, CircleCI, and Bitrise instead of a stored secret.

### Does a remote cache give me remote execution?

No. A remote cache reuses results that already exist; every cache miss still runs on the machine that ran Bazel. Remote execution is a separate service that runs those misses elsewhere; Tuist offers it on Linux executors to enabled accounts, so [email us](mailto:contact@tuist.dev) or [book a call](https://cal.tuist.dev/team/tuist/tuist) to enable it. Measure your hit rate and critical path first, because avoided actions help on any machine.

### Should developers write to the shared cache, or only CI?

Bazel's [remote caching guide](https://bazel.build/remote/caching) recommends limiting who can write to a shared cache, for example to CI only, because anyone who can write can change what others download. Developers can read with `--remote_upload_local_results=false`. Decide based on who can change the code that runs in each environment.

## Sources and review

Sources checked on **2026-11-16**: [Bazel remote caching](https://bazel.build/remote/caching), the [Remote Execution API](https://github.com/bazelbuild/remote-apis), the [Bazel 7 release notes](https://blog.bazel.build/2023/12/11/bazel-7-release.html), and the [bazel-remote README](https://github.com/buchgr/bazel-remote). Written by Tuist.
