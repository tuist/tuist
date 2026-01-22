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
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

大規模なプロジェクトに取り組むことは、雑用のように感じるべきではない。実際、ほんの2週間前に始めたプロジェクトと同じくらい楽しいはずだ。そうならない理由のひとつは、プロジェクトが大きくなるにつれて、開発者のエクスペリエンスが損なわれるからだ。ビルドにかかる時間は長くなり、テストは遅く、不安定になる。耐えられなくなるまで、これらの問題を見過ごすのは簡単なことだが、しかしその時点で対処するのは難しい。Tuist
Insightsは、プロジェクトの健全性を監視し、プロジェクトの規模が拡大しても生産性の高い開発者環境を維持するためのツールを提供する。

言い換えれば、Tuist Insightsは次のような質問に答えるのに役立つ：
- この1週間で、ビルドタイムが大幅に伸びましたか？
- CIでのビルドは、ローカル開発と比べて遅いのですか？

おそらくCIワークフローのパフォーマンスに関するメトリクスは持っているだろうが、ローカルの開発環境については同じように可視化できていないかもしれない。しかし、ローカルのビルド時間は開発者のエクスペリエンスに貢献する最も重要な要素の1つです。

ローカルビルド時間の追跡を開始するには、`tuist inspect build` コマンドをスキームのポストアクションに追加することで活用できる：

![ビルド検査の事後処理](/images/guides/features/insights/inspect-build-scheme-post-action.png)。

::: info
<!-- -->
Tuistがビルド設定を追跡できるように、"Provide build settings from
"を実行ファイルまたはメインのビルドターゲットに設定することを推奨する。
<!-- -->
:::

::: info
<!-- -->
1}生成されたプロジェクト</LocalizedLink>を使用していない場合、ビルドに失敗してもポスト・スキーム・アクションは実行されません。
<!-- -->
:::
> 
> Xcodeの文書化されていない機能により、この場合でも実行することができます。`project.pbxproj`
> ファイルの該当するスキームの`BuildAction` の`runPostActionsOnFailure` 属性を`YES` に設定します：
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


Tuistアカウントにログインしている限り、ローカルのビルドが追跡されるようになりました。Tuistダッシュボードでビルドタイムにアクセスし、時間の経過とともにビルドタイムがどのように変化していくかを確認できるようになりました：


::: チップ
<!-- -->
ダッシュボードに素早くアクセスするには、CLIから`tuist project show --web` を実行する。
<!-- -->
:::

ビルド・インサイトのダッシュボード](/images/guides/features/insights/builds-dashboard.png)。

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

三瀬を使用していない場合、スクリプトは次のように簡略化できる：

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

さらに、以下のいずれかが必要となる：
- `xcodebuild`
  アクションを呼び出すときは、<LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> コマンドを使用する。
- `xcodebuild` の呼び出しに`-resultBundlePath` を追加する。

`xcodebuild` が、`-resultBundlePath`
なしでプロジェクトをビルドするとき、必要なアクティビティログと結果バンドルファイルは生成されません。`tuist inspect build`
ポストアクションでは、ビルドを分析するためにこれらのファイルが必要です。
