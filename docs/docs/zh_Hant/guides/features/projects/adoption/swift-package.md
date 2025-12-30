---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# 在 Swift 套件中使用 Tuist <Badge type="warning" text="beta" />{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支援使用`Package.swift` 作為專案的 DSL，它可以將您的套件目標轉換成原生的 Xcode 專案與目標。

::: warning
<!-- -->
此功能的目的是提供一個簡單的方法，讓開發人員評估在他們的 Swift 套件中採用 Tuist 的影響。因此，我們不打算支援全部的 Swift
套件管理員功能，也不打算將每項 Tuist 的獨特功能，例如
<LocalizedLink href="/guides/features/projects/code-sharing"> 專案描述輔助工具 </LocalizedLink> 帶到套件世界。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist 指令需要特定的
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects"> 目錄結構</LocalizedLink>，其根目錄由`Tuist` 或`.git` 目錄所識別。
<!-- -->
:::

## 在 Swift 套件中使用 Tuist{#using-tuist-with-a-swift-package}

我們將在 [TootSDK Package](https://github.com/TootSDK/TootSDK) 套件庫中使用 Tuist，其中包含一個
Swift Package。我們要做的第一件事就是克隆資源庫：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

進入儲存庫目錄後，我們需要安裝 Swift 套件管理員的相依性：

```bash
tuist install
```

在引擎蓋下`tuist install` 使用 Swift Package Manager 解析並拉取套件的相依性。解析完成後，您就可以產生專案：

```bash
tuist generate
```

瞧！您有一個原生的 Xcode 專案，可以開啟並開始工作。
