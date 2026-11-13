---
{
  "title": "コード共有",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "マニフェストファイル間でコードを共有して重複を減らし、一貫性を確保する方法を学びます"
}
---
# コードの共有 {#code-sharing}

大規模なプロジェクトで Xcode を使用する際の問題点の一つは、ビルド設定以外にプロジェクト要素を `.xcconfig` ファイルを通じて再利用できないことです。プロジェクト定義を再利用できることは、以下の理由で有用です。

- 変更を一箇所で適用でき、すべてのプロジェクトに自動的に反映されるため、**メンテナンス** が容易になります。
- 新しいプロジェクトが準拠できる**規約**を定義できます。
- プロジェクト間の**一貫性**が高まり、不整合によるビルドエラーの可能性が大幅に減少します。
- 既存のロジックを再利用できるため、新しいプロジェクトの追加が簡単になります。

Tuist では、**プロジェクト記述ヘルパー**という概念により、マニフェストファイル間でコードを再利用できます。

> [!TIP]
> **Tuist 独自の強み**
>
> 多くの組織が Tuist を支持するのは、プロジェクト記述ヘルパーによってプラットフォームチームが独自の規約をコード化し、プロジェクトを記述するための独自言語を構築できるプラットフォームと見なしているためです。例えば、YAML ベースのプロジェクトジェネレーターは、独自の YAML ベースのテンプレートソリューションを開発するか、あるいは組織にそのツールの上に自前の仕組みを構築させる必要があります。


## プロジェクト記述ヘルパー {#project-description-helpers}

プロジェクト記述ヘルパーは Swift ファイルであり、マニフェストファイルからインポート可能な `ProjectDescriptionHelpers` モジュールにコンパイルされます。このモジュールは、`Tuist/ProjectDescriptionHelpers` ディレクトリ内のすべてのファイルを集めてコンパイルされます。

ファイルの先頭に import 文を追加することで、マニフェストファイルにインポートできます。

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` は以下のマニフェストで使用可能です。
- `Project.swift`
- `Package.swift`（`#TUIST` コンパイラフラグが必要）
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
> 関数を通じて、ターゲット名、バンドル識別子、フォルダ構造に関する規約を定義している点に注目してください。
