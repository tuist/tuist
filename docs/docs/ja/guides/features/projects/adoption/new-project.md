---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 新しいプロジェクトを作成する {#create-a-new-project}。

Tuistで新しいプロジェクトを始める最も簡単な方法は、`tuist init`
コマンドを使うことである。このコマンドは対話型CLIを起動し、プロジェクトのセットアップをガイドする。プロンプトが表示されたら、必ず "generated
project "を作成するオプションを選択してください。

プロジェクトを編集する`tuist edit` を実行すると、Xcodeがプロジェクトを開き、そこでプロジェ
クトを編集することができます。生成されるファイルの一つは、`Project.swift` で、プロジェクトの定義を含んでいます。Swift
のパッケージマネージャに慣れているなら、`Package.swift` のように、しかし Xcode プロジェクトの専門用語で考えてください。

コードグループ
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

::: info
<!-- -->
メンテナンスのオーバーヘッドを最小限にするため、利用可能なテンプレートのリストは意図的に短くしています。アプリケーションを表さないプロジェクト、たとえばフレームワークを作りたい場合、`tuist
init` を出発点として使い、生成されたプロジェクトをあなたのニーズに合うように修正することができます。
<!-- -->
:::

## プロジェクトの手動作成{#manually-creating-a-project}。

あるいは、手動でプロジェクトを作成することもできます。Tuistとその概念にすでに精通している場合のみ、この方法をお勧めします。最初に必要なことは、プロジェクト構造用に追加のディレクトリを作成することです：

```bash
mkdir MyFramework
cd MyFramework
```

次に、`Tuist.swift`
ファイルを作成します。これはTuistを設定し、Tuistがプロジェクトのルート・ディレクトリを決定するために使用します。また、`Project.swift`
を作成します。ここにはプロジェクトが宣言されます：

コードグループ
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

::: 警告
<!-- -->
Tuistは、`Tuist/`
ディレクトリを使用してプロジェクトのルートを決定し、そこからディレクトリをグロビングする他のマニフェストファイルを探します。これらのファイルはお好みのエディタで作成することをお勧めします。その時点から、`tuist
edit` 、Xcodeでプロジェクトを編集することができます。
<!-- -->
:::
