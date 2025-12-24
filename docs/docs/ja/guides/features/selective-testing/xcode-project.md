---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcodeプロジェクト{#xcode-project}

警告 要件
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

Xcode プロジェクトのテストをコマンドラインから選択的に実行することができます。そのためには、`xcodebuild` コマンドの前に、`tuist`
を付けることができます - 例えば、`tuist xcodebuild test -scheme App`
。このコマンドはプロジェクトをハッシュし、成功すると、将来の実行で何が変更されたかを判断するためにハッシュを永続化します。

今後の実行では、`tuist xcodebuild test`
は透過的にハッシュを使用してテストを絞り込み、最後に成功したテストの実行以降に変更されたものだけを実行する。

例えば、次のような依存関係グラフを仮定する：

- `FeatureA` は`FeatureATests` を持ち、`Core に依存している。`
- `FeatureB` は、`FeatureBTests` をテストし、`Core に依存する。`
- `コア` にはテストがある`CoreTests`

`tuist xcodebuild test` このように動作する：

| アクション                        | 説明                                                       | 内部状態                                                             |
| ---------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------- |
| `tuist xcodebuild test` 呼び出し | `CoreTests` 、`FeatureATests` 、`FeatureBTests のテストを実行する。` | `FeatureATests`,`FeatureBTests` and`CoreTests` のハッシュが永続化される。     |
| `FeatureA` が更新される            | 開発者はターゲットのコードを修正する。                                      | 同上                                                               |
| `tuist xcodebuild test` 呼び出し | ハッシュが変更されたため、`FeatureATests` のテストを実行する。                  | `FeatureATests` の新しいハッシュが永続化される。                                 |
| `コア` を更新                     | 開発者はターゲットのコードを修正する。                                      | 同上                                                               |
| `tuist xcodebuild test` 呼び出し | `CoreTests` 、`FeatureATests` 、`FeatureBTests のテストを実行する。` | `FeatureATests` `FeatureBTests` 、および`CoreTests` の新しいハッシュが永続化される。 |

CI で`tuist xcodebuild test`
を使うには、<LocalizedLink href="/guides/integrations/continuous-integration">Continuous integration guide</LocalizedLink> の指示に従ってください。

次のビデオで、セレクティブ・テストの様子をご覧ください：

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
