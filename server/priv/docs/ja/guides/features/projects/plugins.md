---
{
  "title": "プラグイン",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist でプラグインを作成・使用して機能を拡張する方法を学びます。"
}
---
# プラグイン {#plugins}

プラグインは、複数のプロジェクト間で Tuist の成果物を共有・再利用するためのツールです。以下の成果物がサポートされています。

- 複数のプロジェクトで <.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> を利用できます。
- 複数のプロジェクトで <.localized_link href="/guides/features/projects/templates">テンプレート</.localized_link> を利用できます。
- 複数のプロジェクトでタスクを利用できます。
- 複数のプロジェクトで <.localized_link href="/guides/features/projects/synthesized-files">リソースアクセサ</.localized_link> テンプレートを利用できます。

プラグインは Tuist の機能を簡単に拡張できるよう設計されています。そのため、**いくつかの制限事項**があります。

- プラグインは他のプラグインに依存できません。
- プラグインはサードパーティの Swift パッケージに依存できません。
- プラグインは、そのプラグインを使用するプロジェクトのプロジェクト記述ヘルパーを利用できません。

より高い柔軟性が必要な場合は、ツールの機能提案を検討するか、Tuist の生成フレームワークである [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator) を基盤に独自のソリューションを構築してください。

## プラグインの種類 {#plugin-types}

### プロジェクト記述ヘルパー プラグイン {#project-description-helper-plugin}

プロジェクト記述ヘルパー プラグインは、プラグイン名を宣言する `Plugin.swift` マニフェストファイルと、ヘルパーとなる Swift ファイルを含む `ProjectDescriptionHelpers` ディレクトリを持つディレクトリとして表現されます。

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

<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成されたリソースアクセサ</.localized_link> を共有したい場合は、この種類のプラグインを利用できます。プラグインは、プラグイン名を宣言する `Plugin.swift` マニフェストファイルと、リソースアクセサのテンプレートファイルを含む `ResourceSynthesizers` ディレクトリを持つディレクトリとして表現されます。


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

テンプレートの名前は、リソース型の [キャメルケース](https://en.wikipedia.org/wiki/Camel_case) 版になります。

| リソース型 | テンプレートファイル名 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

プロジェクトでリソースシンセサイザーを定義する際、プラグイン名の指定によりプラグイン内のテンプレートを利用できます。

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### タスク プラグイン <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **非推奨**
>
> タスク プラグインは非推奨です。プロジェクトの自動化ソリューションをお探しの場合は、[こちらのブログ記事](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)をご覧ください。


タスクは `$PATH` に公開された実行ファイルであり、`tuist-<task-name>` という命名規則に従っていれば `tuist` コマンドを通じて呼び出せます。以前のバージョンでは、Tuist は Swift Packages 内の実行ファイルで表現される `build`、`run`、`test`、`archive` タスク向けに `tuist plugin` の下でいくつかの緩やかな規約とツールを提供していましたが、ツールの保守負担と複雑さが増すため、この機能は非推奨となりました。

タスクをプラグインとして配布していた場合は、代わりにスタンドアロンの実行ファイルとしてビルドしてください。

- すべての Tuist リリースに同梱されている `ProjectAutomation.xcframework` を引き続き使用し、`let graph = try Tuist.graph()` でプロジェクトグラフにアクセスできます。これは `tuist` をサブプロセスとして実行し、プロジェクトグラフのメモリ内表現を返します。
- タスクを配布するには、GitHub リリースで `arm64` と `x86_64` をサポートするユニバーサルバイナリを公開し、インストールツールとして [Mise](https://mise.jdx.dev) を使用することをお勧めします。Mise にツールのインストール方法を指示するには、プラグインリポジトリが必要です。[Tuist のもの](https://github.com/asdf-community/asdf-tuist)を参考にできます。
- ツールに `tuist-{xxx}` という名前を付け、ユーザーが `mise install` を実行してインストールできるようにすれば、直接呼び出すか、`tuist xxx` を介して実行できます。

> [!NOTE]
> **ProjectAutomation の将来**
>
> `ProjectAutomation` と `XcodeGraph` のモデルを統合し、プロジェクトグラフ全体をユーザーに公開する単一の後方互換性のあるフレームワークにする予定です。さらに、生成ロジックを新しい層 `XcodeGraph` として抽出し、独自の CLI から利用できるようにします。独自の Tuist を構築すると考えてください。


## プラグインの利用 {#using-plugins}

プラグインを使用するには、プロジェクトの [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) マニフェストファイルに追加する必要があります。

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

異なるリポジトリにある複数のプロジェクトでプラグインを再利用したい場合は、プラグインを Git リポジトリにプッシュし、`Tuist.swift` ファイルで参照できます。

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

プラグインを追加した後、`tuist install` がグローバルキャッシュディレクトリにプラグインを取得します。

> [!NOTE]
> **バージョン解決なし**
>
> ご指摘のとおり、プラグインのバージョン解決は提供していません。再現性を確保するため、Git タグまたは SHA を使用することをお勧めします。


> [!TIP]
> **プロジェクト記述ヘルパー プラグイン**
>
> プロジェクト記述ヘルパー プラグインを使用する場合、ヘルパーを含むモジュールの名前はプラグインの名前になります。
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
