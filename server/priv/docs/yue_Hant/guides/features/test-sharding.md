---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Test Sharding，將測試分散到多個 CI 執行器上執行，以加快測試套件的執行速度。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，允許一定程度的測試並行化。然而，有些情況需要你超越單一主機的能力——例如，當你受限於可同時運行的模擬器數量，或者你的測試套件已經超出單一機器的負荷。

在這些情況下，你需要一個系統將測試分配到多個 CI runner，並將結果匯總成統一的視圖。這就是測試分片的作用。

Tuist 使用歷史測試時間數據，透過 [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) 智能地平衡各分片的負載，使每個 runner 大約在同一時間完成。所有分片的結果會自動匯總到 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，讓你獲得跨所有分片的測試套件統一視圖。

<.home_cards>
  <.home_card
    title="Xcode"
    details="將 Xcode 測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="將 Tuist 生成的項目中的測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="將 Gradle 測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="將你的 Elixir 項目測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="將 Cargo 測試目標分配到並行的 CI worker。"
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="將發現的 Once 測試批次分配到 CI worker，並使用託管方案合併結果。"
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
