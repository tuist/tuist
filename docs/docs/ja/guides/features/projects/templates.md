---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# テンプレート{#templates}

確立されたアーキテクチャを持つプロジェクトでは、開発者はプロジェクトと一貫性のある新しいコンポーネントや機能をブートストラップしたい場合があります。`tuist
scaffold`
を使用すると、テンプレートからファイルを生成できます。独自のテンプレートを定義することも、Tuistにバンドルされているテンプレートを使用することもできます。スキャフォールディングが役立つシナリオの例を以下に示します：

- 指定されたアーキテクチャに従う新機能を作成:`tuist scaffold viper --name MyFeature`
- 新規プロジェクト作成:`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuistはテンプレートの内容や使用目的に関して特定の制約を課しません。指定されたディレクトリに配置されていることのみが求められます。
<!-- -->
:::

## テンプレートの定義{#defining-a-template}

テンプレートを定義するには、<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> を実行し、その後、テンプレートを表すディレクトリ`name_of_template`
を`Tuist/Templates` の下に作成します。
テンプレートには、テンプレートを記述するマニフェストファイル`name_of_template.swift` が必要です。例えば、`framework`
というテンプレートを作成する場合、新しいディレクトリ`framework` を`Tuist/Templates`
に作成し、マニフェストファイル`framework.swift` を配置します。その内容は以下のようなものになります：


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

## テンプレートの使用{#using-a-template}

テンプレートを定義した後、`のscaffoldコマンド（` ）から使用できます：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
platform はオプション引数であるため、`--platform macos` 引数なしでコマンドを呼び出すことも可能です。
<!-- -->
:::

`.string` および`.files` の柔軟性が不十分な場合、`.file` のケースで
[Stencil](https://stencil.fuller.li/en/latest/)
テンプレート言語を活用できます。さらに、ここで定義されている追加フィルターも使用可能です。

文字列補間を使用すると、`\(nameAttribute)` は`{{ name }}`
に展開されます。テンプレート定義でステンシルフィルターを使用したい場合は、この補間を手動で実行し、任意のフィルターを追加できます。例えば、name属性の小文字化値を取得するには、`\(nameAttribute)`
の代わりに`{ { name | lowercase } }` を使用できます。

`.directory` も使用可能です。これにより、指定されたパスへフォルダ全体をコピーできます。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
テンプレートでは、<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト説明ヘルパー</LocalizedLink>を使用して、テンプレート間でコードを再利用できます。
<!-- -->
:::
