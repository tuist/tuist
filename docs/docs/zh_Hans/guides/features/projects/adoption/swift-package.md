---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# 使用 Tuist 与 Swift 包 <Badge type="warning" text="beta" />{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist支持将`Package.swift` 作为项目DSL，可将您的包目标转换为原生Xcode项目及目标。

:: 警告
<!-- -->
本功能旨在为开发者提供便捷途径，评估在Swift包中采用Tuist的影响。因此我们不计划支持Swift包管理器的全部功能，也不会将Tuist的独特特性（如<LocalizedLink href="/guides/features/projects/code-sharing">项目描述辅助工具</LocalizedLink>）引入包管理领域。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist命令要求特定的<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">目录结构</LocalizedLink>，其根目录由`Tuist`
或`.git` 目录标识。
<!-- -->
:::

## 使用 Tuist 与 Swift 包{#using-tuist-with-a-swift-package}

我们将在 [TootSDK Package](https://github.com/TootSDK/TootSDK) 仓库中使用 Tuist，该仓库包含一个
Swift 包。我们需要做的第一件事就是克隆该版本库：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

进入仓库目录后，我们需要安装 Swift Package Manager 的依赖项：

```bash
tuist install
```

底层原理：`tuist install` 通过 Swift Package Manager 解析并拉取包的依赖项。解析完成后，即可生成项目：

```bash
tuist generate
```

瞧！您现在拥有一个原生Xcode项目，可直接打开并开始开发。
