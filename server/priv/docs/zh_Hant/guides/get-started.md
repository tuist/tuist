---
{
  "title": "開始使用",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "選擇符合你目前 App 建置方式的 Tuist 路徑：Xcode、產生的 Xcode 專案、Gradle、Elixir、Rust 或 Bazel。"
}
---
# 開始使用 {#get-started}

選擇符合你目前應用程式建置方式的路徑。每條路徑都會說明需要安裝什麼、如何啟用快取、洞察與測試功能，以及如何端到端驗證設定。你可以單獨採用，若你在多個平台上交付軟體，也可以組合使用。

## Xcode 專案 {#existing-xcode-project}

保留現有的 Xcode 專案或工作區，並逐步加入 Tuist 功能。無需產生專案。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 產生的 Xcode 專案 {#generated-xcode-project}

讓 Tuist 根據 Swift 資訊清單定義並產生你的 Xcode 專案。產生的專案會將模組化 Xcode 專案的複雜性壓縮為簡潔且宣告式的圖形描述，並且是 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 與 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 的嚴格必要條件。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 專案 {#gradle-project}

透過 `dev.tuist` Gradle 外掛程式，將 Gradle 專案連接至 Tuist 的遠端快取、建置洞察與測試洞察。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 專案 {#elixir-project}

透過 `tuist_ex` Hex 套件，將 Elixir 專案連接至 Tuist 的建置洞察、測試洞察、不穩定測試偵測與測試分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 專案 {#rust-project}

透過 Tuist CLI 執行 Cargo，以回報建置與個別測試結果（包含 doctests），並調查不穩定測試。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 專案 {#bazel-project}

將 Bazel 工作區指向 Tuist 的 Remote Execution API 快取與 Build Event Service，以便在團隊與 CI 之間共用快取命中與洞察。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

在開始之前，請先 <.localized_link href="/guides/install-tuist">安裝 Tuist 命令列介面</.localized_link>。Elixir 專案是例外：只需 Hex 套件即可。
