---
title: 新規プロジェクトの作成
titleTemplate: :title · Adoption · Projects · Develop · Guides · Tuist
description: Tuist で新規プロジェクトを作成する方法を学びます。
---

# 新規プロジェクトの作成 {#create-a-new-project}

Tuist を使って新しいプロジェクトを開始する最も簡単な方法は、`tuist init` コマンドを使用することです。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。

## アプリケーションプロジェクトの初期化 {#initializing-an-application-project}

開始するには、プロジェクトを作成するディレクトリを作成する必要があります:

```bash
mkdir MyApp
cd MyApp
```

ディレクトリが作成され、その中に入ったら、次のコマンドを実行します:

::: code-group

```bash [iOS project]
tuist init --platform ios
```

```bash [macOS project]
tuist init --platform macos
```

:::

コマンドは現在のディレクトリ内のプロジェクトを初期化します。 コマンドは現在のディレクトリ内のプロジェクトを初期化します。 プロジェクトを編集するには、`tuist edit` を実行します。そうすると、Xcode がプロジェクトを開き、<0>編集できる</0>ようになります。 生成されるファイルの1つは `Project.swift` で、プロジェクトの定義が含まれています。 Swift Package Manager に馴染みがある方は、Xcode プロジェクト向けの `Package.swift` のようなものだと考えてください。 生成されるファイルの1つは `Project.swift` で、プロジェクトの定義が含まれています。 Swift Package Manager に馴染みがある方は、Xcode プロジェクト向けの `Package.swift` のようなものだと考えてください。

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
            bundleId: "io.tuist.MyApp",
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
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

:::

> メンテナンスの負荷を最小限に抑えるため、利用可能なテンプレートのリストはあえて最小限にしています。 フレームワークなど、アプリケーションを表すものではないプロジェクトを作成する場合。 `tuist init` を出発点として使用し、生成されたプロジェクトを必要に応じて変更できます。

## プロジェクトを手動で作成する {#manually-creating-a-project}

あるいは、手動でプロジェクトを作成することも可能です。 Tuist とその概念をすでに知っている場合にのみ、これを行うことをお勧めします。 最初に行う必要があるのは、プロジェクト構造に追加のディレクトリを作成することです。

```bash
mkdir MyFramework
cd MyFramework
```

次に、Tuist の設定を行い、プロジェクトのルートディレクトリを判定するために Tuist が使用する `Tuist.swift` ファイルと、プロジェクトの内容を宣言する `Project.swift` ファイルを作成します。

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
            bundleId: "io.tuist.MyFramework",
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

:::

> Tuist は `Tuist/` ディレクトリを使ってプロジェクトのルートを判定し、そこからディレクトリを探索しながら他のマニフェストファイルを探します。 [!IMPORTANT]
> Tuist は `Tuist/` ディレクトリを使ってプロジェクトのルートを判定し、そこからディレクトリを探索しながら他のマニフェストファイルを探します。 これらのファイルは、お好みのエディタで作成することをおすすめします。その後は `tuist edit` を使って、Xcode でプロジェクトを編集できます。
