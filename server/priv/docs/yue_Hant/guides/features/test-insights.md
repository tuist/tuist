---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Test Insights，識別 Xcode、Gradle、Bazel、Elixir、Rust 同 Struo 項目中不穩定同緩慢嘅測試。"
}
---
# 測試洞察 {#test-insights}

使用測試洞察，透過識別慢速測試、追蹤不穩定測試，以及快速了解失敗的 CI 運行，來監控你的測試套件健康狀況。目前支援 Xcode、Gradle、Bazel、Elixir、Rust 和 Struo。可用結果和時間取決於你的 runner。要追蹤測試在支援的構建系統上執行哪些代碼，請參閱 <.localized_link href="/guides/features/test-code-coverage">代碼覆蓋率</.localized_link>。有關 [慢速測試](https://tuist.dev/solutions/slow-tests) 和 [不穩定測試](https://tuist.dev/solutions/flaky-tests) 的指導，請參閱解決方案指南。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 scheme post-actions 和 Tuist CLI 追蹤 Xcode 測試分析數據。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="透過 Tuist Gradle 插件追蹤 Gradle 測試分析數據。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過執行 tuist bazel test 來追蹤 Bazel 測試分析數據。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過 Tuist Hex 套件追蹤你的 Elixir 專案測試。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="透過你常用的測試命令追蹤 Cargo 測試結果、套件持續時間和 doctests。"
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Struo"
    details="透過 Struo 的原生整合追蹤報告的測試目標、套件、用例、失敗和重試嘗試。"
    link="/guides/features/test-insights/struo"
/>
</.home_cards>
