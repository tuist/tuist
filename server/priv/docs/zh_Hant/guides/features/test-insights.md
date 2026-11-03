---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Test Insights 識別 Xcode、Gradle、Bazel、Elixir 和 Rust 專案中的不穩定與緩慢測試。"
}
---
# 測試洞察 {#test-insights}

使用「測試洞察」監控測試套件的健全狀況：找出耗時的測試、追蹤不穩定測試，並快速釐清失敗的 CI 執行。目前支援 Xcode、Gradle、Bazel、Elixir 與 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 scheme 的 post-actions 與 Tuist CLI 追蹤 Xcode 測試分析資料。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="透過 Tuist Gradle 外掛程式追蹤 Gradle 測試分析資料。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test 執行測試來追蹤 Bazel 測試分析資料。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過 Tuist Hex 套件追蹤你的 Elixir 專案測試。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用你慣用的測試指令追蹤 Cargo 測試結果、套件執行時間與 doctests。"
    link="/guides/features/test-insights/rust"
/>
</.home_cards>
