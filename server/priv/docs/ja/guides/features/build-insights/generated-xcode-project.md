---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuistダッシュボードで、Tuistが生成したXcodeプロジェクトのビルド分析を追跡します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動生成されたスキームには、`tuist inspect build` ポストアクションが自動的に含まれます。
>
> 生成されたスキームでビルドインサイトをトラックしたくない場合は、[buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) を使用して無効にしてください。

カスタムスキームを含む生成プロジェクトを使用している場合は、ポストアクションを自分で追加する必要があります。[Mise](https://mise.jdx.dev/) の場合：

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
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Miseを使用していない場合は、Xcodeのポストアクションがシェルの `PATH` を継承しないため、スキームの環境で `tuist` が利用可能であることを確認する必要があります。[Homebrew](https://brew.sh/) インストールの場合：

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
