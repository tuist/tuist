---
{
  "title": "不穩定測試",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "自動偵測並追蹤 CI 流程中的不穩定測試。"
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試係指用同一份代碼多次執行時，會產生唔同結果（通過或失敗）嘅測試。佢哋會削弱你對測試套件嘅信任，亦會浪費開發人員時間去調查虛假失敗。Tuist 會自動偵測不穩定測試，並幫你隨時間追蹤佢哋。如要了解團隊如何調查同控制佢哋，請參閱 [不穩定測試](https://tuist.dev/solutions/flaky-tests)。如需工具無關嘅常見成因解釋同衡量不穩定性嘅方法，請參閱 <.localized_link href="/references/concepts/flaky-test">乜嘢係不穩定測試？</.localized_link>。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test 偵測、管理同隔離 Xcode 項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成項目"
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
    details="透過測試重試偵測同管理 Elixir 項目中嘅不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 運行嘅結果偵測同調查不穩定嘅 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="透過報告嘅重試嘗試同 CI 歷史記錄調查不一致嘅測試結果。"
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
