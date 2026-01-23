---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# 選択的検査{#selective-testing}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

生成したプロジェクトでテストを選択的に実行するには、`tuist test`
コマンドを使用します。このコマンドは、<LocalizedLink href="/guides/features/cache#cache-warming">キャッシュのウォームアップ</LocalizedLink>と同様の方法でXcodeプロジェクトを<LocalizedLink href="/guides/features/projects/hashing">ハッシュ化</LocalizedLink>し、成功時にはハッシュを保存して、今後の実行時に変更箇所を特定します。

今後の実行では、`tuist test` はハッシュを透過的に使用し、前回の正常なテスト実行以降に変更されたテストのみを実行対象に絞り込みます。

例として、以下の依存関係グラフを想定します：

- `FeatureA` has tests`FeatureATests`, and depends on`Core`
- `FeatureB` has tests`FeatureBTests`, and depends on`Core`
- `Core` にはテストがあります`CoreTests`

`tuist test` は以下のように動作します:

| アクション                   | 説明                                                            | 内部状態                                                            |
| ----------------------- | ------------------------------------------------------------- | --------------------------------------------------------------- |
| `tuist test` invocation | `のCoreTests` 、`のFeatureATests` 、および`のFeatureBTestsでテストを実行します` | `FeatureATests、` 、`FeatureBTests、` 、`CoreTests、` のハッシュは永続化されます  |
| `FeatureA` が更新されました     | 開発者は対象のコードを修正する                                               | 以前と同様                                                           |
| `tuist test` invocation | `FeatureATests` のテストを実行します。ハッシュが変更されたためです。                    | `FeatureATestsの新しいハッシュ値` が永続化されました                              |
| `Core` が更新されました         | 開発者は対象のコードを修正する                                               | 以前と同様                                                           |
| `tuist test` invocation | `のCoreTests` 、`のFeatureATests` 、および`のFeatureBTestsでテストを実行します` | 新しいハッシュ値：`FeatureATests` `FeatureBTests` ` CoreTests` が永続化されました |

`tuist test`
はバイナリキャッシュと直接連携し、ローカルまたはリモートストレージから可能な限り多くのバイナリを利用することで、テストスイート実行時のビルド時間を短縮します。選択的テストとバイナリキャッシュの組み合わせにより、CI環境でのテスト実行時間を大幅に削減できます。

## UIテスト{#ui-tests}

TuistはUIテストの選択的実行をサポートしています。ただし、Tuistは事前に実行先を知る必要があります。`の`
パラメータで実行先を指定した場合のみ、TuistはUIテストを選択的に実行します。例：
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
