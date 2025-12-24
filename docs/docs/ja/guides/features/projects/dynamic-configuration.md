---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# ダイナミック・コンフィギュレーション{#dynamic-configuration}

生成時にプロジェクトを動的に設定する必要があるシナリオがあります。たとえば、プロジェクトが生成される環境に基づいて、アプリの名前、バンドル識別子、またはデプロイメントターゲットを変更したい場合があります。Tuist
は、マニフェストファイルからアクセス可能な環境変数によってこれをサポートします。

## 環境変数による設定{#configuration-through-environment-variables}

Tuistでは、マニフェストファイルからアクセス可能な環境変数を通して設定を渡すことができます。例えば

```bash
TUIST_APP_NAME=MyApp tuist generate
```

複数の環境変数を渡したい場合は、スペースで区切ってください。例えば

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## マニフェストから環境変数を読み取る{#reading-the-environment-variables-from-manifests}

変数は<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>型を使ってアクセスできる。`TUIST_XXX`
環境で定義された、あるいはコマンド実行時にTuistに渡された規約に従った変数は、`Environment`
型を使ってアクセスできる。次の例は`TUIST_APP_NAME` 変数にアクセスする方法を示している：

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

変数にアクセスすると、`Environment.Value?` 、以下のいずれかの値を取ることができる型のインスタンスが返される：

| ケース               | 説明                |
| ----------------- | ----------------- |
| `.string(String)` | 変数が文字列を表す場合に使用する。 |

以下に定義するヘルパー・メソッドのいずれかを使用して、文字列またはブーリアン`環境`
変数を取得することもできます。これらのメソッドでは、ユーザーが毎回一貫した結果を得られるように、デフォルト値を渡す必要があります。これにより、上で定義した関数
appName() を定義する必要がなくなります。

コードグループ

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
