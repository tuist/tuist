---
{
  "title": "在 Swift Package 中使用 Tuist",
  "titleTemplate": ":title · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Swift Package 中使用 Tuist。"
}
---
# 在 Swift Package 中使用 Tuist <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支援將 `Package.swift` 作為專案的 DSL，並將你的套件目標轉換為原生的 Xcode 專案與目標。

> [!WARNING]
> 此功能的目的是提供開發人員一種簡便的方式，評估在其 Swift Packages 中採用 Tuist 的影響。因此，我們不計畫支援完整的 Swift Package Manager 功能，也不會將 Tuist 的每項獨特功能（例如 <.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>）帶入套件領域。


> [!NOTE]
> **根目錄**
>
> Tuist 命令預期特定的 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">目錄結構</.localized_link>，其根目錄由 `Tuist` 或 `.git` 目錄識別。


## 在 Swift Package 中使用 Tuist {#using-tuist-with-a-swift-package}

我們將使用包含 Swift Package 的 [TootSDK Package](https://github.com/TootSDK/TootSDK) 儲存庫來搭配 Tuist。首先需要克隆該儲存庫：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

進入儲存庫目錄後，需要安裝 Swift Package Manager 的相依性：

```bash
tuist install
```

在底層，`tuist install` 會使用 Swift Package Manager 來解析並拉取套件的相依性。解析完成後，即可產生專案：

```bash
tuist generate
```

完成了！你現在擁有一個可以開啟並開始開發的原生 Xcode 專案。
