---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# プラグイン{#plugins}

プラグインは、複数のプロジェクトでTuistの成果物を共有・再利用するためのツールである。以下の成果物がサポートされている：

- <LocalizedLink href="/guides/features/projects/code-sharing">複数のプロジェクトにまたがるプロジェクト説明ヘルパー</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">複数のプロジェクトにまたがるテンプレート</LocalizedLink>。
- 複数のプロジェクトにまたがるタスク。
- <LocalizedLink href="/guides/features/projects/synthesized-files">複数のプロジェクトにまたがるリソース・アクセッサ</LocalizedLink>テンプレート

プラグインはTuistの機能を拡張する簡単な方法として設計されていることに注意してください。そのため、**いくつか考慮すべき制限があります** ：

- プラグインは他のプラグインに依存することはできません。
- プラグインはサードパーティのSwiftパッケージに依存できない
- プラグインは、そのプラグインを使うプロジェクトのプロジェクト記述ヘルパーを使うことはできません。

より柔軟性が必要な場合は、ツールの機能を提案するか、Tuistの生成フレームワーク[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)に基づいて独自のソリューションを構築することを検討してください。

## プラグインの種類{#plugin-types}

### プロジェクト説明ヘルパープラグイン{#project-description-helper-plugin}

プロジェクト記述ヘルパープラグインは、プラグインの名前を宣言する`Plugin.swift` マニフェストファイルとヘルパー Swift
ファイルを含む`ProjectDescriptionHelpers` ディレクトリを含むディレクトリによって表されます。

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

### リソース・アクセッサ・テンプレート・プラグイン{#resource-accessor-templates-plugin}

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成されたリソース・アクセッサ</LocalizedLink>を共有する必要がある場合、このタイプのプラグインを使用できます。プラグインは、プラグインの名前を宣言する`Plugin.swift`
マニフェスト ファイルと、リソース アクセッサ テンプレート ファイルを含む`ResourceSynthesizers`
ディレクトリを含むディレクトリで表されます。


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

テンプレートの名前は、リソースタイプの[キャメルケース](https://en.wikipedia.org/wiki/Camel_case)バージョンです：

| リソースタイプ      | テンプレートファイル名                  |
| ------------ | ---------------------------- |
| ストリングス       | 文字列.ステンシル                    |
| 資産           | 資産.ステンシル                     |
| 物件リスト        | プリスト.ステンシル                   |
| フォント         | フォント.ステンシル                   |
| コア・データ       | CoreData.stencil（コアデータ・ステンシル |
| インターフェースビルダー | InterfaceBuilder.stencil     |
| JSON         | JSON.stencil                 |
| ヤムル          | YAML.stencil                 |

プロジェクトでリソース・シンセサイザーを定義する際、プラグイン名を指定することで、プラグインのテンプレートを使用することができます：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### タスクプラグイン <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
タスク・プラグインは非推奨です。プロジェクトの自動化ソリューションをお探しなら、[このブログ記事](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)をチェックしてください。
<!-- -->
:::

タスクは`$PATH`-公開された実行可能ファイルであり、命名規則`tuist-<task-name>` に従っていれば`tuist`
コマンドを通して呼び出すことができる。以前のバージョンでは、Tuistは`build`,`run`,`test` and`archive` tasks
represented by executables in Swift Packagesのために、`tuist plugin`
の下でいくつかの弱い規約とツールを提供していましたが、ツールのメンテナンス負担と複雑さを増加させるので、この機能は非推奨としました。

タスクの分散にTuistを使用していた場合は、次のように構築することをお勧めします。
- Tuistリリースごとに配布される`ProjectAutomation.xcframework` を使い続けることで、`let graph = try
  Tuist.graph()` でロジックからプロジェクトグラフにアクセスすることができます。このコマンドはsytemプロセスを使用して`tuist`
  コマンドを実行し、プロジェクトグラフのインメモリ表現を返します。
- タスクを配布するには、`arm64` と`x86_64` をサポートするファットバイナリを GitHub リリースに含め、インストールツールとして
  [Mise](https://mise.jdx.dev)
  を使用することをお勧めします。あなたのツールのインストール方法をMiseに指示するには、プラグインリポジトリが必要です。Tuistの](https://github.com/asdf-community/asdf-tuist)を参考にしてください。
- ツールの名前を`tuist-{xxx}` とし、ユーザが`mise install`
  を実行することでインストールできるようにした場合、ユーザはそれを直接呼び出すか、`tuist xxx` を通して実行することができます。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
私たちは、`ProjectAutomation` と`XcodeGraph`
のモデルを、プロジェクトグラフの全体をユーザに公開する単一の下位互換性のあるフレームワークに統合する予定です。さらに、生成ロジックを新しいレイヤー、`XcodeGraph`
に抽出し、独自のCLIからも使用できるようにします。これは、あなた自身のTuistを構築するようなものだと考えてください。
<!-- -->
:::

## プラグインの使用{#using-plugins}

プラグインを使用するには、プロジェクトの
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
マニフェスト ファイルに追加する必要があります：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

異なるリポジトリにあるプロジェクト間でプラグインを再利用したい場合は、プラグインをGitリポジトリにプッシュし、`Tuist.swift`
ファイルで参照することができます：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

プラグインを追加した後、`tuist install` 、グローバル・キャッシュ・ディレクトリにあるプラグインを取得する。

::: info NO VERSION RESOLUTION
<!-- -->
お気づきかもしれませんが、私たちはプラグインのバージョン解決を提供していません。再現性を確保するために、GitタグやSHAを使うことをお勧めします。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
プロジェクト記述ヘルパーのプラグインを使うとき、ヘルパーを含むモジュールの名前がプラグインの名前になる
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
