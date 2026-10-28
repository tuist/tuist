---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，允許一定程度的測試平行化。然而，有些情況需要超越單一主機所能提供的能力——例如，當您可同時執行的模擬器數量受限，或您的測試套件規模已超出單一機器的負荷時。

在這些情況下，您需要一個系統，將測試分散到多個 CI 執行器上，並將結果彙整為統一的檢視畫面。這就是測試分片的作用。

Tuist 使用歷史測試計時資料，透過 [装箱演算法](https://en.wikipedia.org/wiki/Bin_packing_problem) 智慧地平衡各分片的負載，讓每個執行器大致在同一時間完成。所有分片的結果會自動彙整至 <.localized_link href="/guides/features/test-insights">測試洞察</.localized_link>，讓您獲得跨所有分片的測試套件統一檢視。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在平行的 CI 執行器之間分片 Xcode 測試。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="產生的專案"
    details="在平行的 CI 執行器之間分片 Tuist 產生的專案中的測試。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="在平行的 CI 執行器之間分片 Gradle 測試。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="在平行的 CI 執行器之間分片您的 Elixir 專案測試。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="了解純 Cargo 測試執行的測試分片可用性。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
