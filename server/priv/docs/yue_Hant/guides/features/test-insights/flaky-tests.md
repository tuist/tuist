---
{
  "title": "不穩定測試",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "自動偵測並追蹤 CI 流程中的不穩定測試。"
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試係指喺同一份代碼下多次運行時，會產生唔同結果（通過或失敗）嘅測試。呢類測試會削弱你對測試套件嘅信心，並浪費開發人員排查誤報失敗嘅時間。Tuist 會自動偵測不穩定測試，並幫你持續追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test 偵測、管理同隔離 Xcode 項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Generated projects"
    details="透過 tuist test 偵測、管理同隔離 Tuist 生成項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="偵測同管理 Gradle 項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test 偵測、靜音同跳過不穩定嘅 Bazel 測試用例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過測試重試機制，偵測同管理 Elixir 項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 運行嘅結果，偵測同調查不穩定嘅 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="透過報告嘅重試次數同 CI 歷史記錄，調查不一致嘅測試結果。"
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
