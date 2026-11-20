---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続して、リモートビルドキャッシュの共有、CI 全体でのビルドおよびテストのインサイト、バンドルサイズの追跡、プレビューリンクを利用できます。"
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

以下の各セクションでは、現在不足している点を示し、そのギャップを埋める機能について説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を持つGradleプロジェクト。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradleプロジェクトのルートで `tuist init` を実行します。**Gradleプロジェクトを統合**を選択し、ブラウザで認証を行って、プロジェクトを所有すべきアカウントを選択します。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローではEnterキーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuistはリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を作成し、`plugins { ... }` ブロックを表示します。これを `settings.gradle.kts` の先頭に貼り付けます。

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` で動作確認を行います。Gradleがエラーなく読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべてオプションであり、独立しています。

## リモートビルドキャッシュ

Gradleのローカルビルドキャッシュは、タスクの出力を生み出したマシン上に保存されます。同じブランチ上の2人の開発者は、それぞれ独自の `~/.gradle` 内のキャッシュを利用しますが、互いのキャッシュは利用しません。また、CIはジョブごとに新規の空のキャッシュを利用します。

Tuistのリモートキャッシュは、Gradleがすでにマシン間で使用している同じキー/バリュープロトコルを拡張します。タスクの出力は、最初にそれを実行したマシンでアップロードされ、同じ入力に遭遇した他の誰でもダウンロードできます。`gradle.properties` で有効にします。

```properties
org.gradle.caching=true
```

次に、2つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードの **キャッシュ** を開いて、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradleはビルドの最後にタスクのタイミングを出力し、`--profile` を使用するとビルドごとのHTMLレポートを書き出します。いずれも実行をまたいで集計しません。一連のコミットを通じて遅くなったタスクは、どの単一ビルドのレポートでも以前と同じように見えます。

`dev.tuist` プラグインは、適用されるとすべてのビルドのタスクタイミングを自動的にダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後にダッシュボードの **ビルド** を開いて、傾向を確認してください。

## テストインサイト

Gradleのテストレポートは、`build/reports/tests/` 下にビルドごとに保存されます。10回のCI実行の中で断続的に失敗するテストは、どのレポートを見ても、偶然1回失敗した安定したテストのように見えます。

テストインサイトは、すべての `./gradlew test` 実行について、各タスクの結果と期間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、低速なテスト、および失敗は、ダッシュボードの **テスト** タブに表示されます。不安定さが増加した場合は、ダッシュボードから隔離して、マージをブロックしないようにします。

このプラグインは、ビルドが導入したテストケースを再実行し、マージされる前に不安定であることが判明したものをフラグ立てる **ストレステストモード** もサポートしています。これを `settings.gradle.kts` の `tuist` 拡張機能に追加します。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## コードカバレッジ

JaCoCoは、テストタスクごと、マシンごとにカバレッジレポートを書き出します。コミットのCIジョブのレポートを結合したり、ブランチのカバレッジが増減したかを示すものは何もありません。

このプラグインは、JaCoCoを使用してJVMおよびAndroidのユニットテストを測定し、各テスト実行とともにカバレッジをアップロードできます。Tuistは、シャードを含め、コミットの実行を1つの数値にまとめます。`settings.gradle.kts` の `tuist` 拡張機能で有効にします。

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

ダッシュボードの **コードカバレッジ** を開いて、コミットごとおよびファイルごとの状況を確認してください。CIでのコミットの完了とRobolectricの設定については、<.localized_link href="/guides/features/test-code-coverage/gradle">Gradleコードカバレッジ</.localized_link> を参照してください。

## バンドルインサイト

Android Gradle Pluginは、生成された `.aab` のサイズをビルド出力で報告します。この数値はブランチとともに消失し、リリース間でのサイズ比較は手動の管理作業となります。Play Consoleも同じ数値を報告しますが、アーティファクトがアップロードされた後のみです。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールサイズとダウンロードサイズを記録し、ブランチごとのしきい値を超えた場合にPRチェックを失敗させることができます。これをビルドステップの直後にCIに追加します。

```bash
tuist inspect bundle App.aab
```

ダッシュボードの **バンドルインサイト → Android** を開いて、傾向を確認し、しきい値を設定してください。

## プレビュー

Play Consoleの内部テストトラックでは、共有ごとにレビューおよび反映の遅延が発生します。生の `.apk` をSlackやメールで送信する方が速いですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

このプラグインは、別のCLIアップロードなしでアプリケーションバリアントを直接ビルドおよび公開できます。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` タスクをリクエストすると、その呼び出しが公開対象になります。通常のビルドではプレビューはアップロードされません。サポートされているAPK、署名、およびインストールについては、<.localized_link href="/guides/features/previews/gradle">Gradleプレビュー</.localized_link> を参照してください。

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストはすべて、プロジェクトに接続されている人数に応じて効果が増大します。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリック一回で完了できるようにします。

CIでは、個人用ログインを使用しないでください。CIプロバイダーのOIDCアイデンティティで認証するか、ダッシュボードで **CI** プリセットを使用してアカウントトークンを作成し、それを `TUIST_TOKEN` として設定してください。<.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradleプラグイン認証</.localized_link> を参照してください。

## プラグインのリファレンス全体

ここで説明した内容は、GradleプロジェクトでTuistの価値を得るための最小限の手順です。`tuist`拡張ブロック、`stressNewTests`モード、およびCI認証の設定オプションについては、[Gradleプラグインのインストール](https://tuist.dev/en/docs/guides/install-gradle-plugin)のリファレンスを参照してください。
