---
{
  "title": "在 Swift Package 中使用 Tuist",
  "titleTemplate": ":title · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift Package 中使用 Tuist。"
}
---
# 在 Swift Package 中使用 Tuist <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支持将 `Package.swift` 用作项目的 DSL，并将包中的目标转换为原生 Xcode 项目和目标。

> [!WARNING]
> 此功能旨在为开发者提供一种简便的方式，以评估在其 Swift Packages 中采用 Tuist 的影响。因此，我们并不计划支持 Swift Package Manager 的全部功能，也不会将 Tuist 的所有独特功能（例如 <.localized_link href="/guides/features/projects/code-sharing">项目描述辅助工具</.localized_link>）引入包生态。


> [!NOTE]
> **根目录**
>
> Tuist 命令需要特定的 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">目录结构</.localized_link>，其根目录由 `Tuist` 或 `.git` 目录标识。


## 在 Swift Package 中使用 Tuist {#using-tuist-with-a-swift-package}

我们将结合 [TootSDK Package](https://github.com/TootSDK/TootSDK) 仓库使用 Tuist，该仓库包含一个 Swift Package。首先需要克隆该仓库：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

进入仓库目录后，需要安装 Swift Package Manager 的依赖：

```bash
tuist install
```

在底层，`tuist install` 会使用 Swift Package Manager 解析并拉取包的依赖。解析完成后，即可生成项目：

```bash
tuist generate
```

大功告成！你现在拥有一个可以打开并开始开发的原生 Xcode 项目。
