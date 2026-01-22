---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGenプロジェクトを移行する{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)は、Xcodeプロジェクトを定義するための[設定フォーマット](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)としてYAMLを使用するプロジェクト生成ツールです。多くの組織が**、Xcodeプロジェクトを扱う際に頻繁に発生するGitの競合から逃れようとこれを採用しました。**
しかし、頻繁なGitの競合は、組織が経験する多くの問題の一つに過ぎません。Xcodeは開発者に多くの複雑さと暗黙的な設定を露呈し、大規模なプロジェクトの維持や最適化を困難にしています。
XcodeGenは設計上、この点で不十分です。なぜなら、これはプロジェクトマネージャーではなく、Xcodeプロジェクトを生成するツールだからです。Xcodeプロジェクトの生成を超えて支援するツールが必要な場合は、Tuistを検討することをお勧めします。

::: tip SWIFT OVER YAML
<!-- -->
多くの組織がプロジェクト生成ツールとしてTuistを好む理由の一つは、設定形式にSwiftを採用している点です。Swiftは開発者に馴染み深いプログラミング言語であり、Xcodeの自動補完・型チェック・検証機能を活用できる利便性を提供します。
<!-- -->
:::

以下は、XcodeGenからTuistへのプロジェクト移行を支援するための考慮事項とガイドラインです。

## プロジェクト生成{#project-generation}

TuistとXcodeGenの両方とも、プロジェクト宣言をXcodeプロジェクトとワークスペースに変換する「`generate` 」コマンドを提供しています。

コードグループ

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

違いは編集体験にあります。Tuistでは、``` tuist edit`
コマンドを実行できます。これにより、その場でXcodeプロジェクトが生成され、開いて作業を開始できます。これは、プロジェクトに素早く変更を加えたい場合に特に便利です。

## `project.yaml` {#projectyaml}

XcodeGenの`プロジェクトの`project.yaml`（` ）記述ファイルは```となり、`Project.swift`（`
）が生成されます。さらに、ワークスペース内のプロジェクトグループ化をカスタマイズする方法として、```と`Workspace.swift`（`
）を定義できます。また、他のプロジェクトのターゲットを参照するターゲットを持つプロジェクト（```と`Project.swift`（`
））も可能です。これらの場合、Tuistは全てのプロジェクトを含むXcodeワークスペースを生成します。

コードグループ

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

::: tip XCODE'S LANGUAGE
<!-- -->
XcodeGenとTuistはどちらもXcodeの言語と概念を採用しています。ただし、TuistのSwiftベースの設定により、Xcodeのオートコンプリート、型チェック、検証機能を利用できる利便性が得られます。
<!-- -->
:::

## 仕様テンプレート{#spec-templates}

プロジェクト設定言語としてのYAMLの欠点の一つは、デフォルトではYAMLファイル間の再利用性をサポートしていないことです。
プロジェクト記述においてこれは一般的なニーズであり、XcodeGenは独自ソリューション「* テンプレート」*
でこれを解決する必要がありました。Tuistでは再利用性が言語そのもの（Swift）に組み込まれており、さらに<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</LocalizedLink>というSwiftモジュールを通じて、すべてのマニフェストファイル間でコードを再利用可能にしています。

コードグループ
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
