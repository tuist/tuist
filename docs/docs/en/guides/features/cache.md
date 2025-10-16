---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Cache {#cache}

Xcode's build system provides [incremental builds](https://en.wikipedia.org/wiki/Incremental_build_model), enhancing efficiency under normal circumstances. However, this feature falls short in [Continuous Integration (CI) environments](https://en.wikipedia.org/wiki/Continuous_integration), where data essential for incremental builds is not shared across different builds. Additionally, build artifacts are not shared across different environments, forcing you to rebuild the same code over and over.

Tuist addresses these challenges effectively with its caching feature, significantly reducing build times both in local development and CI environments. This approach not only accelerates feedback loops but also minimizes the need for context switching, ultimately boosting productivity.

We offer two types of caching:
- <LocalizedLink href="/guides/features/cache/localized-link">Cache for generated projects</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/generated-project">Xcode Cache</LocalizedLink>

## Generated Projects {#generated-projects}

For projects that use Tuist's <LocalizedLink href="/guides/features/projects">project generation</LocalizedLink> capabilities, we provide a powerful caching system, which caches compiled framework binaries and shares them across your team and CI environments.

While you can also use the new Xcode Cache, this feature is currently experimental and you will likely have a lower cache hit rate compared to the generated project caching. However, the decision for which caching solution to use depends on your specific needs and preferences. You may also combine both caching solutions to achieve the best results.

<LocalizedLink href="/guides/features/cache/generated-project">Learn more about caching for generated projects →</LocalizedLink>

## Xcode Cache {#xcode-cache}

::: warning EXPERIMENTAL FEATURE
Xcode Cache is currently experimental.
:::

Apple has been working on a new caching solution at the build level, similar to other build systems like Bazel and Buck. The new caching capability is available since Xcode 26 and Tuist now seamlessly integrates with it – regardless of whether you are using Tuist's <LocalizedLink href="/guides/features/projects">project generation</LocalizedLink> capabilities or not.

<LocalizedLink href="/guides/features/cache/xcode-cache">Learn more about Xcode Cache →</LocalizedLink>
