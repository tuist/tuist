---
{
  "title": "テンプレート",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist でテンプレートを作成・使用し、プロジェクト内のコードを生成する方法を学びます。"
}
---
# テンプレート {#templates}

確立されたアーキテクチャを持つプロジェクトでは、開発者はプロジェクトと整合性のある新しいコンポーネントや機能をブートストラップしたい場合があります。`tuist scaffold` を使用すると、テンプレートからファイルを生成できます。独自のテンプレートを定義することも、Tuist に同梱されているテンプレートを使用することもできます。スキャフォールディングが役立つシナリオの例をいくつか挙げます:

- 特定のアーキテクチャに従う新しい機能を作成する: `tuist scaffold viper --name MyFeature`。
- 新しいプロジェクトを作成する: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **非拘束的**
>
> Tuist はテンプレートの内容や用途について特定の制約を課しません。特定のディレクトリに配置されていることだけが要件です。


## テンプレートの定義 {#defining-a-template}

テンプレートを定義するには、<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> を実行し、`Tuist/Templates` 配下にテンプレートを表す `name_of_template` という名前のディレクトリを作成します。テンプレートには、そのテンプレートを記述するマニフェストファイル `name_of_template.swift` が必要です。したがって、`framework` という名前のテンプレートを作成する場合、`Tuist/Templates` に `framework` という新しいディレクトリを作成し、`framework.swift` という名前のマニフェストファイルを配置します。このファイルは次のようになります:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## テンプレートの使用 {#using-a-template}

テンプレートを定義した後、`scaffold` コマンドから使用できます:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> platform はオプションの引数であるため、`--platform macos` 引数を指定せずにコマンドを実行することもできます。


`.string` と `.files` で十分な柔軟性が得られない場合は、`.file` ケースを通じて [Stencil](https://stencil.fuller.li/en/latest/) テンプレート言語を活用できます。さらに、ここで定義されている追加のフィルターも使用できます。

文字列補間を使用すると、上記の `\(nameAttribute)` は `{{ name }}` に解決されます。テンプレート定義で Stencil フィルターを使用したい場合は、その補間を手動で使用し、任意のフィルターを追加できます。たとえば、name 属性の小文字値を取得するために、`\(nameAttribute)` の代わりに `{ { name | lowercase } }` を使用できます。

また、`.directory` を使用して、フォルダー全体を指定のパスにコピーすることもできます。

> [!TIP]
> **Project Description Helpers**
>
> テンプレートでは、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト説明ヘルパー</.localized_link> を使用して、テンプレート間でコードを再利用できます。
