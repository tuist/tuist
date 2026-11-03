---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試分片，將測試分散到多個 CI 執行器上執行，加快測試套件的運行速度。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，允許一定程度嘅測試並行化。不過，有時你需要超越單一主機嘅能力——例如當你同時運行嘅模擬器數量受限，或者你嘅測試套件已經超出單一機器嘅負荷。

喺呢啲情況下，你需要一個系統將測試分派到多個 CI runner，並將結果整合成統一視圖。測試分片就係做呢件事。

Tuist 使用歷史測試時間數據，透過 [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) 智能平衡各分片嘅負載，令每個 runner 大致同一時間完成。所有分片嘅結果會自動整合到 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，為你提供跨所有分片嘅統一測試套件視圖。

<.home_cards>
  <.home_card
    title="Xcode"
    details="將 Xcode 測試分片到平行 CI runner。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="將 Tuist 生成項目中嘅測試分片到平行 CI runner。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="將 Gradle 測試分片到平行 CI runner。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="將你 Elixir 項目中嘅測試分片到平行 CI runner。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="將 Cargo 測試目標分派到平行 CI worker。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
