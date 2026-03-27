---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGenプロジェクトの移行{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)は、Xcodeプロジェクトを定義するための[設定フォーマット](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)としてYAMLを使用するプロジェクト生成ツールです。多くの組織は、**、Xcodeプロジェクトで作業するときに発生する頻繁なGitの衝突から逃れようとして、これを採用しました。**
しかし、頻繁なGitの衝突は、組織が経験する多くの問題の一つに過ぎません。Xcodeは、開発者に多くの複雑さと暗黙的なコンフィギュレーションを提供し、大規模なプロジェクトを維持し最適化することを難しくしている。XcodeGenは、プロジェクトマネージャではなく、Xcodeプロジェクトを生成するツールであるため、設計上、そこでは不十分である。Xcodeプロジェクトを生成する以上のツールが必要な場合は、Tuistを検討するとよいだろう。

::: tip SWIFT OVER YAML
<!-- -->
多くの組織がプロジェクト生成ツールとしてもTuistを好むのは、Swiftを構成フォーマットとして使用しているからだ。Swiftは、開発者が慣れ親しんでいるプログラミング言語であり、Xcodeのオートコンプリート、タイプチェック、検証機能を使用する利便性を提供する。
<!-- -->
:::

以下は、XcodeGenからTuistへプロジェクトを移行する際に役立ついくつかの考慮事項とガイドラインです。

## プロジェクト・ジェネレーション{#project-generation}

TuistもXcodeGenも、`generate` コマンドを提供し、プロジェクト宣言をXcodeプロジェクトとワークスペースに変換します。

コードグループ

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

違いは、編集体験にある。Tuistでは、`tuist edit`
コマンドを実行すると、Xcodeプロジェクトがその場で生成され、それを開いて作業を始めることができる。これは、プロジェクトに素早く変更を加えたいときに特に便利です。

## `project.yaml` {#projectyaml}

XcodeGen の`project.yaml` 記述ファイルは、`Project.swift`
になります。さらに、ワークスペースでプロジェクトをグループ化する方法をカスタマイズする方法として、`Workspace.swift`
を持つことができます。また、他のプロジェクトのターゲットを参照するターゲットを持つプロジェクト`Project.swift`
を持つこともできます。このような場合、Tuistはすべてのプロジェクトを含むXcode Workspaceを生成します。

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
XcodeGenとTuistの両方がXcodeの言語とコンセプトを受け入れている。しかし、TuistのSwiftベースのコンフィギュレーションは、Xcodeのオートコンプリート、タイプチェック、検証機能を使用する利便性を提供します。
<!-- -->
:::

## 仕様テンプレート{#spec-templates}

プロジェクト設定のための言語としてのYAMLの欠点の1つは、YAMLファイル間での再利用性をサポートしていないことです。これはプロジェクトを記述するときの共通のニーズであり、XcodeGen
は*"templates"*
という独自のソリューションで解決しなければなりませんでした。Tuistの再利用性は言語そのものであるSwiftに組み込まれており、<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>というSwiftモジュールを通して、すべてのマニフェストファイルにわたってコードを再利用することができます。

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
