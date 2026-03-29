---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# 動的設定{#dynamic-configuration}

生成時にプロジェクトを動的に設定する必要がある場合があります。たとえば、プロジェクトが生成される環境に応じて、アプリ名、バンドル識別子、またはデプロイメントターゲットを変更したい場合などです。Tuistでは、マニフェストファイルからアクセス可能な環境変数を通じて、このような設定をサポートしています。

## 環境変数による設定{#configuration-through-environment-variables}

Tuist では、マニフェストファイルからアクセス可能な環境変数を通じて設定を渡すことができます。例：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

複数の環境変数を渡したい場合は、スペースで区切ってください。例：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## マニフェストから環境変数を読み込む{#reading-the-environment-variables-from-manifests}

変数には、<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>
形式を使用してアクセスできます。環境内で定義されているか、コマンド実行時に Tuist に渡された、`TUIST_XXX`
という形式の変数は、`Environment` 形式を使用してアクセスできます。以下の例は、`TUIST_APP_NAME`
変数にアクセスする方法を示しています:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

変数にアクセスすると、`Environment.Value? 型のインスタンスが返されます。` であり、以下のいずれかの値をとることができます：

| 大文字・小文字           | 説明                 |
| ----------------- | ------------------ |
| `.string(String)` | 変数が文字列を表す場合に使用します。 |

また、以下に定義されたヘルパーメソッドのいずれかを使用して、文字列またはブール値の`環境変数`
を取得することもできます。これらのメソッドでは、ユーザーが毎回一貫した結果を得られるように、デフォルト値を渡す必要があります。これにより、上記で定義したappName()関数を定義する必要がなくなります。

コードグループ

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
