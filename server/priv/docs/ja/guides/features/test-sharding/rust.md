---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust テストのシャーディング {#rust-test-sharding}

Tuist は通常の `cargo test` 実行をシャーディングしたり、コンパイルされたテストを CI ワーカー間で分散したりしません。shard-plan 環境変数を設定しても、Cargo が実行するテストは変わりません。

代わりに、単一の CI ジョブでテストを実行してください:

```sh
tuist cargo test --workspace
```

Cargo がローカルでのテスト並列処理を管理し、Tuist が doctest を含む結果をレポートします。セットアップとレポートの詳細については、<.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を参照してください。

Cargo のパッケージ選択とテストフィルターを使用して、各ジョブが実行する内容を選択できますが、これらのジョブは独立した実行であり、Tuist が管理するシャードではありません。
