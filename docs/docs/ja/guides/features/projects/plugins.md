---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# プラグイン{#plugins}

プラグインは、複数のプロジェクト間でTuistのアートファクトを共有・再利用するためのツールです。以下のアートファクトがサポートされています：

- <LocalizedLink href="/guides/features/projects/code-sharing">複数のプロジェクトにまたがるプロジェクト説明ヘルパー</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">複数のプロジェクトにまたがるテンプレート</LocalizedLink>。
- 複数のプロジェクトにまたがるタスク。
- <LocalizedLink href="/guides/features/projects/synthesized-files">複数のプロジェクトにまたがるリソースアクセサ</LocalizedLink>テンプレート

プラグインは、Tuistの機能を拡張するためのシンプルな手段として設計されています。そのため、**いくつかの制限事項があります。**:

- プラグインは他のプラグインに依存することはできません。
- プラグインはサードパーティ製のSwiftパッケージに依存してはなりません
- プラグインは、そのプラグインを使用しているプロジェクトのプロジェクト説明ヘルパーを使用することはできません。

より柔軟な対応が必要な場合は、ツールの機能追加を提案するか、Tuistの生成フレームワーク
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)
を利用して独自のソリューションを構築することを検討してください。

## プラグインの種類{#plugin-types}

### プロジェクト説明ヘルパープラグイン{#project-description-helper-plugin}

プロジェクト記述ヘルパープラグインは、プラグイン名を宣言する ``Plugin.swift``
マニフェストファイルを含むディレクトリと、ヘルパーのSwiftファイルを含む ``ProjectDescriptionHelpers``
ディレクトリで構成されます。

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

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成リソースアクセサ</LocalizedLink>を共有する必要がある場合は、この種のプラグインを使用できます。このプラグインは、プラグインの名前を宣言する
``Plugin.swift`` マニフェストファイルを含むディレクトリと、リソースアクセサのテンプレートファイルを含む
``ResourceSynthesizers`` ディレクトリで構成されます。


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

テンプレートの名前は、リソースタイプの [キャメルケース](https://en.wikipedia.org/wiki/Camel_case) 表記です：

| リソースの種類           | テンプレートファイル名              |
| ----------------- | ------------------------ |
| 文字列               | Strings.stencil          |
| アセット              | Assets.stencil           |
| プロパティリスト          | Plists.stencil           |
| フォント              | Fonts.stencil            |
| Core Data         | CoreData.stencil         |
| Interface Builder | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

プロジェクトでリソースシンセサイザーを定義する際、プラグイン名指定することで、そのプラグインのテンプレートを使用できます:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### タスクプラグイン <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
タスクプラグインは非推奨となりました。プロジェクト向けの自動化ソリューションをお探しの場合は、[こちらのブログ記事](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)をご覧ください。
<!-- -->
:::

タスクは`$PATH` に公開されており、命名規則`tuist-<task-name>` に従っている場合、`tuist`
コマンドを通じて実行可能です。以前のバージョンでは、Tuistは`tuist plugin`
を通じて、Swiftパッケージ内の実行可能ファイルによって表される`build` 、`run` 、`test` および`archive`
タスクのための、いくつかの非公式な規約とツールを提供していましたが、この機能はツールの保守負担と複雑さを増大させるため、現在は非推奨となっています。</task-name>

タスクの割り当てにTuistを使用している場合は、
- Tuistの各リリースに同梱されている`ProjectAutomation.xcframework`
  を引き続き使用することで、ロジック内からプロジェクトグラフにアクセスできます。`let graph = try Tuist.graph()`
  のように記述します。このコマンドはシステムプロセスを使用して`tuist` コマンドを実行し、プロジェクトグラフのメモリ内表現を返します。
- タスクを分散させるには、GitHubのリリースに`arm64` および`x86_64`
  をサポートするファットバイナリを含め、インストールツールとして[Mise](https://mise.jdx.dev)を使用することを推奨します。Miseにツールのインストール方法を指示するには、プラグインリポジトリが必要です。参考として[Tuist](https://github.com/asdf-community/asdf-tuist)を利用できます。
- ツールの名前を`tuist-{xxx}` とし、ユーザーが`mise install`
  を実行してインストールできるようにすれば、ユーザーは直接呼び出すか、`tuist xxx` を通じて実行することができます。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`ProjectAutomation` および`XcodeGraph`
の各モデルを統合し、プロジェクトグラフ全体をユーザーに公開する、後方互換性のある単一のフレームワークを構築する予定です。さらに、生成ロジックを新しいレイヤーである`XcodeGraph`
に抽出します。これは独自の CLI からも利用可能です。これは、独自の Tuist を構築するようなものと考えてください。
<!-- -->
:::

## プラグインの使用{#using-plugins}

プラグインを使用するには、プロジェクトの
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
マニフェストファイルに追加する必要があります:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

異なるリポジトリにあるプロジェクト間でプラグインを再利用したい場合は、プラグインをGitリポジトリにプッシュし、`のTuist.swift`
ファイルで参照するように設定できます：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

プラグインを追加した後、`tuist install` を実行すると、プラグインがグローバルキャッシュディレクトリに取得されます。

::: info NO VERSION RESOLUTION
<!-- -->
お気づきかもしれませんが、当サービスではプラグインのバージョン解決機能は提供しておりません。再現性を確保するため、GitタグまたはSHAの使用をお勧めします。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
プロジェクト説明ヘルパープラグインを使用する場合、ヘルパーを含むモジュールの名前がプラグインの名前となります
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
