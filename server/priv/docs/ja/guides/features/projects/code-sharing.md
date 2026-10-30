---
{
  "title": "コード共有",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "マニフェストファイル間でコードを共有し、重複を減らして一貫性を確保する方法を学びます"
}
---
# コード共有 {#code-sharing}

大規模なプロジェクトで Xcode を使用する際の問題点の 1 つは、`.xcconfig` ファイルによるビルド設定以外では、プロジェクトの要素を再利用できないことです。プロジェクト定義を再利用できることは、以下の理由で有用です。

- 変更を 1 か所に適用するとすべてのプロジェクトに自動的に反映されるため、**メンテナンス** が容易になります。
- 新しいプロジェクトが準拠できる**規約**を定義できます。
- プロジェクトはより**一貫性**が保たれ、その結果、不整合によるビルドエラーの可能性が大幅に低減します。
- 既存のロジックを再利用できるため、新しいプロジェクトの追加が簡単になります。

Tuist では、**project description helpers** の概念により、マニフェストファイル間でコードを再利用できます。

> [!TIP]
> **Tuist 独自の強み**
>
> 多くの組織が Tuist を採用しているのは、project description helpers をプラットフォームチームが独自の規約をコード化し、プロジェクトを記述するための独自の言語を生み出すためのプラットフォームとして捉えているためです。たとえば、YAML ベースのプロジェクトジェネレーターは、独自の YAML ベースの独自テンプレートソリューションを用意するか、組織にそのツールの上で構築することを強いる必要があります。


## Project description helpers {#project-description-helpers}

Project description helpers は、マニフェストファイルがインポートできるモジュール `ProjectDescriptionHelpers` にコンパイルされる Swift ファイルです。このモジュールは、`Tuist/ProjectDescriptionHelpers` ディレクトリ内のすべてのファイルを集めてコンパイルされます。

ファイルの先頭に import 文を追加することで、マニフェストファイルにインポートできます。

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` は以下のマニフェストで利用可能です。
- `Project.swift`
- `Package.swift`（`#TUIST` コンパイラフラグを使用した場合のみ）
- `Workspace.swift`

## 例 {#example}

以下のスニペットは、`Project` モデルを拡張して静的コンストラクタを追加し、それを `Project.swift` ファイルから使用する方法の例です。

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

> [!TIP]
> **規約を確立するためのツール**
>
> 関数を通じて、ターゲット名、バンドル識別子、フォルダー構造に関する規約を定義している点に注目してください。
