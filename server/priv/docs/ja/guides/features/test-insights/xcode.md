---
{
  "title": "Xcodeテストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist Test InsightsでXcodeのテスト分析を追跡し、低速なテストや不安定なテストを特定します。"
}
---
# Xcodeテストインサイト {#xcode-test-insights}

Tuist Test Insightsは、遅いテストの特定やCI実行の失敗原因を迅速に把握することで、テストスイートの健全性を監視するためのXcodeテスト分析機能を提供します。テストスイートが大きくなると、テストの徐々に遅くなる傾向や断続的な失敗といったトレンドを見極めることが難しくなります。Tuist Test Insightsは、高速で信頼性の高いテストスイートを維持するために必要な可視性を提供します。

Test Insightsを使用すると、以下のような質問に答えられます：
- テストが遅くなっていないか？どのテストか？
- 不安定で注意が必要なテストはどれか？
- CI実行が失敗したのはなぜか？

## セットアップ {#setup}

テストの追跡を開始するには、スキームのテスト後処理アクションに `tuist inspect test` コマンドを追加してください：

![テスト検査用の後処理アクション](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/) を使用している場合、スクリプトで後処理アクション環境内で `tuist` を有効にする必要があります：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Miseとプロジェクトパス**
>
> 環境の `PATH` 環境変数はスキームの後処理アクションには継承されないため、Miseのインストール方法に応じて絶対パスを使用する必要があります。さらに、$SRCROOTが指すディレクトリからMiseを実行できるように、プロジェクト内のターゲットからビルド設定を継承することを忘れないでください。

Tuistアカウントにログインしている限り、テスト実行が追跡されます。Tuistダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます：

![テストインサイト付きダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

全体的なトレンドだけでなく、CIでの失敗や遅いテストのデバッグ時など、個々のテストを深く掘り下げることもできます：

![テスト詳細](/images/guides/features/build-insights/test-detail.png)

## 生成されたプロジェクト {#generated-projects}

> [!NOTE]
> 自動生成されたスキームには、`tuist inspect test` 後処理アクションが自動的に含まれます。
>
> 自動生成されたスキームでテストインサイトの追跡に興味がない場合は、[testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 生成オプションを使用して無効にしてください。

カスタムスキームを持つ生成されたプロジェクトを使用している場合、テストインサイト用の後処理アクションを設定できます：

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

Miseを使用していない場合、スクリプトは以下のように簡略化できます：

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

CIでテストインサイトを追跡するには、CIが <.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link> であることを確認する必要があります。

さらに、以下のいずれかを行う必要があります：
- `xcodebuild` アクションを呼び出す際に、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> コマンドを使用する。
- `xcodebuild` 呼び出しに `-resultBundlePath` を追加する。

`xcodebuild` が `-resultBundlePath` なしでプロジェクトをテストする場合、必要な結果バンドルファイルが生成されません。`tuist inspect test` 後処理アクションは、テストを分析するためにこれらのファイルを必要とします。

### Git履歴 {#git-history}

CIでは、Tuistはチェックアウトのコミット履歴（コミットSHA、その親、コミット日時、および実行とそのプルリクエストのベースブランチが属していたブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作者はアップロードされません。これは、マージキューがテストしたコミットなど、どのコミットがデフォルトブランチに着陸したかをTuistに伝えます。Tuistはチェックアウトが既に持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ以外では、履歴を取得しません。コードカバレッジがある場合、ファイルの内容なしで浅いチェックアウトが深化され、プルリクエストが分岐した場所を見つけ、Tuistが既に持っているコミットに到達するため、コミットはそれが乗っている親なしでアップロードされることはありません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git履歴を読み取ったりアップロードしたりしません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに連絡することなく、チェックアウトのみを読み取ります。 |
