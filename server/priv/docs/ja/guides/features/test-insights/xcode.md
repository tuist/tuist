---
{
  "title": "Xcode テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist Test Insights を使用して Xcode のテスト分析を追跡し、低速なテストや不安定なテストを特定します。"
}
---
# Xcode テストインサイト {#xcode-test-insights}

Tuist Test Insights は、遅いテストの特定や CI 実行の失敗原因を迅速に把握することで、テストスイートの健全性を監視するための Xcode テスト分析を提供します。テストスイートが大きくなると、徐々に遅くなるテストや断続的な失敗といった傾向を見極めることが難しくなります。Tuist Test Insights は、高速で信頼性の高いテストスイートを維持するために必要な可視性を実現します。

Test Insights を使用すると、以下のような疑問に答えられます。
- テストが遅くなっていませんか？どのテストですか？
- 不安定なテストはどれで、注意が必要ですか？
- CI 実行が失敗したのはなぜですか？

## セットアップ {#setup}

テストの追跡を開始するには、スキームのテスト後処理アクションに `tuist inspect test` コマンドを追加して活用できます。

![テストを検査する後処理アクション](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) を使用している場合、スクリプトは後処理アクション環境で `tuist` を有効にする必要があります。
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise とプロジェクトパス**
>
> 環境の `PATH` 環境変数はスキームの後処理アクションには継承されないため、Mise のインストール方法に応じた Mise の絶対パスを使用する必要があります。さらに、$SRCROOT が指すディレクトリから Mise を実行できるように、プロジェクト内のターゲットからビルド設定を継承することを忘れないでください。

Tuist アカウントにログインしていれば、テスト実行が追跡されます。Tuist ダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます。

![テストインサイト付きダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

全体的な傾向だけでなく、CI での失敗や遅いテストのデバッグ時など、個々のテストの詳細を深く掘り下げることもできます。

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

CI でテストインサイトを追跡するには、CI が <.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link> であることを確認する必要があります。

さらに、以下のいずれかを行う必要があります。
- `xcodebuild` アクションを呼び出す際に、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> コマンドを使用する。
- `xcodebuild` 呼び出しに `-resultBundlePath` を追加する。

`xcodebuild` が `-resultBundlePath` なしでプロジェクトをテストする場合、必要な結果バンドルファイルは生成されません。`tuist inspect test` 後処理アクションは、テストを分析するためにこれらのファイルを必要とします。

### Git ヒストリー {#git-history}

CI では、Tuist はチェックアウトのコミット履歴（コミット SHA、その親、コミット日時、および実行とそのプルリクエストのベースブランチが属していたブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作成者はアップロードされません。これは、マージキューがテストしたコミットなど、どのコミットがデフォルトブランチに取り込まれたかを Tuist に伝えます。Tuist はチェックアウトがすでに持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ以外では、履歴を取得しません。コードカバレッジがある場合、ファイルの内容なしで浅いチェックアウトが深化され、プルリクエストが分岐した場所を見つけ、Tuist がすでに持っているコミットに到達するため、コミットはそれが依存する親コミットなしでアップロードされることはありません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 履歴を読み取ったりアップロードしたりしません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに連絡せずに、チェックアウトのみを読み取ります。 |
| `TUIST_GIT_BRANCH=<branch>` | CI プロバイダーやチェックアウトの情報よりも優先して、実行のブランチ名を指定します。ブランチではなくコミットをチェックアウトし、そうでなければブランチ情報を持たない実行となる、Tuist が認識しない CI システムで設定してください。 |
