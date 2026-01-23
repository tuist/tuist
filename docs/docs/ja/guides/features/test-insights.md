---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# テストインサイト{#test-insights}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

テストインサイトは、遅いテストを特定したりCI実行の失敗を迅速に把握したりすることで、テストスイートの健全性を監視するのに役立ちます。テストスイートが大きくなるにつれ、テストの漸進的な遅延や断続的な失敗といった傾向を把握することがますます困難になります。Tuist
Test Insightsは、高速で信頼性の高いテストスイートを維持するために必要な可視性を提供します。

Test Insights を使用すると、次のような質問に答えられます：
- テストの実行速度は低下しましたか？どのテストですか？
- どのテストが不安定で注意が必要ですか？
- CIの実行が失敗した理由は？

## 設定{#setup}

テストの追跡を開始するには、スキームのテスト後処理に次のコマンドを追加できます:`tuist inspect test`

![テスト検証後のアクション](/images/guides/features/insights/inspect-test-scheme-post-action.png)

Mise](https://mise.jdx.dev/)を使用している場合、スクリプトはポストアクション環境で`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
あなたの環境の`PATH` 環境変数は、scheme
postアクションによって継承されないので、Miseの絶対パスを使用する必要があります。さらに、$SRCROOTが指すディレクトリからMiseを実行できるように、プロジェクトのターゲットからビルド設定を継承することを忘れないでください。
<!-- -->
:::

Tuistアカウントにログインしている限り、テスト実行は自動的に追跡されます。Tuistダッシュボードでテストの分析データにアクセスし、時間の経過に伴う変化を確認できます：

![テストインサイト付きダッシュボード](/images/guides/features/insights/tests-dashboard.png)

全体的な傾向に加え、CI 上で失敗したテストや遅いテストをデバッグする際など、個々のテストを詳細に分析することも可能です：

![テスト詳細](/images/guides/features/insights/test-detail.png)

## 生成されたプロジェクト{#generated-projects}。

::: info
<!-- -->
自動生成されたスキームには、`tuist inspect build` post-actionが自動的に含まれる。
<!-- -->
:::
> 
> 自動生成されたスキームでインサイトを追跡することに興味がない場合は、<LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">buildInsightsDisabled</LocalizedLink>生成オプションを使用してインサイトを無効にします。

カスタムスキームで生成されたプロジェクトを使用している場合、ビルドインサイトのポストアクションを設定できます：

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

## 継続的インテグレーション{#continuous-integration}

CIでビルドのインサイトを追跡するには、CIが<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認する必要があります。

さらに、以下のいずれかが必要です：
- `xcodebuild`
  アクションを呼び出す際は、<LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> コマンドを使用してください。
- `` の xcodebuild 呼び出しに、` -resultBundlePath ` を追加してください。``

`xcodebuild` で、`-resultBundlePath`
を指定せずにプロジェクトをテストすると、必要な結果バンドルファイルが生成されません。`tuist inspect test`
のポストアクションでは、テストを分析するためにこれらのファイルが必要です。
