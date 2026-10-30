---
{
  "title": "開始使用",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "揀選同你目前應用程式建構方式配合嘅 Tuist 路徑：Xcode、生成嘅 Xcode 專案、Gradle、Elixir、Rust 或 Bazel。"
}
---
# 開始使用 {#get-started}

揀選同你而家應用程式構建方式相匹配嘅路徑。每條路徑都會逐步介紹需要安裝乜、點樣啟用快取、分析同測試功能，以及點樣端到端驗證設定。你可以獨立採用佢哋，或者如果你喺多個平台發布，可以將佢哋結合使用。

## Xcode 專案 {#existing-xcode-project}

保留你現有嘅 Xcode 專案或工作區，並逐一添加 Tuist 功能。無需生成專案。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成嘅 Xcode 專案 {#generated-xcode-project}

讓 Tuist 根據 Swift 清單定義並生成你嘅 Xcode 專案。生成嘅專案將模組化 Xcode 專案嘅複雜性壓縮為簡潔、聲明式嘅圖表描述，並且係 <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> 同 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 嘅嚴格要求。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 專案 {#gradle-project}

透過 `dev.tuist` Gradle 外掛程式，將 Gradle 專案連接到 Tuist 嘅遠程快取、構建分析同測試分析。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 專案 {#elixir-project}

透過 `tuist_ex` Hex 套件，將 Elixir 專案連接到 Tuist 嘅構建分析、測試分析、不穩定測試檢測同測試分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 專案 {#rust-project}

透過 Tuist CLI 運行 Cargo 以報告構建同單個測試結果（包括 doctests），並調查不穩定測試。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 專案 {#bazel-project}

將 Bazel 工作區指向 Tuist 嘅 Remote Execution API 快取同 Build Event Service，以便喺你嘅團隊同 CI 之間共享快取命中同分析。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

進行以上任何操作之前，請先 <.localized_link href="/guides/install-tuist">安裝 Tuist 命令列介面</.localized_link>。Elixir 專案係例外：佢哋只需要 Hex 套件。
