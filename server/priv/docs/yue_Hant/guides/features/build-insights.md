---
{
  "title": "建構分析",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Build Insights 追蹤 Xcode、Gradle、Bazel、Elixir 同 Rust 專案嘅建構效能。"
}
---
# 構建分析 {#build-insights}

使用 Build Insights 追蹤本機及 CI 構建效能。目前支援 Xcode、Gradle、Bazel、Elixir 同 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="喺 Tuist 儀表板追蹤 Xcode scheme 後置動作嘅耗時、構建設置同構建元數據。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成項目"
    details="喺 Tuist 生成項目入面，透過自訂 scheme 追蹤構建分析。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="透過 Tuist Gradle 外掛程式，追蹤 Gradle task 耗時同快取成效。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 Build Event Protocol，追蹤 Bazel 指令持續時間、快取總數同關鍵路徑診斷。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="追蹤你嘅 Elixir 項目編譯需時幾耐、警告訊息，以及拖慢構建嘅檔案。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="透過 Tuist CLI，追蹤 Cargo 指令持續時間、觀察到嘅 rustc 調用次數，同編譯器診斷。"
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
