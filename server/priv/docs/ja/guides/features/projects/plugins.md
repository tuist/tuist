---
{
  "title": "プラグイン",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist でプラグインを作成・使用して機能を拡張する方法を学びます。"
}
---
# プラグイン {#plugins}

プラグインは、複数のプロジェクト間で Tuist の成果物を共有・再利用するためのツールです。以下の成果物がサポートされています：

- <.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link>を複数のプロジェクト間で共有
- <.localized_link href="/guides/features/projects/templates">テンプレート</.localized_link>を複数のプロジェクト間で共有
- タスクを複数のプロジェクト間で共有
- <.localized_link href="/guides/features/projects/synthesized-files">リソースアクセサ</.localized_link>テンプレートを複数のプロジェクト間で共有

プラグインは Tuist の機能を拡張するシンプルな手段として設計されています。そのため、**考慮すべき制限がいくつかあります**：

- プラグインは他のプラグインに依存できません。
- プラグインはサードパーティの Swift パッケージに依存できません。
- プラグインは、そのプラグインを使用するプロジェクトのプロジェクト記述ヘルパーを利用できません。

より高い柔軟性が必要な場合は、ツールへの機能提案を検討するか、Tuist の生成フレームワークである [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator) を基盤として独自のソリューションを構築することを検討してください。

## プラグインの種類 {#plugin-types}

### プロジェクト記述ヘルパー プラグイン {#project-description-helper-plugin}

プロジェクト記述ヘルパー プラグインは、プラグイン名を宣言する `Plugin.swift` マニフェストファイルと、ヘルパー Swift ファイルを含む `ProjectDescriptionHelpers` ディレクトリを持つディレクトリとして表されます。

::: code-group
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

### リソースアクセサ テンプレート プラグイン {#resource-accessor-templates-plugin}

<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成リソースアクセサ</.localized_link>を共有する必要がある場合、このタイプのプラグインを使用できます。このプラグインは、プラグイン名を宣言する `Plugin.swift` マニフェストファイルと、リソースアクセサ テンプレートファイルを含む `ResourceSynthesizers` ディレクトリを持つディレクトリとして表されます。


::: code-group
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

テンプレート名は、リソースタイプの [キャメルケース](https://en.wikipedia.org/wiki/Camel_case) 版になります：

| リソースタイプ | テンプレートファイル名 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

プロジェクトでリソースシンセサイザーを定義する際、プラグイン名の指定によりプラグイン内のテンプレートを使用できます：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### タスク プラグイン <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **非推奨**
>
> タスク プラグインは非推奨です。プロジェクトの自動化ソリューションをお探しの場合は、[このブログ記事](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)をご覧ください。


タスクは `$PATH` に公開される実行ファイルであり、`tuist-<task-name>` の命名規則に従っていれば `tuist` コマンドを通じて呼び出すことができます。以前のバージョンでは、Tuist は Swift パッケージ内の実行ファイルで表される `build`、`run`、`test`、`archive` タスクに対して `tuist plugin` の下でいくつかの緩やかな規約とツールを提供していましたが、この機能はツールのメンテナンス負担と複雑さを増大させるため非推奨となりました。

タスクの配布に Tuist を使用していた場合は、独自の
- すべての Tuist リリースに同梱されている `ProjectAutomation.xcframework` を引き続き使用し、`let graph = try Tuist.graph()` を介してロジックからプロジェクトグラフにアクセスできます。このコマンドはシステムプロセスを使用して `tuist` コマンドを実行し、プロジェクトグラフのメモリ内表現を返します。
- タスクを配布するには、GitHub リリースに `arm64` と `x86_64` をサポートするファットバイナリを含め、インストールツールとして [Mise](https://mise.jdx.dev) を使用することをお勧めします。Mise にツールのインストール方法を指示するには、プラグインリポジトリが必要です。[Tuist の](https://github.com/asdf-community/asdf-tuist)リポジトリを参考にすることができます。
- ツールに `tuist-{xxx}` という名前を付け、ユーザーが `mise install` を実行してインストールできるようにすると、直接呼び出すか、`tuist xxx` を介して実行できます。

> [!NOTE]
> **ProjectAutomation の将来**
>
> `ProjectAutomation` と `XcodeGraph` のモデルを統合し、プロジェクトグラフ全体をユーザーに公開する単一の後方互換性のあるフレームワークにする予定です。さらに、生成ロジックを新しいレイヤー `XcodeGraph` として抽出し、独自の CLI から使用できるようにします。これは独自の Tuist を構築するようなものと考えてください。


## プラグインの使用 {#using-plugins}

プラグインを使用するには、プロジェクトの [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) マニフェストファイルに追加する必要があります：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

異なるリポジトリにあるプロジェクト間でプラグインを再利用したい場合は、プラグインを Git リポジトリにプッシュし、`Tuist.swift` ファイルで参照できます：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

プラグインを追加した後、`tuist install` がグローバルキャッシュディレクトリでプラグインを取得します。

> [!NOTE]
> **バージョン解決なし**
>
> ご存知のとおり、プラグインのバージョン解決は提供していません。再現性を確保するために、Git タグまたは SHA を使用することをお勧めします。


> [!TIP]
> **プロジェクト記述ヘルパー プラグイン**
>
> プロジェクト記述ヘルパー プラグインを使用する場合、ヘルパーを含むモジュールの名前はプラグインの名前になります
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
