---
{
  "title": "代碼覆蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試運行中每個檔案及提交嘅行覆蓋率。"
}
---
# 代碼覆蓋率 {#code-coverage}

代碼覆蓋率會告訴你測試執行咗邊啲代碼行。Tuist 會上傳每次測試執行的覆蓋率，並將同一個 commit 嘅多次執行合併成一個數值，按檔案同整個項目顯示，讓你可以喺儀表板逐個 commit 追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳使用 tuist xcodebuild test 測試嘅 Xcode 項目代碼覆蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成嘅項目"
    details="使用 tuist test、二進制緩存同選擇性測試，量度 Tuist 生成項目中嘅代碼覆蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳使用 mix test --cover 測試嘅 Elixir 項目行覆蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上傳使用 cargo test 測試嘅 Rust 項目行覆蓋率。"
    link="/guides/features/test-code-coverage/rust"
/>
  <.home_card
    title="Gradle"
    details="上傳 Gradle 項目嘅代碼覆蓋率，包括每個測試執行咗邊啲檔案。"
    link="/guides/features/test-code-coverage/gradle"
/>
</.home_cards>
