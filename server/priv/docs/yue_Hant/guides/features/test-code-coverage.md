---
{
  "title": "程式碼覆蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試運行中每個檔案及提交的行覆蓋率。"
}
---
# 程式碼覆蓋率 {#code-coverage}

程式碼覆蓋率會顯示你的測試執行了哪些程式碼行。Tuist 會上傳每次測試執行的覆蓋率，並將同一個提交的所有執行結果合併為單一數值（按檔案及整個專案），讓你能在儀表板上逐個提交追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳使用 tuist xcodebuild test 測試的 Xcode 專案的程式碼覆蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成的專案"
    details="透過 tuist test、二進制快取同選擇性測試，量度 Tuist 生成專案中的程式碼覆蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳使用 mix test --cover 測試的 Elixir 專案的行覆蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上傳使用 cargo test 測試的 Rust 專案的行覆蓋率。"
    link="/guides/features/test-code-coverage/rust"
/>
  <.home_card
    title="Gradle"
    details="上傳 Gradle 專案的程式碼覆蓋率，包括每個測試執行了哪些檔案。"
    link="/guides/features/test-code-coverage/gradle"
/>
</.home_cards>
