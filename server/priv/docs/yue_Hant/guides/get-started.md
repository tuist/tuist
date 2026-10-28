---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# 開始使用 {#get-started}

選擇與你目前應用程式建構方式相符的路徑。每條路徑都會逐步說明需要安裝什麼、如何啟用快取、洞察報告和測試功能，以及如何端到端驗證設定。你可以單獨採用這些功能，或者如果你在多平台上發布，也可以將它們結合使用。

## Xcode 專案 {#existing-xcode-project}

保留現有的 Xcode 專案或工作區，並逐一新增 Tuist 功能。無需產生專案。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 產生的 Xcode 專案 {#generated-xcode-project}

讓 Tuist 從 Swift manifest 檔案定義並產生你的 Xcode 專案。產生的專案將模組化 Xcode 專案的複雜性壓縮為簡潔且具宣告性的圖表描述，並且是 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 和 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 的嚴格要求。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle 專案 {#gradle-project}

透過 `dev.tuist` Gradle 外掛程式，將 Gradle 專案連接到 Tuist 的遠端快取、建構洞察報告和測試洞察報告。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir 專案 {#elixir-project}

透過 `tuist_ex` Hex 套件，將 Elixir 專案連接到 Tuist 的建構洞察報告、測試洞察報告、不穩定測試偵測和測試分片。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust 專案 {#rust-project}

透過 Tuist CLI 執行 Cargo 以回報建構和個別測試結果（包括文件測試），並調查不穩定的測試。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel 專案 {#bazel-project}

將 Bazel 工作區指向 Tuist 的遠端執行 API 快取和建構事件服務，以便在你的團隊和 CI 之間共享快取命中和洞察報告。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

在進行任何上述操作之前，請先 <.localized_link href="/guides/install-tuist">安裝 Tuist 命令列介面</.localized_link>。Elixir 專案是例外：它們只需要 Hex 套件。
