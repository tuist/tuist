---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# 使用 Tuist 與 Swift 套件 <Badge type="warning" text="beta" />{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

` Tuist 支援將 ``` 作為專案的 DSL，並將您的套件目標轉換為原生 Xcode 專案與目標。

::: warning
<!-- -->
此功能旨在為開發者提供簡易途徑，評估在 Swift 套件中採用 Tuist 的影響。因此，我們不打算支援 Swift Package Manager
的完整功能，亦不會將 Tuist 的所有獨特功能（如
<LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助工具</LocalizedLink>）引入套件領域。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
` Tuist指令要求特定的<LocalizedLink
href="/guides/features/projects/directory-structure#standard-tuist-projects">目錄結構</LocalizedLink>，其根目錄需由`Tuist目錄或`.git目錄`
標識。
<!-- -->
:::

## 使用 Tuist 與 Swift 套件{#using-tuist-with-a-swift-package}

我們將使用 Tuist 搭配 [TootSDK Package](https://github.com/TootSDK/TootSDK) 儲存庫，該儲存庫包含
Swift 套件。首先需要執行儲存庫的複製操作：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

進入儲存庫目錄後，我們需要安裝 Swift Package Manager 依賴項：

```bash
tuist install
```

底層運作原理：執行 ``` 或 `tuist install` ` 時，系統會透過 Swift Package Manager
解析並拉取套件依賴關係。解析完成後，即可建立專案：

```bash
tuist generate
```

瞧！您現在擁有一個原生的 Xcode 專案，可立即開啟並開始進行開發。
