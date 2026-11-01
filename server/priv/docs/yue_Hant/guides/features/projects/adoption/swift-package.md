---
{
  "title": "在 Swift Package 中使用 Tuist",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "學習如何在 Swift Package 中使用 Tuist。"
}
---
# 將 Tuist 用於 Swift Package <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist 支援使用 `Package.swift` 作為專案的 DSL，並會將你的套件目標轉換為原生 Xcode 專案與目標。

> [!WARNING]
> 此功能旨在讓開發人員輕鬆評估在 Swift Packages 中採用 Tuist 的影響。因此，我們不打算支援 Swift Package Manager 的全部功能，亦不會將 Tuist 的所有獨特功能（例如 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>）帶入套件領域。


> [!NOTE]
> **根目錄**
>
> Tuist 指令需要特定的 <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">directory structure</.localized_link>，其根目錄由 `Tuist` 或 `.git` 目錄識別。


## 將 Tuist 用於 Swift Package {#using-tuist-with-a-swift-package}

我們將以包含 Swift Package 的 [TootSDK Package](https://github.com/TootSDK/TootSDK) 儲存庫為例使用 Tuist。首先要做的是克隆該儲存庫：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

進入儲存庫目錄後，你需要安裝 Swift Package Manager 的依賴項：

```bash
tuist install
```

在底層，`tuist install` 會使用 Swift Package Manager 來解析並拉取套件的依賴項。解析完成後，你就可以生成專案：

```bash
tuist generate
```

搞定！你現在有一個原生 Xcode 專案，可以開啟並開始工作。
