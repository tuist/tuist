---
title: 新規プロジェクトの作成
titleTemplate: :title · Adoption · Projects · Develop · Guides · Tuist
description: Tuist で新規プロジェクトを作成する方法を学びます。
---

# 新規プロジェクトの作成 {#create-a-new-project}

Tuist を使って新しいプロジェクトを開始する最も簡単な方法は、`tuist init` コマンドを使用することです。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。 このコマンドは、デフォルトの構造と設定を持つ新しいプロジェクトを生成します。

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

> [!NOTE]
> We intentionally keep the list of available templates short to minimize maintenance overhead. If you want to create a project that doesn't represent an application, for example a framework, you can use `tuist init` as a starting point and then modify the generated project to suit your needs.

## Manually creating a project {#manually-creating-a-project}

Alternatively, you can create the project manually. We recommend doing this only if you're already familiar with Tuist and its concepts. The first thing that you'll need to do is to create additional directories for the project structure:

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

> [!IMPORTANT]
> Tuist uses the `Tuist/` directory to determine the root of your project, and from there it looks for other manifest files globbing the directories. We recommend creating those files with your editor of choice, and from that point on, you can use `tuist edit` to edit the project with Xcode.
