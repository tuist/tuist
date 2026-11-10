---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続して、共有のリモートビルドキャッシュ、CI 全体でのビルドとテストのインサイト、バンドルサイズの追跡、プレビューリンクを利用しましょう。"
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

以下の各セクションでは、現在不足している部分を最初に示し、そのギャップを埋める機能について説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を含む Gradle プロジェクト。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradle プロジェクトのルートで `tuist init` を実行します。\*\***Gradle プロジェクトを統合**\*\*を選択し、ブラウザで認証を行って、プロジェクトを所有するアカウントを選択します。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist はリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を作成し、`plugins { ... }` ブロックを出力します。これを `settings.gradle.kts` の先頭に貼り付けます。

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` で動作確認を行います。Gradle がエラーなしで読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべてオプションであり、独立しています。

## リモートビルドキャッシュ

Gradle のローカルビルドキャッシュは、タスクの出力を生成したマシン上に保存します。同じブランチ上の 2 人の開発者は、各自の `~/.gradle` 内のキャッシュにはヒットしますが、お互いのキャッシュにはヒットしません。また、CI はジョブごとに新しく空のキャッシュにアクセスします。

Tuist のリモートキャッシュは、Gradle がすでにマシン間で使用している同じキー/バリュープロトコルを拡張します。タスクの出力は、最初に実行したマシンでアップロードされ、同じ入力に遭遇した他のユーザーによってダウンロードされます。`gradle.properties` で有効にします。

```properties
org.gradle.caching=true
```

次に、2 つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2 回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードで **Cache** を開き、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradle はビルドの終了時にタスクのタイミングを出力し、`--profile` を使用するとビルドごとの HTML レポートを作成します。どちらの場合も、実行をまたいだ集計は行われません。一連のコミットを通じて遅くなっているタスクも、単一のビルドレポート上では以前と同じように見えます。

`dev.tuist` プラグインは、適用されると自動的にすべてのビルドのタスクタイミングをダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後にダッシュボードで **Builds** を開き、傾向を確認してください。

## テストインサイト

Gradle のテストレポートは、ビルドごとに `build/reports/tests/` 以下に保存されます。10 回の CI 実行で断続的に失敗するテストも、特定のレポート上では一度だけ失敗した安定したテストのように見えます。

テストインサイトは、`./gradlew test` 実行ごとのすべてのタスクの結果と期間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、遅いテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定さが蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにします。

このプラグインは、ビルドが導入したテストケースを再実行し、マージされる前に不安定であることが判明したものをフラグ付けする **ストレステストモード** もサポートしています。`settings.gradle.kts` の `tuist` 拡張機能に追加します。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルインサイト

Android Gradle Plugin は、ビルド出力で生成された `.aab` のサイズを報告します。この数値はブランチとともに消失し、リリース間でのサイズ比較は手動の管理作業となります。Play Console も同じ数値を報告しますが、アーティファクトがアップロードされた後に限られます。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加します。

```bash
tuist inspect bundle App.aab
```

ダッシュボードで **Bundle insights → Android** を開き、傾向を確認して閾値を設定します。

## プレビュー

Play Console の内部テストトラックでは、共有ごとにレビューおよび伝播の遅延が発生します。生の `.apk` を Slack やメールで送信する方が高速ですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

このプラグインは、別途 CLI でアップロードすることなく、アプリケーションバリアントを直接ビルドおよび公開できます。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` タスクをリクエストすると、その呼び出しが公開対象になります。通常のビルドではプレビューはアップロードされません。サポートされている APK、署名、およびインストールについては、<.localized_link href="/guides/features/previews/gradle">Gradle プレビュー</.localized_link> を参照してください。

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストの効果は、プロジェクトに接続されている人数に応じて増大します。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくワンクリックで完了できるようにします。

CI では個人ログインを使用しないでください。CI プロバイダーの OIDC アイデンティティで認証するか、ダッシュボードで **CI** プリセットを使用してアカウントトークンを作成し、`TUIST_TOKEN` として設定します。<.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle プラグイン認証</.localized_link> を参照してください。

## プラグインリファレンス全文

ここで説明した内容はすべて、Gradle プロジェクトで Tuist から価値を引き出すための最小限の手順です。`tuist` 拡張ブロック、`stressNewTests` モード、および CI 認証の設定オプションについては、[Gradle プラグインのインストール](https://tuist.dev/en/docs/guides/install-gradle-plugin) リファレンスを参照してください。
