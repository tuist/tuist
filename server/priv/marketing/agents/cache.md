# Tuist Cache

Share build outputs across developer machines, CI, and coding-agent environments so compatible outputs can be reused rather than compiled again elsewhere.

## Problem

A local build cache only helps the machine that filled it. Fresh CI machines, new checkouts, and agent sandboxes start cold and recompile what a teammate or an earlier job already built.

## How it works

Tuist hosts a remote cache keyed by build inputs. On a hit, the build downloads the stored output instead of rebuilding it; on a miss, it builds normally and can upload the result for others. The Tuist server tells clients which cache endpoint to use, normally the closest region. On [Tuist Runners](/marketing-markdown/compute), the cache sits on the runner's private network and is the same cache developer machines use.

## Choose the integration

These are four separate integrations, one per build system, not interchangeable settings:

| Integration | Toolchain | What is reused | Requirements and setup |
| --- | --- | --- | --- |
| [Module cache](/en/docs-markdown/guides/features/cache/module-cache) | Tuist-generated Xcode projects | Whole targets as prebuilt `.xcframework` binaries, substituted at generation time | Requires project generation. Warm with `tuist cache`; `tuist generate` then uses binaries. |
| [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) | Any Xcode project, generated or not | Compilation outputs reused during the build (Xcode compilation cache) | Xcode 26 or later. Run `tuist setup cache` on each machine and add the printed build settings. |
| [Gradle cache](/en/docs-markdown/guides/features/cache/gradle-cache) | Gradle, including Android | Task outputs through Gradle's build cache | [Tuist Gradle plugin](/en/docs-markdown/guides/install-gradle-plugin) plus `org.gradle.caching=true`. |
| [Bazel cache](/en/docs-markdown/guides/features/cache/bazel-cache) | Bazel | Action outputs through the Remote Execution API cache | Run `tuist bazel setup` on each machine; it writes `.bazelrc.tuist`. |

Generated Xcode projects can combine the module cache and the Xcode cache: the first skips whole modules, the second speeds up what still compiles. Tuist does not provide remote caching for Elixir.

## When it fits

- Clean CI builds, many checkouts, or agent sandboxes repeatedly compile the same inputs.
- Several environments can produce and consume compatible artifacts (same toolchain versions and settings).

It helps less when most builds change most inputs, when local incremental builds are already fast, or when the network path to the cache is slow relative to compiling.

## How to get started

1. [Install Tuist](/en/docs-markdown/guides/install-tuist) (Gradle: the plugin; Bazel: the CLI), then create or connect a project with `tuist init`.
2. Configure the integration above and [authenticate CI](/en/docs-markdown/guides/server/authentication), preferably with OIDC or a project token rather than a personal login.
3. Build once to populate the cache, then build the same inputs from another environment.
4. Check hit rate and transfer in the project's cache dashboards and [Build Insights](/en/docs-markdown/guides/features/build-insights).

## Limitations

- Changed inputs or different toolchain versions and settings produce misses. A remote cache never guarantees a hit or removes all compilation.
- Downloads cost latency and bandwidth; the benefit depends on artifact size, distance to the cache, and how expensive the work is to rebuild.
- Choose trusted producers. Account admins can set cache uploads to "CI and account tokens only" so developers download but do not upload; Gradle can also disable pushes locally.
- [Self-hosted cache nodes](/en/docs-markdown/guides/features/cache/self-hosting) (Kura) can run near your CI or offices and connect to hosted or self-hosted Tuist. They require the Enterprise plan and add infrastructure to operate.

## Pricing

Billing depends on the account's model: newer plans meter cache downloads (egress and requests) while uploads and storage are free; older plans meter module cache usage differently. Check the live [pricing table](/pricing) and [pricing guide](/marketing-markdown/pricing); do not estimate cost from team size.
