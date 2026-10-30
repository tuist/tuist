---
{
  "title": "生成された Xcode プロジェクト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Tuist が生成した Xcode プロジェクトのビルド分析を追跡します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動生成されたスキームには、`tuist inspect build` ポストアクションが自動的に含まれます。

>
> 生成されたスキームでビルドインサイトを追跡したくない場合は、[buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) を使用して無効にしてください。

カスタムスキームを含む生成済みプロジェクトを使用している場合は、ポストアクションを自分で追加する必要があります。[Mise](https://mise.jdx.dev/) の場合：

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

## CIでのビルドインサイト {#continuous-integration}

CIでビルドインサイトを追跡するには、CIが <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link> であることを確認してください。

Xcodebuild駆動のCIの場合、次のことを行う必要があります：
- `xcodebuild` アクションを呼び出す際は、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> を使用してください。
- `xcodebuild` コマンドに `-resultBundlePath` を追加してください。

`-resultBundlePath` がないと、必要なアクティビティログと結果バンドルが生成されず、`tuist inspect build` でビルドを分析できません。

## マシンメトリクス {#machine-metrics}

ビルドインサイトには、ビルド中にキャプチャされたマシンレベルのパフォーマンスメトリクス（CPU、メモリ、ネットワーク、ディスク使用量）を含めることができます。これを有効にするには、システムメトリクスを継続的にサンプリングする軽量なバックグラウンドデーモンを設定してください：

```bash
tuist setup insights
```

これにより、バックグラウンドでメトリクスをサンプリングするローカルデーモンが実行されます。データは `tuist inspect build` によって自動的に取得され、ビルドレポートとともにアップロードされます。

> [!TIP]
> **Ci**
>
> マシンメトリクスもキャプチャするには、ビルド前にCIマシンで `tuist setup insights` を実行してください。

マシンメトリクスの収集を停止するには、次を実行してください：

```bash
tuist teardown insights
```

これにより、デーモンのLaunchAgentがアンロードされ、plistが削除され、サンプリングされたメトリクスとデーモンログが `~/.local/state` から削除されるため、バックグラウンドで実行されているものは残りません。


## カスタムメタデータ {#custom-metadata}

環境変数を使用してビルドにメタデータを付加し、フィルタリングを改善できます。

### 環境変数

| 変数 | 形式 | 説明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | カンマ区切り | 1つの変数に複数のタグ。 |
| `TUIST_BUILD_VALUE_*` | 単一値 | サフィックスがキーとなるキー・バリューペア。 |

### 例

ビルドを呼び出す前に、CIまたはシェルでこれらの値を設定してください：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
