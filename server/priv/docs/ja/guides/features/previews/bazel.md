---
{
  "title": "Bazel プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Bazel から Android アプリ、Apple アプリ、コマンドラインツールをプレビューとして公開します。"
}
---
# Bazelプレビュー

既存のBazelターゲットからAndroid APK、AppleシミュレータおよびmacOSアプリ、コマンドラインツールを公開します。共有したい出力ごとにプレビューターゲットを追加してください。通常のビルドは変更されません。

## セットアップ

Tuistリポジトリの[`rules_tuist`](https://github.com/tuist/tuist/tree/main/bazel)を`MODULE.bazel`に追加し、使用するコミットを固定します:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

既存のアプリケーションターゲット、ネイティブSDK、署名設定はそのまま維持してください。公開ツールはBazelが提供します。

Bazelから直接サインインします:

```bash
bazel run @rules_tuist//:login
```

これにより、Tuist CLIおよびGradleプラグインと認証情報を共有します。既存のサインイン状態も利用できます。CIでは`TUIST_TOKEN`を使用するか、Tuistの<.localized_link href="/guides/integrations/continuous-integration">OIDC認証</.localized_link>を使用してログインターゲットを実行してください。BUILDファイルやルール属性に認証情報を決して含めないでください。`-- --url https://tuist.example.com`を渡して、セルフホスト型インスタンスにサインインします。

`BUILD.bazel`で必要なアダプターのみを読み込みます:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Appleアプリケーションの場合:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

`cc_binary`などの実行可能ターゲットの場合:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

実行可能プレビューには、ターゲットで宣言されたランタイムファイルが含まれます。ツールが必要とするライブラリとリソースをBazelターゲットで宣言し、ビルドディレクトリの外でも動作するパスを使用してください。

## ビルドと公開

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

アプリケーションおよびシミュレータプラットフォームのラベルを自身のものに置き換えてください。セルフホスト型のTuistオリジンには`--url`を渡し、Gitコミットを関連付けるには`--revision`を渡します。

成功したビルドを共有するには`--publish --project account/project`を渡します。`--publish`がない場合、または`--no-publish`の場合、何もアップロードされず、サインインも不要です。通常の`bazel build`はキャッシュヒット時を含め、決して公開しません。`tuist bazel setup`は公開ではなく、キャッシングとインサイトを有効にします。

## サポートされる出力

- **Android:** デバッグビルドを含む署名済みアプリケーションAPK。Android SDKのbuild-toolsおよびコマンドラインツールをインストールし、`ANDROID_HOME`または`ANDROID_SDK_ROOT`を設定してください。テストAPKおよびAndroid App Bundleはサポートされていません。
- **Apple:** macOS上でビルドおよび検証された、アドホック署名付きシミュレータおよびmacOSアプリケーション。実機ビルド、フレームワーク、エクステンション、テストはサポートされていません。実験的なtreeアーカイブではなく、アーカイブ出力を使用してください。
- **コマンドラインツール:** arm64またはx86_64向けのmacOSまたはLinux実行可能ファイル。ユニバーサルmacOSバイナリも含みます。スクリプトにはshebangと受信側のシステム上のインタープリターが必要です。ターゲットでランタイム依存関係を宣言してください。Tuistは不足しているライブラリや言語ランタイムをインストールしません。

## キャッシュのリプレイ、失敗、および保持

同じ公開を繰り返すと、Bazelがビルドをキャッシュから復元した場合でも、再度アップロードすることなく既存のプレビューを再利用します。出力、トラック、またはリビジョンを変更すると、新しい公開が作成されます。アップロードに失敗するとコマンドは失敗します。再試行する前に公開が完了したかどうかを確認するため、コマンドを再実行できます。

コマンドはプロジェクトのプレビューへのリンクを表示します。処理には少し時間がかかる場合があります。プレビューはプロジェクトのデフォルトの可視性を使用します。

ホスト型Tuistでは、アーティファクト公開は30日後に期限切れになります。セルフホスト型インスタンスでは`TUIST_APP_PREVIEW_RETENTION_DAYS`を使用します。これを未設定のままにすると、このファミリーの有効期限が無効になります。期限切れになった公開レコードは、同じ意図を再実行しても復活させることはできません。

公開されたビルドの実行、アクセス、トラック、READMEバッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行する</.localized_link>を参照してください。

## Appleプレビュー

AppleシミュレータおよびmacOSプレビューについては、<.localized_link href="/guides/features/previews/run/macos">Tuist macOSコンパニオンアプリの説明</.localized_link>を参照してください。これらはBazelのアプリケーション適格性や署名要件を変更しません。

## 関連するワークフロー {#publish-from-once}

既存のOnce統合には、別個の<.localized_link href="/guides/features/previews/once">アーティファクト公開ガイド</.localized_link>があります。どちらのワークフローも、公開をキャッシュされたグラフ実行から分離したままにします。
