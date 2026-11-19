---
{
  "title": "Gradle プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "Gradle プロジェクトを Tuist に接続し、リモートビルドキャッシュの共有、CI 全体でのビルド・テスト分析、バンドルサイズ追跡、プレビューリンクを利用しましょう。"
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

以下の各セクションでは、まず現状で不足している点を示し、そのギャップを埋める機能について順に説明します。

## 前提条件

- `settings.gradle.kts`（または `settings.gradle`）を持つ Gradle プロジェクト。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

Gradle プロジェクトのルートから `tuist init` を実行します。**Integrate a Gradle project** を選択し、ブラウザで認証を行って、プロジェクトを所有するアカウントを選択してください。

```bash
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行します（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist はリポジトリのルートにプロジェクトハンドルを含む `tuist.toml` を書き込み、`plugins { ... }` ブロックを表示します。これを `settings.gradle.kts` の先頭に貼り付けてください。

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help` で動作確認を行います。Gradle がエラーなく読み込まれるはずです。プラグインが見つからない場合は、ブロックが `build.gradle.kts` ではなく `settings.gradle.kts` にあることを確認してください。

以下はすべて任意であり、独立しています。

## リモートビルドキャッシュ

Gradle のローカルビルドキャッシュは、タスクの出力を生み出したマシン上に保存されます。同じブランチ上の二人の開発者は、それぞれ自身の `~/.gradle` でキャッシュにヒットし、互いのキャッシュは利用しません。また、CI はジョブごとに新規で空のキャッシュにヒットします。

Tuist のリモートキャッシュは、Gradle がすでにマシン間で使用しているキー/バリュープロトコルを拡張します。タスクの出力は、最初に実行したマシンでアップロードされ、同じ入力に遭遇した他の任何人都ダウンロードできます。`gradle.properties` で有効化してください。

```properties
org.gradle.caching=true
```

次に、二つの環境でビルドします。

```bash
./gradlew clean build --build-cache --info
```

キャッシュ可能なタスクは、2 回目の実行時に `FROM-CACHE` と報告されます。ダッシュボードで **Cache** を開き、時間経過に伴うヒット率を確認してください。

## ビルドインサイト

Gradle はビルド終了時にタスクのタイミングを出力し、`--profile` を使用するとビルドごとの HTML レポートを書き出します。いずれも実行をまたいで集計しません。一連のコミットを通じて遅くなってきたタスクも、単一のビルドレポート上では従来と同じように見えます。

`dev.tuist` プラグインは、適用されると自動的にすべてのビルドのタスクタイミングをダッシュボードにアップロードします。追加の設定は不要です。次の `./gradlew build` の後、ダッシュボードで **Builds** を開いて傾向を確認してください。

## テストインサイト

Gradle のテストレポートは、ビルドごとに `build/reports/tests/` の下に保存されます。10 回の CI 実行で断続的に失敗するテストも、特定のレポート上では一度だけ偶然失敗した安定したテストのように見えます。

テストインサイトは、すべての `./gradlew test` 実行における各タスクの結果と持続時間を記録し、実行をまたいで結果を相関付けます。不安定なテスト、遅いテスト、および失敗は、ダッシュボードの **Tests** タブに表示されます。不安定性が蓄積された場合は、ダッシュボードから隔離して、マージをブロックしないようにしてください。

このプラグインは、ビルドが導入したテストケースを再実行し、マージされる前に不安定であることが判明したものをフラグ立てする **ストレステストモード** もサポートしています。`settings.gradle.kts` の `tuist` 拡張機能に以下を追加してください。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## バンドルインサイト

Android Gradle Plugin は、生成された `.aab` のサイズをビルド出力で報告します。この数値はブランチとともに消失し、リリース間のサイズ比較は手動での帳合作業となります。Play Console も同じ数値を報告しますが、アーティファクトがアップロードされた後に限ります。

バンドルインサイトは、すべての `.aab`（推奨）または `.apk` のインストールおよびダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加してください。

```bash
tuist inspect bundle App.aab
```

ダッシュボードで **Bundle insights → Android** を開き、傾向を確認して閾値を設定してください。

## プレビュー

Play Console の内部テストトラックでは、共有ごとにレビューおよび反映の遅延が発生します。生の `.apk` を Slack やメールで送信する方が高速ですが、特定のメッセージがどのビルドを指しているかの追跡が失われます。

このプラグインは、別途 CLI アップロードを行うことなく、アプリケーションバリアントを直接ビルドして公開できます。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` タスクをリクエストすると、その呼び出しが公開対象になります。通常のビルドではプレビューがアップロードされることはありません。サポートされている APK、署名、およびインストールについては、<.localized_link href="/guides/features/previews/gradle">Gradle previews</.localized_link> を参照してください。

## チームを巻き込む

キャッシュヒット、インサイト、およびストレステストの効果は、プロジェクトに接続されている人数に応じて増幅されます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくワンクリックで完了できるようにしてください。

CI では個人ログインを使用しないでください。CI プロバイダーの OIDC アイデンティティで認証するか、ダッシュボードで **CI** プリセットを使用してアカウントトークンを作成し、`TUIST_TOKEN` として設定してください。<.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle プラグインの認証</.localized_link> を参照してください。

## プラグインリファレンス全体

ここで説明した内容は、Gradle プロジェクトで Tuist の価値を得るための最小限の手順です。`tuist` 拡張ブロック、`stressNewTests` モード、および CI 認証の設定オプションについては、[Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) リファレンスを参照してください。
