---
{
  "title": "XcodeGen プロジェクトの移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "プロジェクトを XcodeGen から Tuist に移行する方法を学びます。"
}
---
# XcodeGen プロジェクトの移行 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) は、YAML を [設定フォーマット](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) として使用して Xcode プロジェクトを定義するプロジェクト生成ツールです。多くの組織は、**Xcode プロジェクトの作業中に頻繁に発生する Git の競合を回避しようとして、これを採用しました。** しかし、頻繁な Git の競合は、組織が直面する多くの問題のうちの一つにすぎません。Xcode は開発者に多くの複雑さと暗黙的な設定をさらし、大規模なプロジェクトの維持と最適化を困難にします。XcodeGen は Xcode プロジェクトを生成するツールであり、プロジェクトマネージャーではないため、この点では設計上限界があります。Xcode プロジェクトの生成を超えて支援してくれるツールが必要な場合は、Tuist を検討してみてください。

> [!TIP]
> **YAML より Swift**
>
> 多くの組織は、Tuist をプロジェクト生成ツールとしても好んでいます。これは、設定フォーマットとして Swift を使用しているためです。Swift は開発者になじみのあるプログラミング言語であり、Xcode の自動補完、型チェック、および検証機能を利用できる利便性を提供します。


以下では、XcodeGen から Tuist へプロジェクトを移行するための考慮事項とガイドラインを紹介します。

## プロジェクト生成 {#project-generation}

Tuist と XcodeGen の両方は、プロジェクト宣言を Xcode プロジェクトとワークスペースに変換する `generate` コマンドを提供します。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

違いは編集体験にあります。Tuist では、`tuist edit` コマンドを実行すると、その場で Xcode プロジェクトが生成され、開いて作業を開始できます。これは、プロジェクトに素早く変更を加えたい場合に特に便利です。

## `project.yaml` {#projectyaml}

XcodeGen の `project.yaml` 記述ファイルは `Project.swift` になります。さらに、`Workspace.swift` を使用して、プロジェクトをワークスペースでどのようにグループ化するかをカスタマイズできます。また、他のプロジェクトのターゲットを参照するターゲットを持つプロジェクト `Project.swift` を作成することもできます。そのような場合、Tuist はすべてのプロジェクトを含む Xcode ワークスペースを生成します。

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
> XcodeGen と Tuist の両方は、Xcode の言語と概念を取り入れています。ただし、Tuist の Swift ベースの設定により、Xcode の自動補完、型チェック、および検証機能を利用する利便性が得られます。


## 仕様のテンプレート {#spec-templates}

プロジェクト設定の言語としての YAML の欠点の一つは、すぐに YAML ファイル間での再利用をサポートしていないことです。これはプロジェクトを記述する際の一般的なニーズであり、XcodeGen は独自の独自ソリューションである *「テンプレート」* でこれを解決する必要がありました。Tuist では、再利用性は言語自体である Swift に組み込まれており、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> という Swift モジュールを通じて、すべてのマニフェストファイル間でコードを再利用できます。

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
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
