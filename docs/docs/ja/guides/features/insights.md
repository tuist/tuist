---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# ビルド・インサイト{#build-insights}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

大規模プロジェクトの作業は、面倒な作業のように感じるべきではありません。実際、2週間前に始めたプロジェクトに取り組むのと同じくらい楽しいものであるべきです。
そうならない理由の一つは、プロジェクトが大きくなるにつれて開発者の体験が悪化するためです。ビルド時間が長くなり、テストは遅く不安定になります。こうした問題は、耐えられないほど深刻化するまで見過ごされがちです。しかし、その段階になると対処が困難になります。Tuist
Insightsは、プロジェクトの健全性を監視し、プロジェクトが拡大する中でも生産的な開発環境を維持するためのツールを提供します。

つまり、Tuist Insightsは次のような質問への回答を支援します：
- 先週、ビルド時間が大幅に増加しましたか？
- CIでのビルドは、ローカル開発と比べて遅いのですか？

CIワークフローのパフォーマンスについては何らかの指標をお持ちかもしれませんが、ローカル開発環境については同様の可視性がない可能性があります。しかし、ローカルビルド時間は開発者体験に寄与する最も重要な要素の一つです。

ローカルビルド時間の追跡を開始するには、schemeのpost-actionに以下のコマンドを追加することで、`tuist inspect build`
を活用できます：

![ビルド検査後のアクション](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Tuistがビルド構成を追跡できるようにするため、「ビルド設定の提供元」を実行ファイルまたはメインのビルドターゲットに設定することを推奨します。
<!-- -->
:::

::: info
<!-- -->
<LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>を使用していない場合、ビルドが失敗した際にはポストスキームアクションは実行されません。
<!-- -->
:::
> 
> ``
> Xcodeの非公式機能により、この場合でも実行可能です。該当する`プロジェクトの.pbxprojファイル内の`ビルドアクション設定で、以下の属性を次のように設定してください：`runPostActionsOnFailure`
> ` YES`
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Mise](https://mise.jdx.dev/)を使用している場合、スクリプトはポストアクション環境で`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
あなたの環境の`PATH` 環境変数は、scheme
postアクションによって継承されないので、Miseの絶対パスを使用する必要があります。さらに、$SRCROOTが指すディレクトリからMiseを実行できるように、プロジェクトのターゲットからビルド設定を継承することを忘れないでください。
<!-- -->
:::


Tuistアカウントにログインしている限り、ローカルビルドが追跡されるようになりました。Tuistダッシュボードでビルド時間を確認し、時間の経過に伴う変化を把握できます：


::: チップ
<!-- -->
ダッシュボードに素早くアクセスするには、CLIから`tuist project show --web` を実行してください。
<!-- -->
:::

![ビルドインサイト付きダッシュボード](/images/guides/features/insights/builds-dashboard.png)

## 生成されたプロジェクト{#generated-projects}。

::: info
<!-- -->
自動生成されたスキームには、`tuist inspect build` post-actionが自動的に含まれる。
<!-- -->
:::
> 
> 自動生成されたスキームでインサイトを追跡することに興味がない場合は、<LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>生成オプションを使用してインサイトを無効にします。

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
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Miseを使用していない場合、スクリプトは以下のように簡略化できます：

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## 継続的インテグレーション{#continuous-integration}

CIでビルドのインサイトを追跡するには、CIが<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認する必要があります。

さらに、以下のいずれかが必要です：
- `xcodebuild`
  アクションを呼び出す際は、<LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> コマンドを使用してください。
- `` の xcodebuild 呼び出しに、` -resultBundlePath ` を追加してください。``

`xcodebuild` が、`-resultBundlePath`
なしでプロジェクトをビルドするとき、必要なアクティビティログと結果バンドルファイルは生成されません。`tuist inspect build`
ポストアクションでは、ビルドを分析するためにこれらのファイルが必要です。
