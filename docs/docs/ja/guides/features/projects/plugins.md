---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# プラグイン{#plugins}

プラグインは、複数のプロジェクト間でTuistアーティファクトを共有・再利用するためのツールです。以下のアーティファクトがサポートされています：

- <LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト説明ヘルパー</LocalizedLink>を複数プロジェクトにまたがって使用します。
- <LocalizedLink href="/guides/features/projects/templates">複数プロジェクトにまたがるテンプレート</LocalizedLink>。
- 複数プロジェクトにまたがるタスク。
- <LocalizedLink href="/guides/features/projects/synthesized-files">リソースアクセサ</LocalizedLink>テンプレートを複数プロジェクトにまたがって使用

プラグインはTuistの機能を拡張する簡便な手段として設計されています。そのため、**いくつかの制限事項を考慮する必要があります。詳細は** をご参照ください。

- プラグインは他のプラグインに依存できません。
- プラグインはサードパーティのSwiftパッケージに依存してはならない
- プラグインは、そのプラグインを使用しているプロジェクトのプロジェクト説明ヘルパーを使用できません。

より柔軟な対応が必要な場合は、ツールへの機能追加を提案するか、Tuistの生成フレームワーク[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)を基に独自ソリューションを構築することを検討してください。

## プラグインの種類{#plugin-types}

### プロジェクト説明ヘルパープラグイン{#project-description-helper-plugin}

プロジェクト説明ヘルパープラグインは、以下のディレクトリで構成されます：`Plugin.swift`
（プラグイン名を宣言するマニフェストファイル）`ProjectDescriptionHelpers` （ヘルパーSwiftファイルを含むディレクトリ）

コードグループ
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### リソースアクセサテンプレートプラグイン{#resource-accessor-templates-plugin}

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成リソースアクセサ</LocalizedLink>を共有する必要がある場合、このタイプのプラグインを使用できます。プラグインは、以下のディレクトリで構成されます：`Plugin.swift`
プラグイン名を宣言するマニフェストファイル`ResourceSynthesizers` リソースアクセサのテンプレートファイルを含むディレクトリ


コードグループ
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

テンプレートの名前は、リソースタイプの[キャメルケース](https://en.wikipedia.org/wiki/Camel_case)表記です：

| リソースタイプ           | テンプレートファイル名              |
| ----------------- | ------------------------ |
| 文字列               | Strings.stencil          |
| アセット              | Assets.stencil           |
| プロパティリスト          | Plists.stencil           |
| フォント              | Fonts.stencil            |
| Core Data         | CoreData.stencil         |
| Interface Builder | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

プロジェクトでリソースシンセサイザーを定義する際、プラグインのテンプレートを使用するにはプラグイン名を指定できます:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### タスクプラグイン <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
タスクプラグインは非推奨です。プロジェクトの自動化ソリューションをお探しの方は、[こちらのブログ記事](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)をご確認ください。
<!-- -->
:::

`` `` `` `` タスクは`$PATH`-exposed 実行可能ファイルであり、命名規則`tuist-<task-name>`
に従う場合、`tuist` コマンドで呼び出せます。以前のバージョンでは、Tuist は`tuist plugin` tuist plugin tuist
plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist
plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist
plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist
plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist
plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist plugin tuist
plugin tuist plugin tuist</task-name>

タスク配布にTuistを利用していた場合、構築をお勧めします
- Tuistの全リリースに同梱されている`ProjectAutomation.xcframework`
  を使用し続けることで、ロジックからプロジェクトグラフにアクセスできます。`let graph = try Tuist.graph()`
  。このコマンドはシステムプロセスを利用して`tuist` コマンドを実行し、プロジェクトグラフのメモリ内表現を返します。
- タスクを分散させるには、GitHubリリースに`arm64` および`x86_64`
  に対応したファットバイナリを含め、インストールツールとして[Mise](https://mise.jdx.dev)を使用することを推奨します。Miseにツールのインストール方法を指示するには、プラグインリポジトリが必要です。[Tuist's](https://github.com/asdf-community/asdf-tuist)を参考として使用できます。
- ツール名を`tuist-{xxx}` と命名し、ユーザーが`mise install`
  を実行してインストールできる場合、ユーザーは直接呼び出すか、または`tuist xxx` を通じて実行できます。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`の ProjectAutomation` と`の XcodeGraph`
のモデルを統合し、プロジェクトグラフ全体をユーザーに公開する単一の互換性のあるフレームワークを構築する予定です。さらに、生成ロジックを新しいレイヤー`XcodeGraph`
に抽出し、独自の CLI からも利用可能にします。これは独自の Tuist を構築するものと捉えてください。
<!-- -->
:::

## プラグインの使用{#using-plugins}

プラグインを使用するには、プロジェクトの<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
マニフェストファイルに追加する必要があります：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

`異なるリポジトリにあるプロジェクト間でプラグインを再利用したい場合、プラグインをGitリポジトリにプッシュし、`Tuist.swift`（``
`）ファイル内で参照できます：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

プラグイン追加後、``` または `tuist install` ` を実行すると、プラグインがグローバルキャッシュディレクトリに取得されます。

::: info NO VERSION RESOLUTION
<!-- -->
ご存知かもしれませんが、プラグインのバージョン解決は提供しておりません。再現性を確保するため、GitタグまたはSHAの使用をお勧めします。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
プロジェクト説明ヘルパープラグインを使用する場合、ヘルパーを含むモジュールの名前がプラグイン名となります
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
