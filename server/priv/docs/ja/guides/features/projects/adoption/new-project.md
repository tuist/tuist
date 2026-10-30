---
{
  "title": "新しいプロジェクトを作成する",
  "titleTemplate": ":title · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist で新しいプロジェクトを作成する方法を学びます。"
}
---
# 新しいプロジェクトを作成する {#create-a-new-project}

Tuist で新しいプロジェクトを始める最も簡単な方法は、`tuist init` コマンドを使用することです。このコマンドはインタラクティブな CLI を起動し、プロジェクトのセットアップを案内します。プロンプトが表示されたら、「generated project」を作成するオプションを選択してください。

その後、`tuist edit` を実行して <.localized_link href="/guides/features/projects/editing">プロジェクトを編集</.localized_link> でき、Xcode が開いてプロジェクトを編集できます。生成されるファイルの一つに `Project.swift` があり、これがプロジェクトの定義を含みます。Swift Package Manager に慣れている方は、これを Xcode プロジェクトの用語で書かれた `Package.swift` と考えてください。

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> メンテナンス負荷を最小限に抑えるため、利用可能なテンプレートの一覧は意図的に短くしています。アプリケーション以外のプロジェクト（フレームワークなど）を作成したい場合は、`tuist init` を出発点として使用し、生成されたプロジェクトを必要に応じて変更できます。


## プロジェクトを手動で作成する {#manually-creating-a-project}

alternatively、プロジェクトを手動で作成することもできます。これは Tuist とその概念にすでに慣れている場合にのみ推奨します。最初に行う必要があるのは、プロジェクト構造のための追加ディレクトリを作成することです：

```bash
mkdir MyFramework
cd MyFramework
```

次に、Tuist を構成し、プロジェクトのルートディレクトリを決定するために Tuist が使用する `Tuist.swift` ファイルと、プロジェクトが宣言される `Project.swift` を作成します：

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

> [!WARNING]
> Tuist は `Tuist/` ディレクトリを使用してプロジェクトのルートを決定し、そこからディレクトリをグロブして他のマニフェストファイルを探します。これらのファイルはお好みのエディタで作成することを推奨し、その後は `tuist edit` を使用して Xcode でプロジェクトを編集できます。
