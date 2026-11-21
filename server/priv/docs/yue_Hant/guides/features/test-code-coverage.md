---
{
  "title": "代碼覆蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試運行中每個檔案及提交的行覆蓋率。"
}
---
# 程式碼覆蓋率 {#code-coverage}

程式碼覆蓋率會告訴你測試執行咗邊啲程式碼行。Tuist 會上傳每次測試執行嘅覆蓋率，並將同一個提交入面嘅多次執行合併成一個數字（按檔案同整個專案），讓你可以喺儀表板逐個提交追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳以 tuist xcodebuild test 測試嘅 Xcode 專案程式碼覆蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成嘅專案"
    details="使用 tuist test、二進制快取同選擇性測試，量度 Tuist 生成專案嘅程式碼覆蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳以 mix test --cover 測試嘅 Elixir 專案行覆蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上傳以 cargo test 測試嘅 Rust 專案行覆蓋率。"
    link="/guides/features/test-code-coverage/rust"
/>
  <.home_card
    title="Gradle"
    details="上傳 Gradle 專案嘅程式碼覆蓋率，包括每個測試執行咗邊啲檔案。"
    link="/guides/features/test-code-coverage/gradle"
/>
</.home_cards>
