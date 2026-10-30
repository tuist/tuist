---
{
  "title": "在 Swift Package 中使用 Tuist",
  "titleTemplate": ":title · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift Package 中使用 Tuist。"
}
---
# 在 Swift Package 中使用 Tuist <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支持将 `Package.swift` 用作项目的 DSL，并将包中的 target 转换为原生的 Xcode 项目和 target。

> [!WARNING]
> 此功能的目的是为开发者提供一种简便方式，以评估在其 Swift Package 中采用 Tuist 的影响。因此，我们并不计划支持 Swift Package Manager 的全部功能，也不会将 Tuist 的所有独特功能（例如 <.localized_link href="/guides/features/projects/code-sharing">项目描述辅助工具</.localized_link>）引入到包的世界中。


> [!NOTE]
> **根目录**
>
> Tuist 命令期望存在特定的 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">目录结构</.localized_link>，其根目录由 `Tuist` 或 `.git` 目录标识。


## 在 Swift Package 中使用 Tuist {#using-tuist-with-a-swift-package}

我们将结合包含 Swift Package 的 [TootSDK Package](https://github.com/TootSDK/TootSDK) 仓库来使用 Tuist。首先需要克隆该仓库：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

进入仓库目录后，需要安装 Swift Package Manager 的依赖：

```bash
tuist install
```

在底层，`tuist install` 会使用 Swift Package Manager 来解析并拉取包的依赖。解析完成后，你可以生成项目：

```bash
tuist generate
```

完成！你现在拥有一个可以打开并开始开发的原生 Xcode 项目。
