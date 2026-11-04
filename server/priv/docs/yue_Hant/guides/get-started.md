---
{
  "title": "開始使用",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "選擇符合你目前應用程式建構方式的 Tuist 路徑：Xcode、生成的 Xcode 專案、Gradle、Elixir、Rust 或 Bazel。"
}
---
# 開始使用 {#get-started}

揀返條同你而家個 app 點樣 build 嘅路。每條都會帶你睇要裝乜、點樣開啓快取、分析同測試功能，以及點樣端到端驗證設定。你可以逐個採用，或者如果你喺多過一個平台發佈，就可以組合使用。

## Xcode 專案 {#existing-xcode-project}

保留你現有嘅 Xcode 專案或 workspace，然後逐一加入 Tuist 功能。唔需要生成專案。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 已生成嘅 Xcode 專案 {#generated-xcode-project}

讓 Tuist 從 Swift manifests 定義並生成你嘅 Xcode 專案。已生成嘅專案將模組化 Xcode 專案嘅複雜性壓縮成簡潔、聲明式嘅圖表描述，並且係 <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> 同 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 嘅嚴格要求。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 專案 {#gradle-project}

透過 `dev.tuist` Gradle plugin 將 Gradle 專案連接到 Tuist 嘅遠程快取、構建分析同測試分析。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 專案 {#elixir-project}

透過 `tuist_ex` Hex package 將 Elixir 專案連接到 Tuist 嘅構建分析、測試分析、不穩定測試檢測同測試分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 專案 {#rust-project}

透過 Tuist CLI 運行 Cargo 以報告構建同個別測試結果（包括 doctests），並調查不穩定測試。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 專案 {#bazel-project}

將 Bazel workspace 指向 Tuist 嘅 Remote Execution API 快取同 Build Event Service，以便喺你嘅團隊同 CI 之間共享快取命中同分析。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

喺做以上任何事之前，請先 <.localized_link href="/guides/install-tuist">安裝 Tuist 命令行界面</.localized_link>。Elixir 專案係例外：佢哋只需要 Hex package。
