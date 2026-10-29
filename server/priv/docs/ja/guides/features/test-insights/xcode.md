---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Xcode テストインサイト {#xcode-test-insights}

Tuist Test Insights は、遅いテストを特定したり、失敗した CI 実行を迅速に理解することで、テストスイートの健全性を監視するための Xcode テスト分析を提供します。テストスイートが大きくなるにつれて、徐々に遅くなるテストや断続的な失敗といった傾向を見極めることがますます難しくなります。Tuist Test Insights は、高速で信頼性の高いテストスイートを維持するために必要な可視性を提供します。

Test Insights を使用すると、以下のような質問に答えることができます。
- テストが遅くなっていますか？どのテストですか？
- 不安定で注意が必要なテストはどれですか？
- CI 実行が失敗したのはなぜですか？

## セットアップ {#setup}

テストの追跡を開始するには、スキームのテスト後処理アクションに `tuist inspect test` コマンドを追加して活用できます。

![テストを検査するための後処理アクション](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) を使用している場合、スクリプトは後処理アクション環境で `tuist` をアクティブにする必要があります。
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise とプロジェクトパス**
>
> 環境の `PATH` 環境変数はスキームの後処理アクションには継承されないため、Mise のインストール方法に応じて Mise の絶対パスを使用する必要があります。さらに、$SRCROOT が指すディレクトリから Mise を実行できるように、プロジェクト内のターゲットからビルド設定を継承することを忘れないでください。

Tuist アカウントにログインしている限り、テスト実行が追跡されます。Tuist ダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます。

![テストインサイト付きダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

全体的な傾向に加えて、CI での失敗や遅いテストのデバッグ時など、個々のテストを詳しく調べることもできます。

![テスト詳細](/images/guides/features/build-insights/test-detail.png)

## 生成されたプロジェクト {#generated-projects}

> [!NOTE]
> 自動生成されたスキームには、`tuist inspect test` 後処理アクションが自動的に含まれます。

>
> 自動生成されたスキームでテストインサイトの追跡に関心がない場合は、[testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 生成オプションを使用して無効にしてください。

カスタムスキームを持つ生成されたプロジェクトを使用している場合、テストインサイトのために後処理アクションを設定できます。

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Mise を使用していない場合、スクリプトは次のように簡略化できます。

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## 継続的インテグレーション {#continuous-integration}

CI でテストインサイトを追跡するには、CI が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証</.localized_link>されていることを確認する必要があります。

さらに、以下のいずれかを行う必要があります。
- `xcodebuild` アクションを呼び出す際に、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> コマンドを使用する。
- `xcodebuild` 呼び出しに `-resultBundlePath` を追加する。

`xcodebuild` が `-resultBundlePath` なしでプロジェクトをテストする場合、必要な結果バンドルファイルは生成されません。`tuist inspect test` 後処理アクションは、テストを分析するためにこれらのファイルを必要とします。

### Git ヒストリー {#git-history}

CI では、Tuist はチェックアウトのコミット履歴（コミット SHA、その親、コミット日時、および実行とそのプルリクエストのベースブランチが属していたブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作成者はアップロードされません。これは、デフォルトブランチにマージされたコミット（例えば、マージキューによってテストされたもの）を Tuist に伝えます。Tuist はチェックアウトが既に持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ以外では、履歴を取得しません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 履歴を読み取ったりアップロードしたりしません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに連絡することなく、チェックアウトのみを読み取ります。 |
