---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Test Insights，識別 Xcode、Gradle、Bazel、Elixir、Rust 及 Once 專案中的不穩定及緩慢測試。"
}
---
# 測試洞察 {#test-insights}

使用測試洞察來監控你嘅測試套件健康狀況，包括識別慢速測試、追蹤不穩定測試，以及快速了解失敗嘅 CI 運行。目前支援 Xcode、Gradle、Bazel、Elixir、Rust 同 Once。可用嘅結果同時間取決於你嘅 runner。要追蹤喺支援嘅構建系統上測試執行咗邊啲代碼，請參閱 <.localized_link href="/guides/features/test-code-coverage">代碼覆蓋率</.localized_link>。有關 [慢速測試](https://tuist.dev/solutions/slow-tests) 同 [不穩定測試](https://tuist.dev/solutions/flaky-tests) 嘅指導，請參閱解決方案指南。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 scheme post-actions 同 Tuist CLI 追蹤 Xcode 測試分析數據。"
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
    details="透過 Tuist Hex 套件追蹤你嘅 Elixir 項目測試。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="透過你常用嘅測試命令追蹤 Cargo 測試結果、套件持續時間同 doctests。"
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="透過 Once 嘅原生集成追蹤報告嘅測試目標、套件、用例、失敗同重試嘗試。"
    link="/guides/features/test-insights/once"
/>
</.home_cards>
