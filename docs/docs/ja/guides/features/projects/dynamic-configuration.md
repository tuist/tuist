---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 動的構成{#dynamic-configuration}

プロジェクト生成時に動的に設定を変更する必要が生じる場合があります。例えば、生成環境に応じてアプリ名、バンドル識別子、デプロイメントターゲットを変更したい場合などです。Tuistでは環境変数を通じてこれをサポートしており、マニフェストファイルからアクセス可能です。

## 環境変数による設定{#configuration-through-environment-variables}

Tuistは、マニフェストファイルからアクセス可能な環境変数を通じて設定を渡すことを許可します。例：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

複数の環境変数を渡す場合は、スペースで区切ってください。例：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## マニフェストから環境変数を読み取る{#reading-the-environment-variables-from-manifests}

変数は
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
の形式でアクセスできます。環境で定義された、またはコマンド実行時に Tuist に渡された`TUIST_XXX` 形式の変数は、`Environment`
の形式でアクセス可能です。以下の例は`TUIST_APP_NAME` 変数のアクセス方法を示しています：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

変数へのアクセスは、`Environment.Value?` の型を持つインスタンスを返します。このインスタンスは以下のいずれかの値を取ります：

| 大文字小文字            | 説明                 |
| ----------------- | ------------------ |
| `.string(String)` | 変数が文字列を表す場合に使用します。 |

以下のヘルパーメソッドのいずれかを使用して、文字列またはブール値の`環境`
変数を取得することもできます。これらのメソッドは、ユーザーが毎回一貫した結果を得られるように、デフォルト値を渡す必要があります。これにより、上記のappName()関数を定義する必要がなくなります。

コードグループ

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
