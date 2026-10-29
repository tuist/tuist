---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，允許某種程度的測試平行化。然而，有些情況下你需要超越單一主機所能提供的能力——例如，當你受到可同時執行的模擬器數量限制，或當你的測試套件規模已超出單一機器的負荷時。

在這些情況下，你需要一個系統將測試分散到多個 CI 執行器上，並將結果匯總成統一的視圖。這正是測試分片的作用。

Tuist 使用歷史測試計時數據，透過 [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) 智能地在各分片之間平衡負載，使每個執行器大致在同一時間完成。所有分片的結果會自動匯總到 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，讓你獲得跨所有分片的測試套件統一視圖。

<.home_cards>
  <.home_card
    title="Xcode"
    details="將 Xcode 測試分片到平行的 CI 執行器上。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="將 Tuist 生成專案中的測試分片到平行的 CI 執行器上。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="將 Gradle 測試分片到平行的 CI 執行器上。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="將你的 Elixir 專案測試分片到平行的 CI 執行器上。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="將 Cargo 測試目標分散到平行的 CI 工作節點上。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
