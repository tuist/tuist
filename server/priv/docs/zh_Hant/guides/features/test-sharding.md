---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試分片，將測試分散至多個 CI 執行器，加速你的測試套件。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，可實現一定程度的測試平行化。然而，有些情況下你需要超越單一主機的能力——例如，當你受限於能同時執行的模擬器數量，或你的測試套件已超出單一機器的負荷時。

在這些情況下，你需要一個系統，將測試分散到多個 CI 執行器上，並將結果匯總為統一的視圖。這就是測試分片的作用。

Tuist 使用歷史測試計時數據，透過 [装箱演算法](https://en.wikipedia.org/wiki/Bin_packing_problem) 智慧地平衡各分片的負載，讓每個執行器大致在同一時間完成。所有分片的結果會自動匯總至 <.localized_link href="/guides/features/test-insights">測試洞察</.localized_link>，讓你獲得跨所有分片的測試套件統一視圖。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在平行 CI 執行器之間分片 Xcode 測試。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成的專案"
    details="在平行 CI 執行器之間分片 Tuist 生成專案中的測試。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在平行 CI 執行器之間分片 Gradle 測試。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="在平行 CI 執行器之間分片你的 Elixir 專案測試。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="在平行 CI 工作節點之間分配 Cargo 測試目標。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
