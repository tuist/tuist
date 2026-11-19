---
{
  "title": "測試分片",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試分片，將測試分散到多個 CI 執行器，加快測試套件的執行速度。"
}
---
# 測試分片 {#test-sharding}

現代 CI 主機提供多核心環境，可實現一定程度的測試並行。然而，有些情況下你需要超越單一主機的極限——例如同時運行的模擬器數量受限，或者你的測試套件規模已超出單一機器的處理能力。

在這些情況下，你需要一個系統將測試分配到多個 CI runner，並將結果聚合為統一視圖。這就是測試分片的作用。

Tuist 利用歷史測試耗時數據，透過 [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem) 智能平衡各分片的負載，讓每個 runner 大致在同一時間完成。所有分片的結果會自動聚合到 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>，讓你從單一視圖查看整個測試套件的狀況。分片能縮短實際耗時，但可能增加機器時間；[Slow tests](https://tuist.dev/solutions/slow-tests) 和 [CI costs](https://tuist.dev/solutions/ci-costs) 說明了如何權衡兩者。

<.home_cards>
  <.home_card
    title="Xcode"
    details="將 Xcode 測試分片到並行 CI runner。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="將 Tuist 生成的專案中的測試分片到並行 CI runner。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="將 Gradle 測試分片到並行 CI runner。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="將 Elixir 專案的測試分片到並行 CI runner。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="將 Cargo 測試目標分配到並行 CI worker。"
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="在使用託管方案的情況下，將發現的 Once 測試批次分配到 CI worker，並合併結果。"
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
