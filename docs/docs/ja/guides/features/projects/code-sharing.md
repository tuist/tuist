---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# コード共有{#code-sharing}

大規模プロジェクトでXcodeを使用する際の不便な点の一つは、`.xcconfig`
ファイルを通じて、ビルド設定以外のプロジェクト要素を再利用できないことです。プロジェクト定義を再利用できることは、以下の理由から有用です：

- **のメンテナンスを容易にします。** 変更は一箇所で適用でき、すべてのプロジェクトが自動的に変更を取得するためです。
- これにより、新規プロジェクトが準拠できる**規約** を定義することが可能になります。
- プロジェクトはより一貫性が高くなります**consistent** そのため、不整合によるビルド失敗の可能性が大幅に低減されます。
- 既存のロジックを再利用できるため、新規プロジェクトの追加は容易な作業となります。

Tuistでは、**プロジェクト説明ヘルパー** の概念により、マニフェストファイル間でコードを再利用できます。

::: tip A TUIST UNIQUE ASSET
<!-- -->
多くの組織がTuistを好む理由は、プロジェクト説明ヘルパーをプラットフォームチームが独自の規約を体系化し、プロジェクト記述のための独自言語を構築する基盤と見なしているからです。例えば、YAMLベースのプロジェクト生成ツールは、独自のYAMLベースの独自テンプレートソリューションを開発するか、組織にそのツールを基盤とした構築を強制しなければなりません。
<!-- -->
:::

## プロジェクト説明ヘルパー{#project-description-helpers}

プロジェクト記述ヘルパーはSwiftファイルであり、`ProjectDescriptionHelpers`
というモジュールにコンパイルされ、マニフェストファイルがインポートできます。このモジュールは、`Tuist/ProjectDescriptionHelpers`
ディレクトリ内の全ファイルを集めてコンパイルされます。

ファイルの先頭にインポート文を追加することで、マニフェストファイルにインポートできます:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` は以下のマニフェストで利用可能です:
- `Project.swift`
- `Package.swift` (`#TUIST` コンパイラフラグが有効な場合のみ)
- `Workspace.swift`

## 例{#example}

以下のスニペットは、`プロジェクトの`
モデルを拡張して静的コンストラクタを追加する方法と、`プロジェクトのProject.swiftファイルからそれらを使用する方法を示す例です。`

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
関数を通じて、ターゲット名、バンドル識別子、フォルダ構造に関する規約を定義している点に注意してください。
<!-- -->
:::
