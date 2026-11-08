---
{
  "title": "將 Tuist 用於 Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "學習如何將 Tuist 用於 Swift Package。"
}
---
# 喺 Swift Package 入面使用 Tuist <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支援將 `Package.swift` 用嚟做項目嘅 DSL，並會將你嘅 package target 轉換成原生 Xcode 項目同 target。

> [!WARNING]
> 呢項功能嘅目的係為開發者提供一個簡單方法，評估喺自己嘅 Swift Packages 採用 Tuist 嘅影響。因此，我哋無計劃支援全部 Swift Package Manager 功能，亦都無意將 Tuist 獨有嘅功能（例如 <.localized_link href="/guides/features/projects/code-sharing">項目描述輔助工具</.localized_link>）帶入 packages 世界。


> [!NOTE]
> **根目錄**
>
> Tuist 指令需要特定嘅 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">目錄結構</.localized_link>，其根目錄由 `Tuist` 或 `.git` 目錄識別。


## 喺 Swift Package 入面使用 Tuist {#using-tuist-with-a-swift-package}

我哋會喺包含 Swift Package 嘅 [TootSDK Package](https://github.com/TootSDK/TootSDK) 儲存庫中使用 Tuist。首先要做嘅就係複製儲存庫：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

進入儲存庫目錄後，你需要安裝 Swift Package Manager 依賴項：

```bash
tuist install
```

背後 `tuist install` 會使用 Swift Package Manager 解析並拉取套件嘅依賴項。解析完成後，你就可以生成項目：

```bash
tuist generate
```

搞掂！你已經有一個可以打開並開始工作嘅原生 Xcode 項目。
