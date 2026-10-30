---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Test Insights，找出 Xcode、Gradle、Bazel、Elixir 與 Rust 專案中的不穩定測試與緩慢測試。"
}
---
# 測試洞察 {#test-insights}

使用測試洞察來監控測試套件的健全性，包括識別緩慢的測試、追蹤不穩定測試，以及快速了解失敗的 CI 執行。目前支援 Xcode、Gradle、Bazel、Elixir 與 Rust。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 scheme post-actions 與 Tuist CLI 追蹤 Xcode 測試分析資料。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="透過 Tuist Gradle 外掛程式追蹤 Gradle 測試分析資料。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過執行 tuist bazel test 來追蹤 Bazel 測試分析資料。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過 Tuist Hex 套件追蹤 Elixir 專案的測試。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用你慣用的測試指令，追蹤 Cargo 測試結果、套件執行時間與 doctests。"
    link="/guides/features/test-insights/rust"
/>
</.home_cards>
