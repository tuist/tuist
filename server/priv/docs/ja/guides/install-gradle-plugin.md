---
{
  "title": "Gradle プラグインのインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "プロジェクトで Tuist の Gradle プラグインをインストールして設定する方法を学びます。"
}
---
# Gradle プラグインをインストールする {#install-the-gradle-plugin}

Tuist は、<.localized_link href="/guides/features/cache/gradle-cache">リモートビルドキャッシュ</.localized_link>や<.localized_link href="/guides/features/build-insights/gradle">ビルドインサイト</.localized_link>などの機能を有効にするために Gradle プロジェクトと統合される Gradle プラグインを提供します。このガイドでは、プラグインのインストールと設定手順を説明します。

このプラグインには Gradle 8.12.1 以降が必要です。

## 1. Tuist を初期化する {#initialize-tuist}

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

このコマンドは、認証、Tuist プロジェクトの作成または選択、Gradle プロジェクトの設定生成の手順を案内します。

## 2. プラグインを適用する {#apply-the-plugin}

`tuist init` を実行した後、コマンド出力の指示に従って `settings.gradle.kts` に Tuist プラグインを追加する必要があります。

<!-- @snippet: ./_gradle-plugin-block -->

## 3. チームと継続的インテグレーションを認証する {#authenticate}

`tuist init` はローカルであなたを認証しますが、チームメンバーと<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーション</.localized_link>環境は別途認証する必要があります。

各チームメンバーは、自分のマシンで Tuist の機能にアクセスするために次のコマンドを実行してください。

```bash
tuist auth login
```

セルフホスト型またはローカルの Tuist サーバーを使用する場合は、`tuist.toml` で設定した同じベース URL を指定してください。

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

ホスト名の表記を一貫させてください。例えば、`localhost` 用に保存されたログイン情報は `127.0.0.1` 用に保存されたものとは別物です。

自動実行ランナーの場合は、<.localized_link href="/guides/server/authentication#continuous-integration">継続的インテグレーション認証ガイド</.localized_link>に従って、環境に応じた認証を設定してください。

## 構成キャッシュと分離プロジェクト {#configuration-cache-and-isolated-projects}

このプラグインは Gradle の構成キャッシュと[分離プロジェクト](https://docs.gradle.org/current/userguide/isolated_projects.html)をサポートしています。プラグインは `settings.gradle.kts` に記述したままにしておき、各サブプロジェクトに個別に適用する必要はありません。

Tuist はこれらの機能を自動的に有効にしません。有効にするには、`gradle.properties` に以下を追加してください。

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

ビルドスクリプトや他のプラグインもこれらの機能をサポートしている必要があります。Gradle は構成キャッシュを保存する際に互換性の問題を報告します。

## プレビューを公開する {#publish-previews}

Android アプリケーションモジュールの場合、プラグインは `tuistShare<Variant>` タスクを登録します。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

このタスクは署名付き APK を 1 つビルドして検証し、既存の Tuist 認証を使用して公開します。タスクの実行がオプトインとなります。通常の `assemble`、`build`、およびテストタスクはプレビューを公開しません。CLI でのアップロード手順は不要です。対象条件、キャッシュのリプレイ、失敗時の動作については、<.localized_link href="/guides/features/previews/gradle">Gradle プレビュー</.localized_link>を参照してください。

## 設定リファレンス {#configuration-reference}

`settings.gradle.kts` 内の `tuist` 拡張ブロックで使用可能なオプションは次のとおりです。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（任意） | `account/project` 形式のプロジェクト識別子。設定されていない場合、プラグインは `tuist.toml` から読み取ります。 |
| `url` | `String?` | `null` | Tuist サーバーのベース URL。設定されていない場合、デフォルトは `"https://tuist.dev"` または `tuist.toml` で定義された値になります。 |
| `uploadInBackground` | `Boolean?` | `null` | ビルドおよびテストのインサイトをバックグラウンドでアップロードするかどうか。`null`（デフォルト）の場合、ローカルビルドではバックグラウンドで、継続的インテグレーションランナー上ではフォアグラウンドでアップロードが実行されます。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` または `"enforce"`。ビルドによって追加されたテストケースを再実行し、不安定なものをフラグ付けします。<.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">新しいテストの負荷テスト</.localized_link>を参照してください。未設定の場合は無効です。 |

`http://` URL を使用するローカルサーバーの場合、そのローカル設定でのみ安全でないプロトコルを許可してください。

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

ホスト型サーバーやその他の `https://` サーバーで `allowInsecureProtocol` を有効にしないでください。

> [!NOTE]
> **Tuist.toml**
>
> `project`（および任意で `url`）を設定する推奨方法は、プロジェクトルートにある `tuist.toml` ファイルを使用することです。これにより、Tuist コマンドラインインターフェースと Gradle プラグインの間で設定が共有されます。必要に応じて `settings.gradle.kts` でこれらの値を上書きすることもできます。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP プロキシ {#http-proxy}

ネットワークが HTTP プロキシ経由で送信トラフィックをルーティングする場合は、<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link>を参照してください。

## 次のステップ {#next-steps}

プラグインのインストールと設定が完了したら、次の機能を有効にできます。

- <.localized_link href="/guides/features/cache/gradle-cache">リモートビルドキャッシュ</.localized_link>を使用して、チームや継続的インテグレーションランナー間でビルド成果物を共有します。
- <.localized_link href="/guides/features/build-insights/gradle">ビルドインサイト</.localized_link>を使用して、Tuist ダッシュボードでタスクの実行時間とキャッシュの動作を追跡します。
- <.localized_link href="/guides/features/test-insights/gradle">テストインサイト</.localized_link>を使用して、テストのパフォーマンスを追跡し、不安定なテストを検出します。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不安定なテスト</.localized_link>を使用して、不安定なテストを自動的に検出、追跡、隔離します。
