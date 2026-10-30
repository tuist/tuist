---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試是指在使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。它們會削弱對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助您隨時間追蹤它們。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test 偵測、管理及隔離 Xcode 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="產生的專案"
    details="透過 tuist test 偵測、管理及隔離 Tuist 產生的專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="偵測及管理 Gradle 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="透過 tuist bazel test 偵測、靜音及跳過不穩定的 Bazel 測試案例。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="透過測試重試機制，偵測及管理 Elixir 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="使用跨 CI 執行的結果來偵測及調查不穩定的 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
