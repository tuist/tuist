---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# コード共有{#code-sharing}

Xcodeを大規模なプロジェクトで使用する際に不便な点の一つは、`.xcconfig`
ファイルを通して、ビルド設定以外のプロジェクトの要素を再利用できないことです。プロジェクト定義を再利用できることは、以下の理由で便利です：

- 一箇所で変更が適用され、すべてのプロジェクトに変更が自動的に反映されるため、**** のメンテナンスが容易になる。
- これにより、新しいプロジェクトが準拠できる**規約** を定義することが可能になる。
- プロジェクトはより**** 一貫しているため、不整合によるビルドの破損の可能性は著しく低い。
- 既存のロジックを再利用できるので、新しいプロジェクトを追加するのは簡単な作業になる。

**プロジェクト記述ヘルパー** のコンセプトのおかげで、マニフェストファイル間でのコードの再利用がTuistでは可能です。

::: tip A TUIST UNIQUE ASSET
<!-- -->
多くの組織がTuistを気に入っているのは、プロジェクト記述ヘルパーに、プラットフォームチームが自分たちの規約を成文化し、自分たちのプロジェクトを記述するための独自の言語を考え出すためのプラットフォームを見出すからである。例えば、YAMLベースのプロジェクトジェネレータは、YAMLベースの独自のテンプレートソリューションを考え出さなければならない。
<!-- -->
:::

## プロジェクト説明ヘルパー{#project-description-helpers}

プロジェクト記述ヘルパーは、マニフェストファイルがインポートできるモジュール`ProjectDescriptionHelpers` にコンパイルされる
Swift ファイルです。モジュールは、`Tuist/ProjectDescriptionHelpers`
ディレクトリにあるすべてのファイルを集めることによってコンパイルされます。

ファイルの先頭に import ステートメントを追加することで、それらをマニフェストファイルにインポートすることができます：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` は以下のマニフェストで利用できます：
- `プロジェクト.swift`
- `Package.swift` (`#TUIST` コンパイラフラグの後ろのみ)
- `ワークスペース.swift`

## 例{#example}

以下のスニペットには、`Project` モデルを拡張して静的コンストラクタを追加する方法と、`Project.swift`
ファイルからそれらを使用する方法の例が含まれています：

コードグループ
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

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
この関数を通して、ターゲットの名前、バンドル識別子、フォルダー構造に関する規約を定義していることに注目してほしい。
<!-- -->
:::
