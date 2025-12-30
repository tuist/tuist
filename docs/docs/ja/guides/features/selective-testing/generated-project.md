---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# 生成されたプロジェクト{#generated-project}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/projects">生成プロジェクト</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

生成されたプロジェクトでテストを選択的に実行するには、`tuist test`
コマンドを使用します。このコマンドは、<LocalizedLink href="/guides/features/cache#cache-warming">キャッシュを温める</LocalizedLink>のと同じように、あなたの
Xcode プロジェクトを<LocalizedLink href="/guides/features/projects/hashing">ハッシュ化</LocalizedLink>し、成功すると、将来の実行で何が変更されたかを判断するためにハッシュを持続させます。

今後の実行では、`tuist test` 、透過的にハッシュを使用してテストを絞り込み、最後に成功したテストの実行以降に変更されたものだけを実行する。

例えば、次のような依存関係グラフを仮定する：

- `FeatureA` は`FeatureATests` を持ち、`Core に依存している。`
- `FeatureB` は、`FeatureBTests` をテストし、`Core に依存する。`
- `コア` にはテストがある`CoreTests`

`tuistテスト` ：

| アクション             | 説明                                                       | 内部状態                                                             |
| ----------------- | -------------------------------------------------------- | ---------------------------------------------------------------- |
| `tuistテスト` 呼び出し   | `CoreTests` 、`FeatureATests` 、`FeatureBTests のテストを実行する。` | `FeatureATests`,`FeatureBTests` and`CoreTests` のハッシュが永続化される。     |
| `FeatureA` が更新される | 開発者はターゲットのコードを修正する。                                      | 同上                                                               |
| `tuistテスト` 呼び出し   | ハッシュが変更されたため、`FeatureATests` のテストを実行する。                  | `FeatureATests` の新しいハッシュが永続化される。                                 |
| `コア` を更新          | 開発者はターゲットのコードを修正する。                                      | 同上                                                               |
| `tuistテスト` 呼び出し   | `CoreTests` 、`FeatureATests` 、`FeatureBTests のテストを実行する。` | `FeatureATests` `FeatureBTests` 、および`CoreTests` の新しいハッシュが永続化される。 |

`tuist test`
はバイナリキャッシングと直接統合し、ローカルまたはリモートのストレージからできるだけ多くのバイナリを使用して、テストスイートを実行する際のビルド時間を改善します。選択的テストとバイナリキャッシングを組み合わせることで、CIでテストを実行する時間を劇的に短縮できます。

## UIテスト{#ui-tests}

TuistはUIテストの選択テストをサポートしている。ただし、Tuistは事前にデスティネーションを知っておく必要がある。`destination`
パラメータを指定した場合のみ、Tuist は次のように UI テストを選択的に実行する：
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
