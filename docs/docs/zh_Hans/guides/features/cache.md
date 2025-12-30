---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# 缓存 {#cache}

Xcode
的构建系统提供了[增量构建](https://en.wikipedia.org/wiki/Incremental_build_model)，提高了单台机器上的效率。但是，构建工件不能在不同环境中共享，这就迫使您在[持续集成（CI）环境](https://en.wikipedia.org/wiki/Continuous_integration)或本地开发环境（您的
Mac）中反复重建相同的代码。

Tuist 通过缓存功能解决了这些难题，大大缩短了本地开发和 CI
环境中的构建时间。这种方法不仅加快了反馈循环，还最大限度地减少了上下文切换的需要，最终提高了工作效率。

我们提供两种缓存方式：
- <LocalizedLink href="/guides/features/cache/module-cache">模块缓存</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Xcode缓存</LocalizedLink>

## 模块缓存 {#module-cache}

对于使用 Tuist 的 <LocalizedLink href="/guides/features/projects">项目生成</LocalizedLink> 功能的项目，我们提供了强大的缓存系统，可将单个模块缓存为二进制文件，并在团队和 CI 环境中共享。

虽然您也可以使用新的 Xcode
缓存，但该功能目前已针对本地构建进行了优化，与生成的项目缓存相比，您的缓存命中率可能会更低。不过，使用哪种缓存解决方案取决于您的具体需求和偏好。您也可以将两种缓存解决方案结合使用，以达到最佳效果。

<LocalizedLink href="/guides/features/cache/module-cache">了解有关模块缓存的更多信息 →</LocalizedLink>

## Xcode 缓存 {#xcode-cache}

::: warning XCODE CACHE STATE
<!-- -->
Xcode 缓存目前针对本地增量构建进行了优化，而且整个构建任务的范围还不依赖于路径。尽管如此，您仍然可以通过插入 Tuist
的远程缓存来体验其优势，而且随着构建系统能力的不断提高，我们预计构建时间也会逐渐缩短。
<!-- -->
:::

Apple 一直致力于在构建级别开发一种新的缓存解决方案，类似于 Bazel 和 Buck 等其他构建系统。新的缓存功能从 Xcode 26 开始提供，无论您是否使用 Tuist 的 <LocalizedLink href="/guides/features/projects">项目生成</LocalizedLink> 功能，Tuist 现在都能与之无缝集成。

<LocalizedLink href="/guides/features/cache/xcode-cache">了解有关 Xcode 缓存的更多信息 →</LocalizedLink>
