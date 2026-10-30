---
{
  "title": "コード共有",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "マニフェストファイル間でコードを共有して重複を減らし、一貫性を確保する方法を学ぶ"
}
---
# コード共有 {#code-sharing}

大規模プロジェクトで Xcode を使用する際の問題点の 1 つは、ビルド設定を `.xcconfig` ファイル経由で再利用すること以外に、プロジェクト要素の再利用が許されていないことです。プロジェクト定義を再利用できることは、以下の理由で役立ちます。

- 変更を一箇所で適用でき、すべてのプロジェクトに自動的に反映されるため、**メンテナンス** が容易になります。
- 新しいプロジェクトが準拠できる**規約**を定義できます。
- プロジェクトの**一貫性**が高まり、不整合によるビルドエラーの可能性が大幅に減少します。
- 既存のロジックを再利用できるため、新しいプロジェクトの追加が簡単になります。

Tuist では、**プロジェクト記述ヘルパー**という概念により、マニフェストファイル間でコードを再利用できます。

> [!TIP]
> **Tuist の独自の強み**
>
> 多くの組織が Tuist を好むのは、プロジェクト記述ヘルパーをプラットフォームチームが独自の規約をコード化し、プロジェクトを記述するための独自言語を生み出すためのプラットフォームとして捉えているためです。例えば、YAML ベースのプロジェクトジェネレーターは、独自の YAML ベースの独自テンプレートソリューションを用意するか、組織にそのツールの上に構築することを強いる必要があります。


## プロジェクト記述ヘルパー {#project-description-helpers}

プロジェクト記述ヘルパーは Swift ファイルで、マニフェストファイルがインポートできる `ProjectDescriptionHelpers` モジュールにコンパイルされます。このモジュールは、`Tuist/ProjectDescriptionHelpers` ディレクトリ内のすべてのファイルを集めてコンパイルされます。

ファイルの先頭に import 文を追加することで、マニフェストファイルにインポートできます。

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` は以下のマニフェストで使用できます。
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
> 関数を通じて、ターゲット名、バンドル識別子、フォルダ構造に関する規約を定義している点に注目してください。
