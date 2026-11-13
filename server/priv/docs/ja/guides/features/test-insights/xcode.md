---
{
  "title": "Xcodeテストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist Test InsightsでXcodeのテスト分析を追跡し、低速なテストや不安定なテストを特定します。"
}
---
# Xcodeテストのインサイト {#xcode-test-insights}

Tuist Test Insightsは、遅いテストを特定したり、失敗したCI実行をすばやく理解することで、テストスイートの健全性を監視するためのXcodeテスト分析を提供します。テストスイートが大きくなるにつれて、徐々に遅くなるテストや断続的な失敗といった傾向を見極めることが難しくなります。Tuist Test Insightsは、高速で信頼性の高いテストスイートを維持するために必要な可視性を提供します。

Test Insightsを使用すると、次のような質問に答えることができます。
- テストが遅くなったか？どのテストか？
- 不安定で注意が必要なテストはどれか？
- CI実行が失敗したのはなぜか？

## セットアップ {#setup}

テストの追跡を開始するには、スキームのテスト後処理アクションに`tuist inspect test`コマンドを追加して利用できます。

![テストを検査するための後処理アクション](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

[Mise](https://mise.jdx.dev/)を使用している場合、スクリプトで後処理アクション環境内で`tuist`を有効化する必要があります。
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Miseとプロジェクトパス**
>
> 環境の`PATH`環境変数はスキームの後処理アクションに継承されないため、Miseのインストール方法に応じて絶対パスを使用する必要があります。さらに、$SRCROOTが指すディレクトリからMiseを実行できるように、プロジェクト内のターゲットからビルド設定を継承することを忘れないでください。

Tuistアカウントにログインしている限り、テスト実行が追跡されます。Tuistダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます。

![テストインサイト付きダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

全体的な傾向だけでなく、CIでの失敗や遅いテストのデバッグ時など、個々のテストを深く掘り下げることもできます。

![テストの詳細](/images/guides/features/build-insights/test-detail.png)

## 生成されたプロジェクト {#generated-projects}

> [!NOTE]
> 自動生成されたスキームには、`tuist inspect test`後処理アクションが自動的に含まれます。
>
> 自動生成されたスキームでテストインサイトの追跡に関心がない場合は、[testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)生成オプションを使用して無効にしてください。

カスタムスキームを使用した生成済みプロジェクトを使用している場合、テストインサイト用の後処理アクションを設定できます。

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

Miseを使用していない場合、スクリプトは次のように簡略化できます。

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

CIでテストインサイトを追跡するには、CIが<.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link>であることを確認する必要があります。

さらに、次のいずれかを行う必要があります。
- `xcodebuild`アクションを呼び出す際に、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>コマンドを使用する。
- `xcodebuild`の呼び出しに`-resultBundlePath`を追加する。

`xcodebuild`が`-resultBundlePath`なしでプロジェクトをテストする場合、必要な結果バンドルファイルは生成されません。`tuist inspect test`後処理アクションは、テストを分析するためにこれらのファイルを必要とします。

### Git履歴 {#git-history}

CIでは、Tuistはチェックアウトのコミット履歴（コミットSHA、その親、コミット日時、および実行とそのプルリクエストのベースブランチが属していたブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作成者はアップロードされません。これは、マージキューがテストしたものなど、どのコミットがデフォルトブランチに取り込まれたかをTuistに伝えます。Tuistはチェックアウトがすでに持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ以外では、履歴を取得しません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git履歴の読み取りやアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに連絡せずに、チェックアウトのみを読み取ります。 |
