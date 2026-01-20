---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Cache {#cache}

Xcode's build system provides [incremental
builds](https://en.wikipedia.org/wiki/Incremental_build_model), enhancing
efficiency on a single machine. However, build artifacts are not shared across
different environments, forcing you to rebuild the same code over and over –
either in your [Continuous Integration (CI)
environments](https://en.wikipedia.org/wiki/Continuous_integration) or local
development environments (your Mac).

Tuist addresses these challenges with its caching feature, significantly
reducing build times both in local development and CI environments. This
approach not only accelerates feedback loops but also minimizes the need for
context switching, ultimately boosting productivity.

We offer two types of caching:
- <LocalizedLink href="/guides/features/cache/module-cache">Module cache</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode cache</LocalizedLink>

## Module cache {#module-cache}

For projects that use Tuist's
<LocalizedLink href="/guides/features/projects">project generation</LocalizedLink> capabilities, we provide a powerful caching system,
which caches individual modules as binaries and shares them across your team and
CI environments.

While you can also use the new Xcode cache, this feature is currently optimized
for local builds and you will likely have a lower cache hit rate compared to the
generated project caching. However, the decision for which caching solution to
use depends on your specific needs and preferences. You may also combine both
caching solutions to achieve the best results.

<LocalizedLink href="/guides/features/cache/module-cache">Learn more about Module cache →</LocalizedLink>

## Xcode cache {#xcode-cache}

::: warning STATE OF CACHE IN XCODE
<!-- -->
Xcode caching is currently optimized for local incremental builds and the whole
spectrum of build tasks is not yet path-independent. Still you can experience
benefits by plugging Tuist's remote cache, and we expect build times to improve
over time as the build system's capability keeps improving.
<!-- -->
:::

Apple has been working on a new caching solution at the build level, similar to
other build systems like Bazel and Buck. The new caching capability is available
since Xcode 26 and Tuist now seamlessly integrates with it – regardless of
whether you are using Tuist's
<LocalizedLink href="/guides/features/projects">project generation</LocalizedLink> capabilities or not.

<LocalizedLink href="/guides/features/cache/xcode-cache">Learn more about Xcode cache →</LocalizedLink>
