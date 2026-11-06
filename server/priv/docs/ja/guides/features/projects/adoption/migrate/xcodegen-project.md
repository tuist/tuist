---
{
  "title": "XcodeGen プロジェクトの移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "XcodeGen から Tuist へプロジェクトを移行する方法を学びます。"
}
---
# XcodeGen プロジェクトの移行 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) は、YAML を [設定フォーマット](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) として使用して Xcode プロジェクトを定義するプロジェクト生成ツールです。多くの組織は、**Xcode プロジェクトの作業中に頻繁に発生する Git の競合を避けるためにこれを採用しました。** しかし、頻繁な Git の競合は、組織が直面する数ある問題のひとつにすぎません。Xcode は開発者に多くの複雑さと暗黙的な設定を露呈させ、大規模なプロジェクトの維持と最適化を困難にします。XcodeGen は Xcode プロジェクトを生成するツールであり、プロジェクトマネージャーではないため、設計上この点では不十分です。Xcode プロジェクトの生成を超えて支援するツールが必要な場合は、Tuist の検討をおすすめします。

> [!TIP]
> **YAML より Swift**
>
> 多くの組織が Tuist をプロジェクト生成ツールとしても好むのは、設定フォーマットとして Swift を使用しているためです。Swift は開発者になじみのあるプログラミング言語であり、Xcode の自動補完、型チェック、検証機能を利用できる利便性を提供します。


以下では、XcodeGen から Tuist へプロジェクトを移行するための考慮事項とガイドラインを紹介します。

## プロジェクト生成 {#project-generation}

Tuist と XcodeGen のどちらも、プロジェクト宣言を Xcode プロジェクトとワークスペースに変換する `generate` コマンドを提供します。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

違いは編集体験にあります。Tuist では `tuist edit` コマンドを実行でき、その場で Xcode プロジェクトを生成して開き、作業を開始できます。プロジェクトに迅速な変更を加えたい場合に特に便利です。

## `project.yaml` {#projectyaml}

XcodeGen の `project.yaml` 記述ファイルは `Project.swift` になります。さらに、プロジェクトをワークスペース内でどのようにグループ化するかをカスタマイズする方法として `Workspace.swift` を用意できます。また、他のプロジェクトのターゲットを参照するターゲットを含むプロジェクト `Project.swift` を作成することもできます。その場合、Tuist はすべてのプロジェクトを含む Xcode ワークスペースを生成します。

::: code-group

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

> [!TIP]
> **Xcode の言語**
>
> XcodeGen と Tuist のどちらも、Xcode の言語と概念を取り入れています。ただし、Tuist の Swift ベースの設定では、Xcode の自動補完、型チェック、検証機能を利用できる利便性が得られます。


## 仕様テンプレート {#spec-templates}

プロジェクト設定の言語として YAML を使用する欠点のひとつは、YAML ファイル間での再利用を开箱即用でサポートしていないことです。これはプロジェクトを記述する際の一般的なニーズであり、XcodeGen は独自の独自ソリューションである *「テンプレート」* でこれに対処していました。Tuist では、再利用機能が言語自体である Swift に組み込まれており、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> という Swift モジュールを通じて、すべてのマニフェストファイル間でコードを再利用できます。

::: code-group
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
import ProjectDescriptionHelpers

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature"))
```
:::
