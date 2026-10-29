---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Gradle プロジェクト {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

既存の Gradle プロジェクトを Tuist に向けるには、この手順に従ってください。`dev.tuist` Gradle プラグインは、Gradle のローカルビルドキャッシュを Tuist のリモートキャッシュに接続し、`./gradlew` コマンドを一切変更することなく、ビルドおよびテストデータをダッシュボードにアップロードします。

以下の各セクションでは、まず現在不足している部分を説明し、そのギャップを埋める機能について順を追って解説します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を備えた Gradle プロジェクト。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradle プロジェクトのルートから `tuist init` を実行します。**Gradle プロジェクトを統合** を選択し、ブラウザで認証を行って、プロジェクトを所有すべきアカウントを選択します。

```bash
tuist init
```

コーディングエージェントやスクリプトからこれを実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist はリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を書き込み、`plugins { ... }` ブロックを出力します。これを `settings.gradle.kts` の先頭に貼り付けます。

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

`./gradlew help` で動作確認を行います。Gradle がエラーなしで読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべてオプションであり、独立しています。

## リモートビルドキャッシュ

Gradle のローカルビルドキャッシュは、タスクの出力を生み出したマシン上に保存されます。同じブランチ上の 2 人の開発者は、各自の `~/.gradle` 内のキャッシュにはヒットしますが、互いのキャッシュにはヒットしません。また、CI はジョブごとに新規で空のキャッシュにヒットします。

Tuist のリモートキャッシュは、Gradle がすでにマシン間で使用している同じキー/バリュープロトコルを拡張します。タスクの出力は、最初にそれを実行したマシンでアップロードされ、同じ入力に遭遇した他の誰かによってダウンロードされます。`gradle.properties` で有効にします。

```properties
org.gradle.caching=true
```

次に、2 つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2 回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードの **Cache** を開いて、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradle はビルド終了時にタスクのタイミングを出力し、`--profile` を使用するとビルドごとの HTML レポートを書き出します。どちらの実行も、複数回の実行を集約しません。一連のコミットを通じて遅くなってきたタスクは、どの単一ビルドのレポートでも以前と同じように見えます。

`dev.tuist` プラグインは、プラグインが適用されると、すべてのビルドのタスクタイミングを自動的にダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後、ダッシュボードの **Builds** を開いて傾向を確認してください。

## テストインサイト

Gradle のテストレポートは、`build/reports/tests/` 以下にビルドごとに存在します。10 回の CI 実行で断続的に失敗するテストは、任意のレポートでは、一度だけ失敗した安定したテストのように見えます。

テストインサイトは、すべての `./gradlew test` 実行における各タスクの結果と持続時間を記録し、実行間の結果を相関付けます。不安定なテスト、低速なテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定なテストが蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにします。

このプラグインは、ビルドが導入したテストケースを再実行し、マージ前に不安定であることが判明したものをフラグ付けする **ストレステストモード** もサポートしています。これを `settings.gradle.kts` の `tuist` 拡張機能に追加します。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルインサイト

Android Gradle Plugin は、ビルド出力で生成された `.aab` のサイズを報告します。その数値はブランチとともに消失し、リリース間でのサイズ比較は手動の帳簿作業となります。Play Console も同じ数値を報告しますが、アーティファクトがアップロードされた後に限られます。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。これをビルドステップの直後に CI に追加します。

```bash
tuist inspect bundle App.aab
```

ダッシュボードの **Bundle insights → Android** を開いて、傾向を確認し、閾値を設定します。

## プレビュー

Play Console の内部テストトラックは、共有ごとにレビューおよび伝播の遅延を追加します。生の `.apk` を Slack やメールで送信する方が速いですが、特定のメッセージがどのビルドを指しているかの追跡ができなくなります。

プレビューは、ビルドを受信者が 1 つのコマンドでインストールできる共有可能なリンクに変換します。

```bash
tuist share App.apk
```

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストは、プロジェクトに接続されている人数が増えるにつれて複合的に効果を発揮します。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリック一回で完了できるようにします。

CI では、個人用ログインを使用しないでください。プロジェクトにスコープを限定した `TUIST_TOKEN` を設定してください（ダッシュボードのプロジェクト設定から作成します）。

## プラグインリファレンス全体

ここで説明した内容はすべて、Gradle プロジェクトで Tuist から価値を引き出すための最小限の要件です。`tuist` 拡張ブロック、`stressNewTests` モード、および CI 認証の構成オプションについては、[Gradle プラグインをインストール](https://tuist.dev/en/docs/guides/install-gradle-plugin) リファレンスを参照してください。
