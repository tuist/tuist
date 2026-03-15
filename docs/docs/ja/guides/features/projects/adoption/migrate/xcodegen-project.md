---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGenプロジェクトの移行{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)は、Xcodeプロジェクトを定義するための[設定形式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)としてYAMLを使用するプロジェクト生成ツールです。多くの組織が**、Xcodeプロジェクトでの作業時に頻繁に発生するGitのコンフリクトから逃れるためにこれを採用しました。**
しかし、頻繁なGitのコンフリクトは、組織が直面する多くの問題のほんの一部に過ぎません。Xcodeは、大規模なプロジェクトの維持や最適化を困難にする、多くの複雑な仕組みや暗黙の設定を開発者に課しています。
XcodeGenは、Xcodeプロジェクトを生成するツールであり、プロジェクト管理ツールではないため、設計上、この点では不十分です。Xcodeプロジェクトの生成以上の支援が必要な場合は、Tuistの導入を検討するとよいでしょう。

::: tip SWIFT OVER YAML
<!-- -->
多くの組織がプロジェクト生成ツールとしてTuistを好んで採用している理由の一つは、設定形式としてSwiftを採用している点にあります。Swiftは開発者にとって馴染み深いプログラミング言語であり、Xcodeのオートコンプリート、型チェック、検証機能を利用できる利便性を提供します。
<!-- -->
:::

以下は、XcodeGenからTuistへプロジェクトを移行する際の注意事項とガイドラインです。

## プロジェクトの生成{#project-generation}

TuistとXcodeGenの両方とも、プロジェクト宣言をXcodeのプロジェクトおよびワークスペースに変換する`generate` コマンドを提供しています。

コードグループ

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

その違いは編集体験にあります。Tuist を使えば、``tuist edit` ` というコマンドを実行することで、その場で Xcode
プロジェクトを生成し、すぐに開いて作業を開始できます。これは、プロジェクトに素早く変更を加えたい場合に特に便利です。

## `project.yaml` {#projectyaml}

XcodeGenの`プロジェクト.yaml` 記述ファイルは、`プロジェクト.swift` となります。さらに、`ワークスペース.swift`
を作成することで、ワークスペース内でのプロジェクトのグループ化方法をカスタマイズできます。また、他のプロジェクトのターゲットを参照するターゲットを持つプロジェクト`プロジェクト.swift`
を作成することも可能です。そのような場合、Tuistはすべてのプロジェクトを含むXcodeワークスペースを生成します。

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
XcodeGenもTuistも、Xcodeの言語と概念を採用しています。しかし、TuistのSwiftベースの設定では、Xcodeのオートコンプリート、型チェック、および検証機能を利用できるという利点があります。
<!-- -->
:::

## 仕様テンプレート{#spec-templates}

プロジェクト設定言語としてのYAMLの欠点の一つは、デフォルトではYAMLファイル間の再利用性をサポートしていないことです。
これはプロジェクトを記述する際によくあるニーズであり、XcodeGenは* の「テンプレート」*
という独自のソリューションでこの問題を解決する必要がありました。Tuistでは、再利用性が言語そのものであるSwiftに組み込まれており、<LocalizedLink href="/guides/features/projects/code-sharing">project
description
helpers</LocalizedLink>というSwiftモジュールを通じて、すべてのマニフェストファイル間でコードを再利用できるようになっています。

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
