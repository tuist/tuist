---
{
  "title": "Gradle プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist Previews を使用して、Gradle プロジェクトから Android アプリやネイティブのコマンドラインツールをビルドし、共有します。"
}
---
# Gradle プレビュー

Android アプリとネイティブのコマンドラインツールを Gradle から直接ビルドして共有します。まずは <.localized_link href="/guides/get-started/gradle-project">Gradle プロジェクトガイド</.localized_link> を参照し、プロジェクトの接続と認証を行ってください。

## Android アプリ

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 設定プラグインは、Android Gradle Plugin（8.8.2 以降）の各アプリケーションバリアントに対して `tuistShare<Variant>` タスクを登録します。`app` と `Debug` は、お使いのアプリケーションモジュールとバリアントに置き換えてください。例えば、プロダクトフレーバーの場合は `:app:tuistShareDemoDebug` のようになります。このタスクは、公開前に Gradle で宣言されたアーティファクトの依存関係を通じて APK をビルドします。ビルド出力が最新の状態である場合や、ビルドキャッシュから復元された場合にも動作します。

署名付きの単一のユニバーサルなアプリケーション APK だけがサポートされています。Android のデバッグバリアントは通常、デバッグ用署名鍵を使用します。リリースバリアントでは、独自の署名設定が必要です。このタスクは、認証やアップロードの前に APK の署名を検証します。署名なし、不正、インストゥルメンテーション、分割 APK は拒否されます。ライブラリモジュール、テスト APK、Android App Bundle（`.aab`）は公開対象ではありません。

## ネイティブのコマンドラインツール

Gradle の `cpp-application` または `swift-application` プラグインを使用するプロジェクトでは、各ネイティブバイナリに対して共有タスクが利用できます：

```bash
./gradlew :app:tuistShareMainDebug
```

このタスクは、ランチャーと実行時ライブラリを含むインストール済みディストリビューションをビルドしてパッケージ化します。リリースバイナリには `tuistShareMainRelease` を使用してください。複数のマシンを対象とするプロジェクトでは、バイナリごとにタスクが用意されています。名前を確認するには `./gradlew :app:tasks --all` を実行してください。

arm64 または x86_64 向けのネイティブ macOS および Linux 実行ファイルがサポートされています。Gradle プラグインで必要なツールチェーンを使用して、ターゲットプラットフォーム上でビルドしてください。JVM アプリケーションとその生成されたランチャースクリプトは、この統合ではサポートされていません。

## 公開の動作

共有タスクは、Tuist CLI を呼び出さずに、プラグインの既存の Tuist 認証情報を使用して公開します。通常の `assemble`、`build`、およびテストタスクはプレビューを公開しません。

共有後、プロジェクトで **プレビュー** を開いてリンクをコピーしてください。同じビルドとトラックでの共有を繰り返すと、ビルドキャッシュヒット後を含め、その公開が再利用されます。アップロードに失敗した場合や確認されない場合は、共有タスクが失敗します。これらは成功したプレビューとして報告されません。

## CI とトラック

プラグインの他の認証が必要な機能で使用しているのと同じ認証情報で <.localized_link href="/guides/integrations/continuous-integration">CI 認証</.localized_link> を設定し、明示的に公開をリクエストしてください：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ネイティブの共有タスクにも同様に `--track nightly` を追加してください。タスクは、設定された Tuist プロジェクト、サーバー URL、およびプロキシ設定を使用します。プレビューの公開には常に認証が必要です。Git リビジョンのメタデータ、リリースノート、自動プルリクエストコメントは、これらのタスクによって付加されません。

ホストされた Tuist では、アーティファクトの公開は 30 日後に期限切れになります。セルフホストインスタンスでは `TUIST_APP_PREVIEW_RETENTION_DAYS` を使用します。これを未設定にすると、このファミリーの有効期限が無効になります。期限切れになった公開は、同じ意図を繰り返しても復活させることはできません。

## 既存の APK を共有する

このワークフローの外でビルドされた APK の場合、またはレガシーなアップロードフローでリリースノートを含める場合は、CLI が引き続き利用できます：

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

公開されたビルドの実行、アクセス、トラック、README バッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行</.localized_link> を参照してください。

<!-- @snippet: ./_tuist-share -->
