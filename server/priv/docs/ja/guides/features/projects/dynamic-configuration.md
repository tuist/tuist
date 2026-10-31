---
{
  "title": "動的な設定",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "環境変数を使用してプロジェクトを動的に設定する方法を学びます。"
}
---
# 動的な構成 {#dynamic-configuration}

プロジェクトの生成時に動的に構成する必要があるシナリオがあります。例えば、プロジェクトが生成される環境に応じて、アプリ名、バンドル識別子、またはデプロイメントターゲットを変更したい場合があります。Tuist は環境変数を介してこれをサポートしており、マニフェストファイルからアクセスできます。

## 環境変数による構成 {#configuration-through-environment-variables}

Tuist では、マニフェストファイルからアクセスできる環境変数を介して構成を渡すことができます。例：

```bash
TUIST_APP_NAME=MyApp tuist generate
```

複数の環境変数を渡す場合は、スペースで区切ります。例：

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## マニフェストからの環境変数の読み取り {#reading-the-environment-variables-from-manifests}

変数は [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) 型を使用してアクセスできます。環境で定義されているか、コマンド実行時に Tuist に渡された `TUIST_XXX` の規則に従う変数は、`Environment` 型を使用してアクセスできます。次の例は、`TUIST_APP_NAME` 変数へのアクセス方法を示しています。

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

変数へのアクセスは `Environment.Value?` 型のインスタンスを返し、以下のいずれかの値を取ることができます。

| ケース | 説明 |
| --- | --- |
| `.string(String)` | 変数が文字列を表す場合に使用されます。 |

また、以下に定義されているヘルパーメソッドのいずれかを使用して、文字列またはブーリアンの `Environment` 変数を取得することもできます。これらのメソッドでは、ユーザーが毎回一貫した結果を得られるようにデフォルト値を渡す必要があります。これにより、上記で定義した appName() 関数を定義する必要がなくなります。

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::

## 追加の環境変数をマニフェストに転送する {#forwarding-additional-environment-variables-to-manifests}

デフォルトでは、`TUIST_` プレフィックスが付いた変数と `CI` および `DEVELOPER_DIR` のみが、`Project.swift`、`Workspace.swift`、`Package.swift`、およびプロジェクト記述ヘルパーを評価するサブプロセスに転送されます。これにより、生成が決定的になり、無関係なシェルまたは CI 変数がマニフェストキャッシュを無効化するのを防ぎます。

マニフェストが制御できない変数（例えば、すでに `OPENSWIFTUI_LIBRARY_TYPE` を読み取っているサードパーティの `Package.swift` など）を読み取る必要がある場合は、生成オプションの `manifestEnvironment` を介して `Tuist.swift` でそれらを宣言します。各エントリは、リテラル名またはプレフィックスマッチング用に `*` で終わる名のいずれかです。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

リストされた変数はマニフェストキャッシュハッシュに参加するため、その値の変更は期待どおりにキャッシュを無効化します。リストされていない変数はマニフェスト評価から隠されたままになります。
