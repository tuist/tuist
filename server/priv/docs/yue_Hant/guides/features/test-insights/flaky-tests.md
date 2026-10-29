---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不穩定測試 {#flaky-tests}

不穩定測試是指在使用相同代碼多次運行時產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查虛假失敗的時間。Tuist 會自動偵測不穩定測試，並幫助你隨時間追蹤它們。

<.home_cards>
  <.home_card
    title="Xcode"
    details="透過 tuist xcodebuild test 偵測、管理及隔離 Xcode 專案中的不穩定測試。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Generated projects"
    details="透過 tuist test 偵測、管理及隔離 Tuist 生成專案中的不穩定測試。"
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
    details="利用跨 CI 運行的結果，偵測及調查不穩定的 Cargo 測試。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
