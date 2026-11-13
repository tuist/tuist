---
{
  "title": "不穩定測試",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "自動偵測並追蹤 CI 流程中的不穩定測試。"
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試係指同一份代碼多次運行時，結果唔一致（有時通過、有時失敗）嘅測試。佢哋會削弱你對測試套件嘅信心，亦浪費開發人員排查誤報失敗嘅時間。Tuist 會自動偵測不穩定測試，並幫你長期追蹤。如欲了解團隊如何調查同控制呢啲問題，請參閱 [不穩定測試](https://tuist.dev/solutions/flaky-tests)。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test，喺 Xcode 專案中偵測、管理同隔離不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成嘅專案"
    details="透過 tuist test，喺 Tuist 生成嘅專案中偵測、管理同隔離不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="喺 Gradle 專案中偵測同管理不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test，偵測、靜音同跳過不穩定嘅 Bazel 測試用例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="配合測試重試機制，喺 Elixir 專案中偵測同管理不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 運行嘅結果，偵測同調查不穩定嘅 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="透過匯報嘅重試次數同 CI 歷史記錄，調查不一致嘅測試結果。"
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
