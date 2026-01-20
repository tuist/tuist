---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# 在 Swift 软件包中使用 Tuist <Badge type="warning" text="beta" />{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支持使用`Package.swift` 作为您项目的 DSL，它能将您的软件包目标转换为本地 Xcode 项目和目标。

:: 警告
<!-- -->
该功能旨在为开发人员提供一种简便的方法，以评估在其 Swift 软件包中采用 Tuist 的影响。因此，我们并不打算支持 Swift
软件包管理器的所有功能，也不打算将 Tuist 的所有独特功能（如
<LocalizedLink href="/guides/features/projects/code-sharing">项目描述助手</LocalizedLink>）引入软件包世界。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist 命令需要一个特定的
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects"> 目录结构</LocalizedLink>，其根目录由`Tuist` 或`.git` 目录标识。
<!-- -->
:::

## 在 Swift 软件包中使用 Tuist{#using-tuist-with-a-swift-package}

我们将在 [TootSDK Package](https://github.com/TootSDK/TootSDK) 仓库中使用 Tuist，其中包含一个
Swift 包。我们需要做的第一件事就是克隆该版本库：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

进入版本库目录后，我们需要安装 Swift 包管理器依赖项：

```bash
tuist install
```

`tuist install` 使用 Swift 软件包管理器解析并提取软件包的依赖关系。解析完成后，即可生成项目：

```bash
tuist generate
```

瞧！您有了一个原生的 Xcode 项目，可以打开并开始工作。
