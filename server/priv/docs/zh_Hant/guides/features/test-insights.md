---
{
  "title": "測試洞察",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試洞察，找出 Xcode、Gradle、Bazel、Elixir、Rust 及 Once 專案中不穩定與緩慢的測試。"
}
---
# 測試洞察 {#test-insights}

使用測試洞察來監控測試套件的健康狀況，方法包括識別緩慢測試、追蹤不穩定測試，以及快速了解失敗的 CI 執行。目前支援 Xcode、Gradle、Bazel、Elixir、Rust 和 Once。可用的結果與時間取決於你的 runner。若要追蹤在受支援建置系統上執行的程式碼，請參閱 <.localized_link href="/guides/features/test-code-coverage">程式碼涵蓋率</.localized_link>。如需有關 [緩慢測試](https://tuist.dev/solutions/slow-tests) 和 [不穩定測試](https://tuist.dev/solutions/flaky-tests) 的指引，請參閱解決方案指南。

<.home_cards>
  <.home_card
    title="Xcode"
    details="使用 scheme post-actions 和 Tuist CLI 追蹤 Xcode 測試分析。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="使用 Tuist Gradle 外掛程式追蹤 Gradle 測試分析。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過執行 tuist bazel test 來追蹤 Bazel 測試分析。"
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
  <.home_card
    title="Once"
    details="透過 Once 的原生整合，追蹤回報的測試目標、套件、案例、失敗和重試嘗試。"
    link="/guides/features/test-insights/once"
/>
</.home_cards>
