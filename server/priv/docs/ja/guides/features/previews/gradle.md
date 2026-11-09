---
{
  "title": "Gradle プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist Previews を使用して、Gradle プロジェクトから Android アプリやネイティブなコマンドラインツールをビルドし、共有します。"
}
---
# Gradle プレビュー

Android アプリとネイティブのコマンドラインツールを Gradle から直接ビルドして共有します。プロジェクトの接続と認証を行うには、<.localized_link href="/guides/get-started/gradle-project">Gradle プロジェクトガイド</.localized_link>から始めてください。

## Android アプリ

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 設定プラグインは、Android Gradle Plugin（8.8.2 以降）の各アプリケーションバリアントに対して `tuistShare<Variant>` タスクを登録します。`app` と `Debug` を各自のアプリケーションモジュールとバリアントに置き換えてください。例えば、プロダクトフレーバーの場合は `:app:tuistShareDemoDebug` のようになります。このタスクは、APK を公開する前に Gradle で宣言されたアーティファクト依存関係を通じて APK をビルドします。ビルド出力が最新の状態である場合や、ビルドキャッシュから復元された場合にも動作します。

署名付きの単一かつユニバーサルなアプリケーション APK のみがサポートされます。Android のデバッグバリアントは通常、デバッグ用署名鍵を使用します。リリースバリアントでは独自の署名設定が必要です。このタスクは、認証またはアップロードの前に APK の署名を検証します。未署名、無効、インストゥルメンテーション、分割 APK は拒否されます。ライブラリモジュール、テスト APK、Android App Bundle（`.aab`）は公開対象ではありません。

## ネイティブのコマンドラインツール

Gradle の `cpp-application` または `swift-application` プラグインを使用するプロジェクトでは、各ネイティブバイナリに対して共有タスクが用意されます。

```bash
./gradlew :app:tuistShareMainDebug
```

このタスクは、ランチャーとランタイムライブラリを含むインストール済みディストリビューションをビルドしてパッケージ化します。リリースバイナリには `tuistShareMainRelease` を使用してください。複数のマシンを対象とするプロジェクトでは、バイナリごとにタスクが用意されています。`./gradlew :app:tasks --all` を実行して名前を確認してください。

arm64 または x86_64 向けのネイティブ macOS および Linux 実行ファイルがサポートされます。Gradle プラグインが必要とするツールチェーンを使用して、ターゲットプラットフォーム上でビルドしてください。JVM アプリケーションとその生成されたランチャースクリプトは、この統合ではサポートされません。

## 公開の動作

共有タスクは、Tuist CLI を呼び出さずに、プラグインの既存の Tuist 認証情報を使用して公開を行います。通常の `assemble`、`build`、およびテストタスクはプレビューを公開しません。

共有後、プロジェクトで **プレビュー** を開いてリンクをコピーしてください。同じビルドとトラックでの共有を繰り返すと、ビルドキャッシュヒット後を含め、その公開が再利用されます。アップロードに失敗した場合や確認されない場合は共有タスクが失敗し、成功したプレビューとして報告されることはありません。

## CI とトラック

プラグインの他の認証機能で使用しているのと同じ認証情報で <.localized_link href="/guides/integrations/continuous-integration">CI 認証</.localized_link> を構成し、明示的に公開をリクエストします。

```bash
./gradlew :app:tuistShareDebug --track nightly
```

同様に、ネイティブ共有タスクに `--track nightly` を追加します。タスクは構成済みの Tuist プロジェクト、サーバー URL、およびプロキシ設定を使用します。プレビューの公開には常に認証が必要です。Git リビジョンメタデータ、リリースノート、自動プルリクエストコメントは、これらのタスクによって添付されません。

ホスト型 Tuist では、アーティファクトの公開は 30 日後に期限切れになります。セルフホスト型インスタンスでは `TUIST_APP_PREVIEW_RETENTION_DAYS` を使用します。これを未設定のままにすると、このファミリーの有効期限が無効になります。期限切れの公開は、同じ意図を繰り返しても復活させることはできません。

## 既存の APK を共有する

このワークフロー外でビルドされた APK の場合、またはレガシーなアップロードフローでリリースノートを含める場合には、CLI が引き続き利用可能です。

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

公開済みビルドの実行、アクセス、トラック、README バッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行する</.localized_link>を参照してください。

<!-- @snippet: ./_tuist-share -->
