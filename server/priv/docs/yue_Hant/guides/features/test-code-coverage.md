---
{
  "title": "程式碼覆蓋率",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "追蹤每次測試執行中每個檔案及提交嘅行覆蓋率。"
}
---
# 代碼覆蓋率 {#code-coverage}

代碼覆蓋率顯示你嘅測試執行咗邊啲代碼行。Tuist 會上傳每次\<gN\>測試執行\</gN\>嘅覆蓋率，並將同一個 commit 嘅多次執行合併為單一數值，按每個檔案同整個項目計算，讓你可以喺儀表板逐個 commit 追蹤。

<.home_cards>
  <.home_card
    title="Xcode"
    details="上傳使用 tuist xcodebuild test 測試嘅 Xcode 項目代碼覆蓋率。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成項目"
    details="使用 tuist test、<gN>Binary Caching</gN> 同 <gN>選擇性測試</gN> 量度 Tuist 生成項目中嘅代碼覆蓋率。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="上傳使用 mix test --cover 測試嘅 Elixir 項目行覆蓋率。"
    link="/guides/features/test-code-coverage/elixir"
/>
</.home_cards>
