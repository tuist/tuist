# Tuist with Once

Tuist and [Once](https://buildonce.dev/) make scripts cacheable and bring caching to build systems that do not support it natively, without rewriting project sources or native build definitions. Once support in Tuist is currently in canary, with remote execution coming soon. Shared action results and live run/action reporting bring these workflows into the same productivity platform as Tuist's Xcode, Gradle, Bazel, and Mix integrations.

## One productivity platform, native depth

Embracing build-system diversity includes new action models, not just today's established toolchains. We believe Tuist is the best choice for organizations seeking one productivity platform across their build systems; the canary Once integration extends that direction rather than introducing a disconnected productivity product.

For Once, native depth means making existing work reusable, even when its build system has no native remote-cache integration. Keep the project and toolchain; Once adds the action contract, Tuist shares compatible results, and live reporting exposes the work as it happens. Remote execution is coming soon to extend that model from reusing work to running it elsewhere. See the [cross-build-system stance](/marketing-markdown/build-systems) for why one platform should embrace these workflows, not require a build-system migration.

## What Once already does

- **Make scripts cacheable.** Declare a script's inputs, outputs, and relevant environment through Once annotations. Once records the result and restores the outputs when the same work is requested again. Existing automation becomes reusable rather than running from scratch on every invocation.
- **Add caching around an existing build command.** A Once wrapper can run a command such as `npm run build`, declare the source files and lockfile as inputs, and capture the generated directory as an output. The underlying build system does not need a native cache protocol, and the project's sources and native build definitions stay unchanged.
- **Read existing project graphs.** For supported native projects, Once discovers targets and dependencies from existing project files. You can try `once query targets`, `once build`, and `once test` without rewriting the project into a new build language or creating `once.toml` just for discovery.

Once keeps the underlying compilers and SDKs. Its local cache works without a remote account; connect an infrastructure provider when those results should be shared across machines. Script annotations or wrapper configuration describe the action's inputs, outputs, and environment separately from the project's build definitions.

## How Tuist augments it

- **Reuse action results across people and environments.** The [Tuist provider](https://buildonce.dev/docs/guide/infrastructure/tuist) connects Once's declared actions to a shared cache. A developer, CI runner, or agent environment can restore a compatible result produced on another machine instead of only benefiting from its own local cache.
- **Extend acceleration beyond native cache integrations.** Scripts and build systems without a native remote cache can use the same shared action-result infrastructure. Remote execution through the Tuist integration is coming soon, extending the workflow without requiring changes to project sources or native build definitions.
- **Follow work live.** Once reports ordered run/action events to Tuist and prints a dashboard link as a run starts. The live view exposes recorded progress, cache decisions, and captured output; Tuist's integration distinguishes actions within the same target.
- **Use authenticated team infrastructure.** The provider binds the repository to a Tuist account/project in `once.toml`, with developer login and documented token or OIDC automation flows. This is independent of whether CI runs on Tuist Runners.

Project first, environment second still applies: improve the action boundaries and reuse compatible outputs before moving cache misses to larger or remote machines.

## First experiment

Follow [Once getting started](https://buildonce.dev/docs/guide/getting-started) to install Once and make one script cacheable, or discover a supported existing project's targets. For a build command without native caching, create a Once wrapper with declared inputs and outputs while leaving the project's sources and native build definitions unchanged.

Use [connecting a project](https://buildonce.dev/docs/guide/infrastructure/connect) to bind the repository to a Tuist environment with the canary integration enabled:

```sh
once connect --provider tuist --create
```

Configure the intended Tuist URL, account, and project using the provider documentation. Run the action on a first machine, then request the same work on a second authenticated machine whose local cache has never seen the result. Confirm that Once restores the declared outputs from the shared cache and open the printed run URL to follow the action evidence.

## Open infrastructure you can improve

Tuist combines open-source tooling with public infrastructure code. Inspect [Once's implementation](https://github.com/tuist/once) and the [Tuist infrastructure](https://github.com/tuist/tuist), report issues, and [contribute improvements](https://github.com/tuist/tuist/blob/main/CONTRIBUTING.md) to action handling, cache integration, and live reporting. The code gives your team a concrete way to help shape support for its scripts and native project workflows.

A closed hosted service leaves implementation changes entirely with the provider. Tuist and Once give developers a direct path to help improve the infrastructure they depend on. See [Openness](/marketing-markdown/openness) for Tuist's public components and their licenses.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Once](https://buildonce.dev/), its [Tuist provider](https://buildonce.dev/docs/guide/infrastructure/tuist), [connection guide](https://buildonce.dev/docs/guide/infrastructure/connect), [script caching contract](https://buildonce.dev/docs/guide/scripted/caching), and [execution-provider guide](https://buildonce.dev/docs/guide/infrastructure/remote-execution). The canary status and upcoming remote execution describe Tuist's rollout direction.

[All build systems](/marketing-markdown/build-systems) · [Tuist cache infrastructure](/marketing-markdown/cache)
