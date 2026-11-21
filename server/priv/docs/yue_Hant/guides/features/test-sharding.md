---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Test Sharding，將測試分散到多個 CI runner 上執行，以加快測試套件的執行速度。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，支援一定程度的測試並行化。不過，有些情況需要超越單一主機的能力——例如同時運行的模擬器數量有限，或者測試套件規模已經超出單一機器的負荷。

在這些情況下，你需要一個系統將測試分發到多個 CI runner，並將結果匯總成統一的視圖。這就是測試分片的作用。

Tuist 使用歷史測試計時數據，透過 [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) 智能地在各分片之間平衡負載，讓每個 runner 大致在同一時間完成。所有分片的結果會自動匯總到 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，讓你從單一視圖查看整個測試套件在所有分片的狀況。分片可以縮短牆鐘時間，但可能增加機器時間；[Slow tests](https://tuist.dev/solutions/slow-tests) 和 [CI costs](https://tuist.dev/solutions/ci-costs) 說明如何權衡兩者。

<.home_cards>
  <.home_card
    title="Xcode"
    details="將 Xcode 測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="將 Tuist 生成的專案中的測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="將 Gradle 測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="將你的 Elixir 專案測試分片到並行的 CI runner。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="將 Cargo 測試目標分發到並行的 CI worker。"
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="在使用託管方案的情況下，將發現的 Struo 測試批次分發到 CI worker，並合併結果。"
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
