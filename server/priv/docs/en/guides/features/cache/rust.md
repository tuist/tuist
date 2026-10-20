---
{
  "title": "Rust cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share eligible Cargo compilation outputs across builds with Tuist's experimental local and remote compilation cache."
}
---
# Rust cache {#rust-cache}

Tuist's experimental Cargo cache reuses verified compilation outputs locally and through your project's remote cache. Run your usual Cargo commands through Tuist:

```sh
tuist cargo build --release
tuist cargo check --workspace
```

Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link> to configure your project and authenticate. There is no extra tool to install or `[cargo]` configuration section. You can also configure a mise Cargo wrapper to keep typing `cargo`.

> [!WARNING] Experimental compilation cache
> The cache is not production-qualified across arbitrary workers, toolchains, SDKs, or build-script inputs. Executable and native-link restores remain disabled while a macOS verification divergence is investigated. Unsupported or unavailable cache paths fall back to compilation.

## What is cached {#what-is-cached}

Official CLI bundles include Tuist's internal native cache runtime, based on the Mr. Boxington cache model. It retains Rust library caching, dependency and workspace input tracking, build-script modeling, and eligible C/C++ compilation invoked by Cargo builds. A hit requires validating discovered inputs and the complete recorded output closure; a prediction alone never authorizes reuse.

The runtime also retains advisory predictions, bounded speculative prefetching, verification, background publication, and local garbage collection. These mechanisms do not guarantee that a crate is cacheable or that a build will be faster. Remote prediction updates can race without making an unvalidated result reusable.

Cargo still owns its arguments, toolchain, target directories, incremental settings, output, and exit status. Incremental compilations and unsupported inputs can bypass caching. Tuist does not enable the copied application's scheduler, managed target placement, learned incremental rewriting, or standalone commands.

If the bundled runtime is missing or incompatible, Tuist keeps its Swift cache as a fallback. That fallback caches only eligible registry leaf libraries, excludes build scripts, procedural macros and dependencies on other crates, and retains absolute checkout paths in its keys. Source-built CLIs without the native helper therefore have narrower coverage than official bundles.

## Share outputs in CI {#share-outputs-in-ci}

Tuist discovers the project's Kura endpoint and uses its existing authentication and Remote Execution API. Remote credentials are refreshed privately and are not included in build analytics. If remote setup fails, local caching remains available.

Remote publication is limited to protected GitHub branch-push jobs. Local commands and other invocations consume remote results and populate their local cache, but do not publish remotely. Cache writers are trusted code producers: content digests detect corruption, not malicious compiled code. Do not expose cache-write credentials to untrusted jobs.

Cache reuse depends on the actual compiler, inputs, flags, and environment, not just `Cargo.lock`. This experimental integration does not promise relocation across arbitrary checkout paths or independent workers.

## Inspect cache activity {#inspect-cache-activity}

Open **Cargo Cache** in the project sidebar to compare hit rates and recorded transfer, latency, and throughput measurements. Use the date and environment filters, switch between daily trends and individual-build hit rates, or open a recent build's **Cache** tab.

- **Cacheable Tasks** shows recorded reuse decisions and referenced outputs.
- **CAS Outputs** shows recorded artifact transfers, presence checks, and failures.

**Hit** means outputs were reused. **Missed** includes cold compilations and verification rebuilds. Hits do not identify a local or remote origin. Prefetches do not count as task reuse, and estimated compiler work avoided is not elapsed build time saved. Background-store timings do not measure remote publication completion.

Inspection records are bounded and may be partial. Builds without measurements remain unavailable rather than counting as zero. See <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust Build Insights</.localized_link> for the build-level measurements.

## Local storage and troubleshooting {#local-storage}

The native and Swift caches use separate project-scoped directories under Tuist's cache root. The native runtime collects its own action/blob entries; shared Tuist retention can reclaim idle native project caches after 30 days or under the support-cache byte budget. Active native sessions refresh their project lease so shared retention does not delete live cache-agent locks.

On managed runners, the native collector also uses the staged support-cache byte share as its maximum total size. Collection is periodic, not a per-write hard quota.

Enable debug output to diagnose setup and reporting failures:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

A cache failure must not replace Cargo's result or cause Cargo to run twice.
