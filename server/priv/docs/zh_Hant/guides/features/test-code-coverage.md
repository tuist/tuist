---
{
  "title": "程式碼涵蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試執行中每個檔案與提交的行涵蓋率。"
}
---
# 程式碼涵蓋率 {#code-coverage}

程式碼涵蓋率會告訴你測試執行了哪些程式碼行。Tuist 會上傳每次測試執行的涵蓋率，並將同一提交的多次執行合併為單一數值，提供每個檔案與整個專案的統計，讓你能在儀表板中逐次提交追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳使用 tuist xcodebuild test 測試之 Xcode 專案的程式碼涵蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="產生的專案"
    details="透過 tuist test、二進位快取與選擇性測試，測量 Tuist 產生專案中的程式碼涵蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳使用 mix test --cover 測試之 Elixir 專案的行涵蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="上傳使用 cargo test 測試之 Rust 專案的行涵蓋率。"
    link="/guides/features/test-code-coverage/rust"
/>
  <.home_card
    title="Gradle"
    details="上傳 Gradle 專案的程式碼涵蓋率，並包含每次測試執行的檔案資訊。"
    link="/guides/features/test-code-coverage/gradle"
/>
</.home_cards>
