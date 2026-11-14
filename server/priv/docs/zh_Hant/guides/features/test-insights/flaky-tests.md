---
{
  "title": "不穩定測試",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 CI 流程中自動偵測並追蹤不穩定測試。"
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試是指在相同程式碼下多次執行會產生不同結果（通過或失敗）的測試。這類測試會削弱你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你長期追蹤。若要了解團隊如何調查與控制這些測試，請參閱 [不穩定測試](https://tuist.dev/solutions/flaky-tests)。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test 偵測、管理並隔離 Xcode 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="產生的專案"
    details="透過 tuist test 偵測、管理並隔離 Tuist 產生之專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="偵測並管理 Gradle 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test 偵測、靜音並跳過不穩定的 Bazel 測試案例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過測試重試機制，偵測並管理 Elixir 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="利用跨 CI 執行的結果，偵測並調查不穩定的 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="透過回報的重試嘗試與 CI 歷史記錄，調查不一致的測試結果。"
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
