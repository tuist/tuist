---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続し、リモートビルドキャッシュの共有、CI 全体でのビルドおよびテストの分析、バンドルサイズの追跡、プレビューリンクを利用しましょう。"
}
---
# Gradle プロジェクト {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

既存の Gradle プロジェクトを Tuist に接続するには、この手順に従ってください。`dev.tuist` Gradle プラグインは、Gradle のローカルビルドキャッシュを Tuist のリモートキャッシュに接続し、`./gradlew` コマンドを一切変更することなく、ビルドおよびテストデータをダッシュボードにアップロードします。

以下の各セクションでは、まず現状で不足している点を示し、そのギャップを埋める機能について説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を含む Gradle プロジェクト。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradle プロジェクトのルートで `tuist init` を実行します。**Gradle プロジェクトを統合** を選択し、ブラウザで認証を行って、プロジェクトを所有するアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist はリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を作成し、`plugins { ... }` ブロックを表示します。これを `settings.gradle.kts` の先頭に貼り付けてください。

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

`./gradlew help` で動作確認を行います。Gradle がエラーなしで読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべて任意であり、独立しています。

## リモートビルドキャッシュ

Gradle のローカルビルドキャッシュは、タスクの出力を生成したマシン上に保存されます。同じブランチ上の 2 人の開発者は、各自の `~/.gradle` 内のキャッシュを利用しますが、互いのキャッシュは利用しません。また、CI はジョブごとに新しい空のキャッシュを利用します。

Tuist のリモートキャッシュは、Gradle がすでにマシン間で使用している同じキー/バリュープロトコルを拡張します。タスクの出力は、最初に実行したマシンでアップロードされ、同じ入力に遭遇した他の任何人によってダウンロードされます。`gradle.properties` で有効にしてください。

```properties
org.gradle.caching=true
```

次に、2 つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2 回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードの **Cache** を開き、時間経過に伴うヒット率を確認してください。

## ビルドの洞察

Gradle はビルドの最後にタスクのタイミングを出力し、`--profile` を使用するとビルドごとの HTML レポートを書き出します。いずれも実行をまたいで集計されません。一連のコミットを通じて遅くなったタスクは、どの単一ビルドのレポートでも以前と同じように見えます。

`dev.tuist` プラグインは、適用されると自動的にすべてのビルドのタスクタイミングをダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後にダッシュボードの **Builds** を開き、傾向を確認してください。

## テストの洞察

Gradle のテストレポートは、`build/reports/tests/` の下にビルドごとに保存されます。10 回の CI 実行で断続的に失敗するテストは、どのレポートを見ても、一度だけ失敗した安定したテストのように見えます。

テストの洞察は、すべての `./gradlew test` 実行について、すべてのタスクの結果と持続時間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、遅いテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定なテストが蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにしてください。

このプラグインは、ビルドで導入されたテストケースを再実行し、マージ前に不安定であることが判明したものをフラグ付けする **ストレステストモード** もサポートしています。`settings.gradle.kts` の `tuist` 拡張機能に追加してください。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルの洞察

Android Gradle Plugin は、生成された `.aab` のサイズをビルド出力で報告します。この数値はブランチとともに消失し、リリース間のサイズ比較は手動での集計作業となります。Play Console も同じ数値を報告しますが、アーティファクトがアップロードされた後に限られます。

バンドルの洞察は、すべての `.aab`（推奨）または `.apk` のインストールおよびダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加してください。

```bash
tuist inspect bundle App.aab
```

ダッシュボードの **Bundle insights → Android** を開き、傾向を確認して閾値を設定してください。

## プレビュー

Play Console の内部テストトラックでは、共有ごとにレビューおよび伝播の遅延が発生します。生の `.apk` を Slack やメールで送信する方が速いですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

プレビューは、ビルドを受信者が 1 つのコマンドでインストールできる共有リンクに変換します。

```bash
tuist share App.apk
```

## チームを巻き込む

キャッシュヒット、洞察、およびストレステストは、プロジェクトに接続されている人数が増えるほど効果が高まります。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリックだけで完了できるようにしてください。

CI では個人ログインを使用しないでください。プロジェクトにスコープを限定した `TUIST_TOKEN` を設定してください（ダッシュボードのプロジェクト設定から作成できます）。

## プラグインのリファレンス全体

ここで説明した内容は、Gradle プロジェクトで Tuist から価値を引き出すための最小限の内容です。`tuist` 拡張ブロック、`stressNewTests` モード、および CI 認証の構成オプションについては、[Gradle プラグインをインストール](https://tuist.dev/en/docs/guides/install-gradle-plugin) のリファレンスを参照してください。
