---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust 測試分片 {#rust-test-sharding}

Tuist 不會對普通的 `cargo test` 執行進行分片，也不會將編譯後的測試分散到 CI 工作節點上。設定 shard-plan 環境變數不會改變 Cargo 執行的測試項目。

請改為在單一 CI 工作中執行您的測試：

```sh
tuist cargo test --workspace
```

Cargo 管理本機測試的平行處理，而 Tuist 會回報結果，包括文件測試。請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 以了解設定與回報詳細資訊。

您可以使用 Cargo 的套件選擇和測試篩選器來決定每個工作要執行哪些測試，但這些工作是獨立執行的，並非由 Tuist 管理的分片。
