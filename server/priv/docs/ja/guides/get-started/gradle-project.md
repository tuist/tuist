---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続して、リモートビルドキャッシュの共有、CI 全体でのビルド・テスト分析、バンドルサイズの追跡、プレビューリンクを利用しましょう。"
}
---
# Gradleプロジェクト {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

既存のGradleプロジェクトをTuistに接続するには、この手順に従ってください。`dev.tuist` Gradleプラグインは、GradleのローカルビルドキャッシュをTuistのリモートキャッシュに接続し、`./gradlew` コマンドを一切変更することなく、ビルドおよびテストデータをダッシュボードにアップロードします。

以下の各セクションでは、まず現在不足しているものを示し、そのギャップを埋める機能について説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を持つGradleプロジェクト。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradleプロジェクトのルートで `tuist init` を実行します。**Gradleプロジェクトを統合**を選択し、ブラウザで認証して、プロジェクトを所有するアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行し（ブラウザフローでEnterキーを押すまで待機します）、その後、非インタラクティブな形式を使用してください。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuistはリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を作成し、`plugins { ... }` ブロックを表示します。これを `settings.gradle.kts` の先頭に貼り付けてください。

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

`./gradlew help` で動作確認を行います。Gradleはエラーなしで読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべて任意であり、独立しています。

## リモートビルドキャッシュ

Gradleのローカルビルドキャッシュは、タスクの出力を生成したマシン上に保存します。同じブランチ上の2人の開発者は、それぞれ自身の `~/.gradle` でキャッシュにヒットしますが、互いのキャッシュにはヒットしません。また、CIはジョブごとに新規で空のキャッシュにヒットします。

Tuistのリモートキャッシュは、Gradleがすでにマシン間で使用している同じキー/値プロトコルを拡張します。タスクの出力は、最初に実行したマシンでアップロードされ、同じ入力に遭遇した他のユーザーによってダウンロードされます。`gradle.properties` で有効にしてください。

```properties
org.gradle.caching=true
```

次に、2つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードの **Cache** を開いて、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradleはビルド終了時にタスクのタイミングを出力し、`--profile` を使用するとビルドごとのHTMLレポートを作成します。いずれも実行をまたいで集計しません。一連のコミットを通じて遅くなってきたタスクは、どの単一ビルドのレポートでも以前と同じように見えます。

`dev.tuist` プラグインは、適用されると自動的にすべてのビルドのタスクタイミングをダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後、ダッシュボードの **Builds** を開いて傾向を確認してください。

## テストインサイト

Gradleのテストレポートは、ビルドごとに `build/reports/tests/` に保存されます。10回のCI実行で断続的に失敗するテストは、どのレポートを見ても、偶然1回失敗した安定したテストのように見えます。

テストインサイトは、`./gradlew test` 実行ごとにすべてのタスクの結果と持続時間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、低速なテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定さが蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにしてください。

このプラグインは、ビルドが導入したテストケースを再実行し、マージ前に不安定であることが判明したものをフラグ付けする **ストレステストモード** もサポートしています。`settings.gradle.kts` の `tuist` 拡張機能に追加してください。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルインサイト

Android Gradle Pluginは、ビルド出力で生成された `.aab` のサイズを報告します。この数値はブランチとともに消え、リリース間でのサイズ比較は手動の会計作業となります。Play Consoleも同じ数値を報告しますが、アーティファクトがアップロードされた後に限ります。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールおよびダウンロードサイズを記録し、ブランチごとの閾値を超えた場合にPRチェックを失敗させることができます。ビルドステップの直後にこれをCIに追加してください。

```bash
tuist inspect bundle App.aab
```

ダッシュボードの **Bundle insights → Android** を開いて、傾向を確認し、閾値を設定してください。

## プレビュー

Play Consoleの内部テストトラックは、共有ごとにレビューおよび伝播の遅延を追加します。生の `.apk` をSlackやメールで送信する方が高速ですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

このプラグインは、別のCLIアップロードなしでアプリケーションバリアントを直接ビルドおよび公開できます。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` タスクをリクエストすると、その呼び出しが公開対象になります。通常のビルドはプレビューをアップロードしません。サポートされているAPK、署名、およびインストールについては、<.localized_link href="/guides/features/previews/gradle">Gradleプレビュー</.localized_link> を参照してください。

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストはすべて、プロジェクトに接続されている人数に応じて複合的に効果が高まります。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリック一回で完了できるようにしてください。

CIでは、個人用ログインを使用しないでください。プロジェクトにスコープを限定した `TUIST_TOKEN` を設定してください（ダッシュボードのプロジェクト設定から作成します）。

## プラグインリファレンス全体

ここで説明した内容はすべて、GradleプロジェクトでTuistの価値を得るための最小限の手順です。`tuist` 拡張ブロック、`stressNewTests` モード、およびCI認証の構成オプションについては、[Gradleプラグインをインストール](https://tuist.dev/en/docs/guides/install-gradle-plugin) リファレンスを参照してください。
