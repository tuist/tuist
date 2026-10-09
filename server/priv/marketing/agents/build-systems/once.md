# Tuist with Once

Tuist extends its one-platform approach to [Once](https://buildonce.dev/) through shared action results and live run/action reporting using Once's Tuist infrastructure provider. Once support in Tuist is currently in canary. Organizations can evaluate native action-level integration alongside Tuist's supported Xcode, Gradle, Bazel, and Mix workflows, without treating canary support as generally available or feature-equivalent.

## One productivity platform, native depth

Embracing build-system diversity includes new action models, not just today's established toolchains. We believe Tuist is the best choice for organizations seeking one productivity platform across their build systems; the canary Once integration extends that direction rather than introducing a disconnected productivity product.

For Once, native depth means declared action contracts, shared compatible results, and recorded live action progress and output. A generic CI job can execute a script without exposing its action boundaries or providing this provider-backed reuse. See the [cross-build-system stance](/marketing-markdown/build-systems) for the platform rationale and CI comparison. Evaluate Once only on an enabled canary environment: this direction is not a promise of production readiness, remote execution availability, or broader test-feature support.

## What Once already does

Once makes work explicit as actions with declared inputs, outputs, and environment. Its local cache can reuse recorded results without a remote account. Script annotations make existing automation cacheable; graph workflows expose targets and dependencies, including adapters for supported native projects. Once keeps the underlying compilers and SDKs rather than replacing them.

The action contract is the correctness boundary. Declare every relevant input and environment variable and the outputs that must be restored. Publishing releases or sending notifications are external side effects, not suitable cacheable work.

Once also separates caching from execution infrastructure. It can run prepared actions through supported execution providers, but that is not the same as configuring the Tuist cache provider.

## How Tuist augments it

- **Reuse action results across people and environments.** The [Tuist provider](https://buildonce.dev/docs/guide/infrastructure/tuist) connects Once's declared actions to a shared cache. A developer, CI runner, or agent environment can restore a compatible result produced on another machine instead of only benefiting from its own local cache.
- **Follow work live.** Once reports ordered run/action events to Tuist and prints a dashboard link as a run starts. The live view exposes recorded progress, cache decisions, and captured output; Tuist's integration distinguishes actions within the same target.
- **Use authenticated team infrastructure.** The provider binds the repository to a Tuist account/project in `once.toml`, with developer login and documented token or OIDC automation flows. This is independent of whether CI runs on Tuist Runners.

Project first, environment second still applies: improve the action boundaries and reuse compatible outputs before moving cache misses to larger or remote machines.

## First experiment

First verify that your Tuist environment has the canary integration enabled and that the Once release and provider configuration are compatible. Read [Once getting started](https://buildonce.dev/docs/guide/getting-started) and [connecting a project](https://buildonce.dev/docs/guide/infrastructure/connect); pin an appropriate release rather than assuming every release has identical behavior.

On an enabled environment, the documented connection flow is:

```sh
once connect --provider tuist --create
```

The published default provider URL is `https://tuist.dev`. Do not assume that default grants canary access: configure the intended Tuist URL/account/project using the provider documentation and the environment's setup instructions before testing.

Run one correctly declared scripted action on a first machine. Run the same action, inputs, and configuration on a second authenticated machine whose local cache has never seen the result. A hit that restores the declared outputs demonstrates shared reuse, not merely a warm local cache. Open the printed run URL to inspect the action evidence.

## Limitations

Canary availability is not general availability; commands, protocols, and support boundaries may change. Published Once releases and documentation are not proof that a particular Tuist environment has enabled the integration. Live reporting is best-effort and does not fail an otherwise successful run if reporting is unavailable. Cache configuration does not establish remote execution: [Once's execution providers](https://buildonce.dev/docs/guide/infrastructure/remote-execution) are configured separately. Do not infer general test insights, quarantine, stress testing, selective testing, or test sharding support from a live run/action view. Compatible action contracts remain necessary for correct reuse.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Once](https://buildonce.dev/), its [Tuist provider](https://buildonce.dev/docs/guide/infrastructure/tuist), [connection guide](https://buildonce.dev/docs/guide/infrastructure/connect), [script caching contract](https://buildonce.dev/docs/guide/scripted/caching), and [execution-provider guide](https://buildonce.dev/docs/guide/infrastructure/remote-execution). The canary availability statement is an explicit Tuist rollout qualification, not inferred from Once's release tags.

[All build systems](/marketing-markdown/build-systems) · [Tuist cache infrastructure](/marketing-markdown/cache)
