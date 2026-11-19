---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試分片，將測試分散至多個 CI 執行器，以加快測試套件的執行速度。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，可實現一定程度的測試平行化。然而，有些情況需要超越單一主機的能力——例如，當同時執行的模擬器數量受限，或測試套件規模已超出單一機器的負荷時。

在這些情況下，你需要一個能將測試分散到多個 CI 執行器，並將結果彙整為統一視圖的系統。這就是測試分片的作用。

Tuist 利用歷史測試計時資料，透過 [bin-packing 演算法](https://en.wikipedia.org/wiki/Bin_packing_problem) 智慧地在各分片間平衡負載，讓每個執行器大致在同一時間完成。所有分片的結果會自動彙整至 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，讓你獲得跨所有分片的測試套件統一視圖。分片能縮短實際耗時，但可能增加機器時間；[Slow tests](https://tuist.dev/solutions/slow-tests) 與 [CI costs](https://tuist.dev/solutions/ci-costs) 說明了如何權衡兩者。

<.home_cards>
  <.home_card
    title="Xcode"
    details="在平行的 CI 執行器之間分片 Xcode 測試。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
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
    details="在平行的 CI 執行器之間分片你的 Elixir 專案測試。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="在平行的 CI 工作節點之間分配 Cargo 測試目標。"
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="在使用託管方案並合併結果的情況下，將發現的 Struo 測試批次分配到 CI 工作節點。"
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
