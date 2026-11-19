---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続して、リモートビルドキャッシュの共有、CI 全体でのビルドおよびテストのインサイト、バンドルサイズの追跡、プレビューリンクを利用しましょう。"
}
---
# Gradle プロジェクト {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

既存の Gradle プロジェクトを Tuist 向けに設定するには、この手順に従ってください。`dev.tuist` Gradle プラグインは、Gradle のローカルビルドキャッシュを Tuist のリモートキャッシュに接続し、`./gradlew` コマンドを一切変更することなく、ビルドおよびテストデータをダッシュボードにアップロードします。

以下の各セクションでは、現在不足している部分を最初に示し、そのギャップを埋める機能の手順を説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を持つ Gradle プロジェクト。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradle プロジェクトのルートで `tuist init` を実行します。**Integrate a Gradle project** を選択し、ブラウザで認証を行って、プロジェクトを所有するアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist はリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を書き込み、`plugins { ... }` ブロックを表示します。これを `settings.gradle.kts` の先頭に貼り付けてください。

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` で動作確認を行います。Gradle がエラーなしで読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべて任意であり、独立しています。

## リモートビルドキャッシュ

Gradle のローカルビルドキャッシュは、タスクの出力を生成したマシン上に保存されます。同じブランチ上の 2 人の開発者は、それぞれ独自の `~/.gradle` 内のキャッシュを利用しますが、互いのキャッシュは利用しません。また、CI はジョブごとに空の新しいキャッシュから開始します。

Tuist のリモートキャッシュは、Gradle がすでにマシン間で使用している同じキー/バリュープロトコルを拡張します。タスクの出力は、最初に実行したマシンでアップロードされ、同じ入力に遭遇した他の任何人都ダウンロードできます。`gradle.properties` で有効にしてください。

```properties
org.gradle.caching=true
```

次に、2 つの環境でビルドを実行します。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2 回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードの **Cache** を開いて、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradle はビルド終了時にタスクの実行時間を出力し、`--profile` を使用するとビルドごとの HTML レポートを書き出します。いずれも実行をまたいで集計しません。一連のコミットを通じて遅くなってきたタスクも、単一のビルドレポート上では従来と同じように見えます。

`dev.tuist` プラグインは、適用されるとすべてのビルドのタスク実行時間を自動的にダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後にダッシュボードの **Builds** を開いて、傾向を確認してください。

## テストインサイト

Gradle のテストレポートは、`build/reports/tests/` 以下にビルドごとに保存されます。10 回の CI 実行で断続的に失敗するテストも、個々のレポート上では一度だけ失敗した安定したテストのように見えます。

テストインサイトは、`./gradlew test` 実行ごとに各タスクの結果と継続時間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、低速なテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定なテストが蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにしてください。

このプラグインは、ビルドで導入されたテストケースを再実行し、マージ前に不安定性を示すものをフラグ付けする **ストレステストモード** もサポートしています。`settings.gradle.kts` の `tuist` 拡張機能に以下を追加してください。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルインサイト

Android Gradle Plugin は、生成された `.aab` のサイズをビルド出力で報告します。この数値はブランチとともに消失し、リリース間でのサイズ比較は手動での管理作業となります。Play Console でも同じ数値を報告しますが、アーティファクトがアップロードされた後に限られます。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加してください。

```bash
tuist inspect bundle App.aab
```

ダッシュボードの **Bundle insights → Android** を開いて、傾向を確認し、閾値を設定してください。

## プレビュー

Play Console の内部テストトラックでは、共有ごとにレビューと反映の遅延が発生します。生の `.apk` を Slack やメールで送信する方が高速ですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

このプラグインは、別の CLI アップロードなしでアプリケーションバリアントを直接ビルドおよび公開できます。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` タスクをリクエストすると、その呼び出しが公開対象になります。通常のビルドではプレビューはアップロードされません。サポートされている APK、署名、およびインストールについては、<.localized_link href="/guides/features/previews/gradle">Gradle previews</.localized_link> を参照してください。

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストの効果は、プロジェクトに接続されている人数に応じて増大します。ダッシュボードのアカウント設定からチームメンバーを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリック操作で完了できるようにしてください。

CI では個人ログインを使用しないでください。CI プロバイダーの OIDC アイデンティティで認証するか、ダッシュボードの **CI** プリセットでアカウントトークンを作成し、`TUIST_TOKEN` として設定してください。<.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle plugin authentication</.localized_link> を参照してください。

## プラグインのリファレンス全体

ここで説明した内容は、Gradle プロジェクトで Tuist の価値を得るための最小限の設定です。`tuist` 拡張ブロック、`stressNewTests` モード、および CI 認証の構成オプションは、[Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) リファレンスに記載されています。
