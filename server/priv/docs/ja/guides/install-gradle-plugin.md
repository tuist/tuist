---
{
  "title": "Gradle プラグインのインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "プロジェクトで Tuist の Gradle プラグインをインストールおよび設定する方法を学びます。"
}
---
# Gradle プラグインのインストール {#install-the-gradle-plugin}

Tuist は、<.localized_link href="/guides/features/cache/gradle-cache">リモートビルドキャッシュ</.localized_link> や <.localized_link href="/guides/features/build-insights/gradle">ビルドインサイト</.localized_link> などの機能を有効にするために Gradle プロジェクトと統合する Gradle プラグインを提供します。このガイドでは、プラグインのインストールと設定手順を説明します。

このプラグインには Gradle 8.12.1 以降が必要です。

## 1. Tuist の初期化 {#initialize-tuist}

Gradle プロジェクトのルートで次のコマンドを実行してください。

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

このコマンドは、認証の実施、Tuist プロジェクトの作成または選択、および Gradle プロジェクト用の設定生成の手順を案内します。

## 2. プラグインの適用 {#apply-the-plugin}

`tuist init` を実行した後、コマンド出力の指示に従って `settings.gradle.kts` に Tuist プラグインを追加する必要があります。

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. チームと継続的インテグレーションの認証 {#authenticate}

`tuist init` はローカル環境であなたを認証しますが、チームメンバーや <.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーション</.localized_link> 環境は別途認証を行う必要があります。

各チームメンバーは、自分のマシンで Tuist の機能にアクセスするために次のコマンドを実行してください。

```bash
tuist auth login
```

セルフホスト型またはローカルの Tuist サーバーを使用する場合は、`tuist.toml` で設定したのと同じベース URL を指定してください。

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

ホスト名の表記を一貫させてください。たとえば、`localhost` 用に保存されたログイン情報は `127.0.0.1` 用に保存されたものとは別扱いです。

自動化されたランナーの場合は、<.localized_link href="/guides/integrations/continuous-integration#authentication">継続的インテグレーションの認証ガイド</.localized_link> に従って、環境向けの認証を設定してください。

## 構成キャッシュと分離プロジェクト {#configuration-cache-and-isolated-projects}

このプラグインは Gradle の構成キャッシュと [分離プロジェクト](https://docs.gradle.org/current/userguide/isolated_projects.html) をサポートしています。プラグインは `settings.gradle.kts` に記述したままにしておき、各サブプロジェクトに個別に適用する必要はありません。

Tuist はこれらの機能を自動的に有効にしません。オプトインするには、`gradle.properties` に以下を追加してください。

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

ビルドスクリプトや他のプラグインもこれらの機能をサポートしている必要があります。Gradle は構成キャッシュの保存時に互換性の問題を報告します。

## 設定リファレンス {#configuration-reference}

以下のオプションは、`settings.gradle.kts` 内の `tuist` 拡張ブロックで利用可能です。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（任意） | `account/project` 形式のプロジェクト識別子。設定されていない場合、プラグインは `tuist.toml` から読み取ります。 |
| `url` | `String?` | `null` | Tuist サーバーのベース URL。設定されていない場合、デフォルトは `"https://tuist.dev"` または `tuist.toml` で定義された値になります。 |
| `uploadInBackground` | `Boolean?` | `null` | ビルドおよびテストのインサイトをバックグラウンドでアップロードするかどうか。`null`（デフォルト）の場合、ローカルビルドではバックグラウンドで、継続的インテグレーションのランナー上ではフォアグラウンドでアップロードが実行されます。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` または `"enforce"`。ビルドによって追加されたテストケースを再実行し、不安定なものをフラグ付けします。<.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">新しいテストのストレステスト</.localized_link> も参照してください。未設定の場合は無効です。 |

`http://` URL を使用するローカルサーバーの場合、そのローカル設定でのみ安全でないプロトコルを許可してください。

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

ホスティングされたサーバーやその他の `https://` サーバーでは `allowInsecureProtocol` を有効にしないでください。

> [!NOTE]
> **Tuist.toml**
>
> `project`（および任意で `url`）を設定する推奨方法は、プロジェクトルートにある `tuist.toml` ファイルを使用することです。これにより、Tuist コマンドラインインターフェースと Gradle プラグインの間で設定が共有されます。必要に応じて `settings.gradle.kts` でこれらの値を上書きすることもできます。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP プロキシ {#http-proxy}

ネットワークが HTTP プロキシ経由でアウトバウンドトラフィックをルーティングする場合は、<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link> を参照してください。

## 次のステップ {#next-steps}

プラグインのインストールと設定が完了したら、以下を有効にできます。

- <.localized_link href="/guides/features/cache/gradle-cache">リモートビルドキャッシュ</.localized_link>：チーム全体および継続的インテグレーションのランナー間でビルド成果物を共有します。
- <.localized_link href="/guides/features/build-insights/gradle">ビルドインサイト</.localized_link>：Tuist ダッシュボードでタスクの実行時間とキャッシュの動作を追跡します。
- <.localized_link href="/guides/features/test-insights/gradle">テストインサイト</.localized_link>：テストのパフォーマンスを追跡し、不安定なテストを検出します。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不安定なテスト</.localized_link>：不安定なテストを自動的に検出、追跡、隔離します。
