---
{
  "title": "不穩定測試",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "自動偵測並追蹤 CI 流程中的不穩定測試。"
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試係指用同一份代碼多次執行時，會出現唔同結果（通過或失敗）嘅測試。佢哋會削弱你對測試套件嘅信心，亦浪費開發人員時間去調查誤報失敗。Tuist 會自動偵測不穩定測試，並幫你隨住時間追蹤佢哋。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test，在 Xcode 專案中偵測、管理同隔離不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成專案"
    details="透過 tuist test，在 Tuist 生成專案中偵測、管理同隔離不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在 Gradle 專案中偵測同管理不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test，偵測、靜音同跳過不穩定嘅 Bazel 測試案例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過測試重試，在 Elixir 專案中偵測同管理不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 運行嘅結果，偵測同調查不穩定嘅 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
