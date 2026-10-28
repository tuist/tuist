---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust 测试分片 {#rust-test-sharding}

Tuist 不会对普通的 `cargo test` 运行进行分片，也不会将编译后的测试分发到 CI 工作节点。设置 shard-plan 环境变量不会改变 Cargo 执行的测试。

改为在单个 CI 作业中运行测试：

```sh
tuist cargo test --workspace
```

Cargo 管理本地测试并行性，Tuist 报告结果，包括文档测试。有关设置和报告详情，请参阅 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>。

你可以使用 Cargo 的包选择和测试过滤器来选择每个作业执行的内容，但这些作业是独立运行的，并非由 Tuist 管理的分片。
