---
{
  "title": "Bazel プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Bazel から Android アプリ、Apple アプリ、およびコマンドラインツールをプレビューとして公開します。"
}
---
# Bazel プレビュー

既存の Bazel ターゲットから、Android APK、Apple シミュレーターおよび macOS アプリ、コマンドラインツールを公開します。共有したい出力ごとにプレビューターゲットを追加してください。通常のビルドは変更されません。

## セットアップ

[`rules_tuist` from the Tuist repository](https://github.com/tuist/tuist/tree/main/bazel) を `MODULE.bazel` に追加し、使用するコミットを固定します:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

既存のアプリケーションターゲット、ネイティブ SDK、署名設定はそのままにしてください。公開ツールは Bazel が提供します。

Bazel から直接サインインします:

```bash
bazel run @rules_tuist//:login
```

これにより、Tuist CLI および Gradle プラグインと認証情報を共有します。既存のサインイン状態も利用できます。CI では `TUIST_TOKEN` を使用するか、Tuist の <.localized_link href="/guides/integrations/continuous-integration">OIDC 認証</.localized_link> でログインターゲットを実行してください。BUILD ファイルやルール属性に認証情報を含めないでください。`-- --url https://tuist.example.com` を渡して、セルフホスト型インスタンスにサインインします。

`BUILD.bazel` で必要なアダプターのみを読み込みます:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Apple アプリケーションの場合:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

`cc_binary` などの実行可能ターゲットの場合:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

実行可能プレビューには、ターゲットで宣言されたランタイムファイルが含まれます。ツールが必要とするライブラリとリソースを Bazel ターゲットで宣言し、ビルドディレクトリの外でも動作するパスを使用してください。

## ビルドと公開

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

アプリケーションとシミュレーターのプラットフォームラベルを自身のものに置き換えてください。セルフホスト型の Tuist オリジンには `--url` を渡し、Git コミットを関連付けるには `--revision` を渡します。

正常に完了したビルドを共有するには `--publish --project account/project` を渡します。`--publish` なし、または `--no-publish` の場合、何もアップロードされず、サインインも不要です。通常の `bazel build` は、キャッシュヒット時を含め、決して公開しません。`tuist bazel setup` はキャッシングとインサイトを有効にしますが、公開は行いません。

## サポートされる出力

- **Android:** デバッグビルドを含む、署名済みアプリケーション APK。Android SDK の build-tools とコマンドラインツールをインストールし、`ANDROID_HOME` または `ANDROID_SDK_ROOT` を設定してください。テスト APK と Android App Bundle はサポートされていません。
- **Apple:** macOS でビルドおよび検証された、アドホック署名済みのシミュレーターおよび macOS アプリケーション。物理デバイス向けビルド、フレームワーク、エクステンション、テストはサポートされていません。実験的な tree アーカイブではなく、アーカイブ出力を使用してください。
- **コマンドラインツール:** arm64 または x86_64 向けの macOS または Linux 実行ファイル。ユニバーサル macOS バイナリも含みます。スクリプトには shebang と、受信側システム上のインタープリターが必要です。ターゲットでランタイム依存関係を宣言してください。Tuist は不足しているライブラリや言語ランタイムをインストールしません。

## キャッシュのリプレイ、失敗、および保持

同じ公開を繰り返すと、Bazel がビルドをキャッシュから復元する場合でも、既存のプレビューを再アップロードせずに再利用します。出力、トラック、またはリビジョンを変更すると、新しい公開が作成されます。アップロードに失敗するとコマンドは失敗します。再試行する前に、公開が完了していたかどうかを確認するためにもう一度実行できます。

コマンドはプロジェクトのプレビューへのリンクを表示します。処理には少し時間がかかる場合があります。プレビューはプロジェクトのデフォルトの可視性を使用します。

ホスト型 Tuist では、アーティファクトの公開は 30 日後に期限切れになります。セルフホスト型インスタンスでは `TUIST_APP_PREVIEW_RETENTION_DAYS` を使用します。これを未設定のままにすると、このファミリーの有効期限が無効になります。期限切れになった公開レコードは、同じ意図を再実行しても復活させることはできません。

公開されたビルドの実行、アクセス、トラック、README バッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行する</.localized_link> を参照してください。

## Apple プレビュー

Apple シミュレーターおよび macOS プレビューについては、<.localized_link href="/guides/features/previews/run/macos">Tuist macOS コンパニオンアプリの手順</.localized_link> を参照してください。これらは Bazel のアプリケーション適格性や署名要件を変更しません。

## 関連するワークフロー {#publish-from-once}

既存の Struo 統合には、別の <.localized_link href="/guides/features/previews/struo">アーティファクト公開ガイド</.localized_link> があります。どちらのワークフローも、公開をキャッシュされたグラフ実行から分離したままにします。
