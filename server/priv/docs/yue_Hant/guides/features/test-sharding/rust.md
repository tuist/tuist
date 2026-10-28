---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust 測試分片 {#rust-test-sharding}

Tuist 不會對普通的 `cargo test` 運行進行分片，也不會在 CI 工作節點之間分發其編譯後的測試。設定 shard-plan 環境變數不會改變 Cargo 執行的測試。

改為在單一 CI 工作中運行你的測試：

```sh
tuist cargo test --workspace
```

Cargo 管理本地測試並行性，而 Tuist 會報告結果，包括 doctests。請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 以了解設定和報告詳情。

你可以使用 Cargo 的套件選擇和測試篩選器來選擇每個工作執行的內容，但這些工作是獨立運行，並非由 Tuist 管理的分片。
