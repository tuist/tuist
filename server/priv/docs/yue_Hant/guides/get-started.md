---
{
  "title": "開始使用",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "揀選配合你現時應用程式建構方式嘅 Tuist 路徑：Xcode、生成嘅 Xcode 專案、Gradle、Elixir、Rust、Bazel 或 Struo。"
}
---
# 開始使用 {#get-started}

揀選同你今日應用程式構建方式相匹配嘅路徑。每條路徑都會逐步說明需要安裝乜嘢、點樣啟用快取、洞察同測試功能，以及點樣端到端驗證設定。你可以獨立採用各項功能，或者如果你喺多個平台發布，可以將佢哋結合使用。

大多數路徑都使用 <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。Elixir 使用 Hex 套件，而 Struo 則透過其原生 Tuist 提供者連接；兩者整合時都唔需要 Tuist CLI。

## Xcode 專案 {#existing-xcode-project}

保留你現有嘅 Xcode 專案或工作區，並逐一添加 Tuist 功能。無需生成專案。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成嘅 Xcode 專案 {#generated-xcode-project}

讓 Tuist 從 Swift 清單檔案定義並生成你嘅 Xcode 專案。生成嘅專案將模組化 Xcode 專案嘅複雜性壓縮為圖表嘅簡潔聲明式描述，並且係 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 同 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 嘅嚴格要求。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 專案 {#gradle-project}

透過 `dev.tuist` Gradle 外掛程式，將 Gradle 專案連接到 Tuist 嘅遠端快取、構建洞察同測試洞察。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 專案 {#elixir-project}

透過 `tuist_ex` Hex 套件，將 Elixir 專案連接到 Tuist 嘅構建洞察、測試洞察、不穩定測試偵測同測試分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 專案 {#rust-project}

透過 Tuist CLI 執行 Cargo 以報告構建同個別測試結果（包括文件測試），並調查不穩定測試。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 專案 {#bazel-project}

將 Bazel 工作區指向 Tuist 嘅遠端執行 API 快取同構建事件服務，以便喺你嘅團隊同 CI 之間共享快取命中同洞察。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Struo 專案 {#struo-project}

<a id="once-project"></a>

將 Struo 嘅可快取腳本同構建圖連接到 Tuist，以實現共享快取、即時構建同測試洞察、託管測試分片同應用程式預覽。

<.localized_link href="/guides/get-started/struo-project">Start with a Struo project →</.localized_link>
