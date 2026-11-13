---
{
  "title": "代碼覆蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試運行中每個檔案和提交的行覆蓋率。"
}
---
# 代碼覆蓋率 {#code-coverage}

代碼覆蓋率會告訴你測試執行了代碼中的哪些行。Tuist 會上傳每次測試執行的覆蓋率，並將一個提交中的所有執行合併為單一數值（按檔案及整個項目計算），讓你能在儀表板上逐個提交追蹤進度。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳使用 tuist xcodebuild test 測試的 Xcode 項目的代碼覆蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成的項目"
    details="透過 tuist test、二進制緩存和選擇性測試，量度 Tuist 生成項目中的代碼覆蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳使用 mix test --cover 測試的 Elixir 項目的行覆蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上傳使用 cargo test 測試的 Rust 項目的行覆蓋率。"
    link="/guides/features/test-code-coverage/rust"
/>
</.home_cards>
