---
{
  "title": "新しいプロジェクトの作成",
  "titleTemplate": ":title · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist で新しいプロジェクトを作成する方法を学びます。"
}
---
# 新しいプロジェクトの作成 {#create-a-new-project}

Tuist で新しいプロジェクトを始める最も簡単な方法は、`tuist init` コマンドを使用することです。このコマンドはインタラクティブな CLI を起動し、プロジェクトの設定手順を案内します。プロンプトが表示されたら、「generated project」を作成するオプションを選択してください。

その後、`tuist edit` を実行して <.localized_link href="/guides/features/projects/editing">プロジェクトを編集</.localized_link> すると、Xcode が開き、プロジェクトを編集できます。生成されるファイルの一つに `Project.swift` があり、これにはプロジェクトの定義が含まれています。Swift Package Manager に慣れている方は、これを Xcode プロジェクトの用語で記述された `Package.swift` と考えてください。

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
> メンテナンス負荷を最小限に抑えるため、利用可能なテンプレートのリストは意図的に短くしています。アプリケーションではなくフレームワークなどを作成したい場合は、`tuist init` を出発点として使用し、生成されたプロジェクトをニーズに合わせて修正できます。


## プロジェクトの手動作成 {#manually-creating-a-project}

あるいは、プロジェクトを手動で作成することもできます。これは Tuist とその概念にすでに慣れている場合にのみ推奨します。最初に行うべきことは、プロジェクト構造のために追加のディレクトリを作成することです。

```bash
mkdir MyFramework
cd MyFramework
```

次に、Tuist を構成し、プロジェクトのルートディレクトリを決定するために Tuist が使用する `Tuist.swift` ファイルと、プロジェクトが宣言される `Project.swift` を作成します。

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
> Tuist は `Tuist/` ディレクトリを使用してプロジェクトのルートを特定し、そこからディレクトリを glob パターンで検索して他のマニフェストファイルを探します。これらのファイルはお好みのエディタで作成し、その後は `tuist edit` を使用して Xcode でプロジェクトを編集できます。
