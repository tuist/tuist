---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# テンプレート{#templates}

確立されたアーキテクチャを持つプロジェクトでは、開発者はプロジェクトと一貫性のある新しいコンポーネントや機能をブートストラップしたいかもしれません。`tuist
scaffold`
を使えば、テンプレートからファイルを生成することができます。独自のテンプレートを定義することも、Tuistで提供されているテンプレートを使用することもできます。これらはscaffoldが役に立つかもしれないいくつかのシナリオです：

- `tuist scaffold viper --name MyFeature`.
- 新規プロジェクトの作成:`tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuistはテンプレートの内容や使用目的については一切関知しません。特定のディレクトリにあることが要求されるだけです。
<!-- -->
:::

## テンプレートの定義{#defining-a-template}

テンプレートを定義するには、<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>を実行し、`Tuist/Templates` の下に、`name_of_template`
という、テンプレートを表すディレクトリを作成します。テンプレートには、`name_of_template.swift`
という、テンプレートを説明するマニフェスト・ファイルが必要です。したがって、`framework`
というテンプレートを作成する場合、`Tuist/Templates` に新しいディレクトリ`framework` を作成し、`framework.swift`
というマニフェスト・ファイルを作成する必要があります：


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

テンプレートを定義したら、`scaffold` コマンドから使用することができます：

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info
<!-- -->
プラットフォームはオプションの引数なので、`--platform macos` 引数なしでコマンドを呼び出すこともできる。
<!-- -->
:::

`.string` や`.files` では柔軟性が足りない場合は、`.file` のケースで
[Stencil](https://stencil.fuller.li/en/latest/)
テンプレート言語を活用できます。それ以外にも、ここで定義された追加のフィルターを使うこともできます。

文字列補間を使用すると、上記の`\(nameAttribute)` は`{{ name }}`
に解決されます。テンプレート定義でステンシル・フィルターを使用したい場合は、手動でこの補間を使用し、好きなフィルターを追加することができます。例えば、`{ {
名前 | 小文字 } } を使うことができます。name 属性の小文字の値を取得するには、`\(nameAttribute)` の代わりに` { { name
| 小文字 } を使用します。

また、`.directory` を使えば、指定したパスにフォルダ全体をコピーすることもできる。

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
テンプレートは<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</LocalizedLink>の使用をサポートし、テンプレート間でコードを再利用します。
<!-- -->
:::
