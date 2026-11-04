---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Test Insights，識別 Xcode、Gradle、Bazel、Elixir 同 Rust 專案中不穩定同緩慢嘅測試。"
}
---
# 測試洞察 {#test-insights}

使用測試洞察，透過識別慢速測試、追蹤不穩定測試，以及快速了解失敗的 CI 執行，來監控你的測試套件健康狀況。目前支援 Xcode、Gradle、Bazel、Elixir 和 Rust。要追蹤測試執行的程式碼，請參閱 <.localized_link href="/guides/features/test-code-coverage">程式碼涵蓋率</.localized_link>。

<.home_cards>
  <.home_card
    title="Xcode"
    details="使用 scheme post-actions 和 Tuist CLI 追蹤 Xcode 測試分析數據。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="使用 Tuist Gradle 外掛程式追蹤 Gradle 測試分析數據。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過執行 tuist bazel test 來追蹤 Bazel 測試分析數據。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="使用 Tuist Hex 套件追蹤你的 Elixir 專案測試。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="使用你慣用的測試指令追蹤 Cargo 測試結果、套件持續時間和 doctests。"
    link="/guides/features/test-insights/rust"
/>
</.home_cards>
