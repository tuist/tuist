---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# インサイト{#insights}

警告 要件
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

大規模なプロジェクトに取り組むことは、雑用のように感じるべきではない。実際、ほんの2週間前に始めたプロジェクトと同じくらい楽しいはずだ。そうならない理由の一つは、プロジェクトが大きくなるにつれて、開発者の体験が損なわれるからだ。ビルドにかかる時間は長くなり、テストは遅く、不安定になる。耐えられなくなるまで、これらの問題を見過ごすのは簡単なことだが、しかしその時点で対処するのは難しい。Tuist
Insightsは、プロジェクトの健全性を監視し、プロジェクトの規模が拡大しても生産性の高い開発者環境を維持するためのツールを提供する。

言い換えれば、Tuist Insightsは次のような質問に答えるのに役立つ：
- この1週間で、ビルドタイムが大幅に伸びましたか？
- 私のテストは遅くなりましたか？どのテストですか？

::: info
<!-- -->
Tuist Insightsは開発初期段階にある。
<!-- -->
:::

## ビルド{#builds}

おそらくCIワークフローのパフォーマンスに関するメトリクスは持っているだろうが、ローカルの開発環境については同じように可視化できていないかもしれない。しかし、ローカルのビルド時間は、開発者のエクスペリエンスに貢献する最も重要な要素の1つです。

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
<LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>を使用していない場合、ビルドに失敗してもポスト・スキーム・アクションは実行されません。
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

## テスト {#tests}

ビルドを追跡するだけでなく、テストを監視することもできます。テストインサイトは、遅いテストを特定したり、失敗した CI の実行を素早く理解するのに役立ちます。

テストの追跡を開始するには、`tuist inspect test` コマンドをスキームのテストのポストアクションに追加することで活用できます：

検査の事後処理](/images/guides/features/insights/inspect-test-scheme-post-action.png)。

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

Tuistアカウントにログインしている限り、テスト実行が追跡されるようになりました。Tuistダッシュボードでテストインサイトにアクセスし、時間の経過とともにどのように変化していくかを見ることができます：

テスト・インサイトのダッシュボード](/images/guides/features/insights/tests-dashboard.png)。

全体的な傾向とは別に、CI上の失敗や遅いテストをデバッグするときなど、個々のテストを深く掘り下げることもできます：

テスト詳細](/images/guides/features/insights/test-detail.png)。

## 生成されたプロジェクト{#generated-projects}。

::: info
<!-- -->
自動生成されたスキームには、`tuist inspect build` と`tuist inspect test` の両方のポストアクションが自動的に含まれる。
<!-- -->
:::
> 
> 自動生成されたスキームでインサイトを追跡することに興味がない場合は、<LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>と<LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>生成オプションを使用してインサイトを無効にします。

カスタムスキームで生成されたプロジェクトを使う場合、ビルドとテストの両方のインサイトに対してポストアクションを設定できます：

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
),
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

CIでビルドとテストのインサイトを追跡するには、CIが<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証されていることを確認する必要がある</LocalizedLink>。

さらに、以下のいずれかが必要となる：
- `xcodebuild`
  アクションを呼び出すときは、<LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> コマンドを使用する。
- `xcodebuild` の呼び出しに`-resultBundlePath` を追加する。

`xcodebuild` が、`-resultBundlePath`
なしでプロジェクトをビルドまたはテストするとき、必要なアクティビティログと結果バンドルファイルは生成されません。`tuist inspect build`
と`tuist inspect test` の両方のポストアクションは、ビルドとテストを分析するためにこれらのファイルを必要とします。
