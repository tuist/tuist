# Tuist with Struo

Tuist and [Struo](https://struo.run/) make scripts cacheable and bring caching to build systems that do not support it natively, without rewriting project sources or native build definitions. Struo support in Tuist is currently in canary; remote execution requires an enabled account and available capacity. Shared action results and live run/action reporting bring these workflows into the same productivity platform as Tuist's Xcode, Gradle, Bazel, and Mix integrations.

## One productivity platform, native depth

Embracing build-system diversity includes new action models, not just today's established toolchains. We believe Tuist is the best choice for organizations seeking one productivity platform across their build systems; the canary Struo integration extends that direction rather than introducing a disconnected productivity product.

For Struo, native depth means making existing work reusable, even when its build system has no native remote-cache integration. Keep the project and toolchain; Struo adds the action contract, Tuist shares compatible results, and live reporting exposes the work as it happens. Eligible graph command actions can also run on compatible Linux remote workers. See the [cross-build-system stance](/marketing-markdown/build-systems) for why one platform should embrace these workflows, not require a build-system migration.

## What Struo already does

- **Make scripts cacheable.** Declare a script's inputs, outputs, and relevant environment through Struo annotations. Struo records the result and restores the outputs when the same work is requested again. Existing automation becomes reusable rather than running from scratch on every invocation.
- **Add caching around an existing build command.** A Struo wrapper can run a command such as `npm run build`, declare the source files and lockfile as inputs, and capture the generated directory as an output. The underlying build system does not need a native cache protocol, and the project's sources and native build definitions stay unchanged.
- **Read existing project graphs.** For supported native projects, Struo discovers targets and dependencies from existing project files. You can try `struo query targets`, `struo build`, and `struo test` without rewriting the project into a new build language or creating `struo.toml` just for discovery.

Struo keeps the underlying compilers and SDKs. Its local cache works without a remote account; connect an infrastructure provider when those results should be shared across machines. Script annotations or wrapper configuration describe the action's inputs, outputs, and environment separately from the project's build definitions.

## How Tuist augments it

- **Reuse action results across people and environments.** The [Tuist provider](https://struo.run/docs/guide/infrastructure/tuist) connects Struo's declared actions to a shared cache. A developer, CI runner, or agent environment can restore a compatible result produced on another machine instead of only benefiting from its own local cache.
- **Extend acceleration beyond native cache integrations.** Scripts and build systems without a native remote cache can use the same shared action-result infrastructure. [Remote execution](/en/docs-markdown/guides/features/runners/struo) runs eligible graph command actions on `linux/amd64` workers for accounts with execution enabled and capacity. It requires a compatible Struo client/server, the advertised worker image, and actions prepared for that environment.
- **Follow work live.** Struo reports ordered run/action events to Tuist and prints a dashboard link as a run starts. The live view exposes recorded progress, cache decisions, and reported structured action errors; use CI logs for full command output. Tuist does not ingest Struo's raw action log stream.
- **Use authenticated team infrastructure.** The provider binds the repository to a Tuist account/project in `struo.toml`, with developer login and documented token or OIDC automation flows. This is independent of whether CI runs on Tuist Runners.

Project first, environment second still applies: improve the action boundaries and reuse compatible outputs before moving cache misses to larger or remote machines.

## First experiment

Follow [Struo getting started](https://struo.run/docs/guide/getting-started) to install [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) or later and make one script cacheable, or discover a supported existing project's targets. For a build command without native caching, create a Struo wrapper with declared inputs and outputs while leaving the project's sources and native build definitions unchanged. Existing Once users should follow the [rename steps](/en/docs-markdown/guides/get-started/struo-project#upgrading-from-once), including the new executable, configuration, script headers, environment variables, and cold local cache.

Use [connecting a project](https://struo.run/docs/guide/infrastructure/connect) to bind the repository to a Tuist environment with the canary integration enabled:

```sh
struo connect --provider tuist --create
```

Configure the intended Tuist URL, account, and project using the provider documentation. Run the action on a first machine, then request the same work on a second authenticated machine whose local cache has never seen the result. Confirm that Struo restores the declared outputs from the shared cache and open the printed run URL to follow the action evidence.

## Open infrastructure you can improve

Tuist combines open-source tooling with public infrastructure code. Inspect [Struo's implementation](https://github.com/tuist/struo) and the [Tuist infrastructure](https://github.com/tuist/tuist), report issues, and [contribute improvements](https://github.com/tuist/tuist/blob/main/CONTRIBUTING.md) to action handling, cache integration, and live reporting. The code gives your team a concrete way to help shape support for its scripts and native project workflows.

A closed hosted service leaves implementation changes entirely with the provider. Tuist and Struo give developers a direct path to help improve the infrastructure they depend on. See [Openness](/marketing-markdown/openness) for Tuist's public components and their licenses.

## Sources and review

Written by Tuist. Sources reviewed on **2026-11-07**: [Struo](https://struo.run/), its [Tuist provider](https://struo.run/docs/guide/infrastructure/tuist), [connection guide](https://struo.run/docs/guide/infrastructure/connect), [script caching contract](https://struo.run/docs/guide/scripted/caching), [execution-provider guide](https://struo.run/docs/guide/infrastructure/remote-execution), and Tuist's [Struo execution guide](/en/docs-markdown/guides/features/runners/struo). Canary support and account-enabled execution are distinct availability conditions.

[All build systems](/marketing-markdown/build-systems) · [Tuist cache infrastructure](/marketing-markdown/cache)
