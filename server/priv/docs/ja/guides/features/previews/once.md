---
{
  "title": "Once プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Once のネイティブな Tuist プロバイダーを通じて、Android、Apple シミュレーター、macOS アプリケーションのプレビューを公開します。"
}
---
# Once プレビュー {#once-previews}

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) はアプリケーションアーティファクトを Tuist に公開できるため、チームメンバーはローカルで再ビルドせずにビルドを試すことができます。これには Once 0.74.0 以上と、アーティファクトレシーバーを備えた Tuist サーバーが必要です。Once 0.73.x では代わりに従来の単一ペイロードアダプターが使用されます。

## 宛先の設定

<.localized_link href="/guides/get-started/once-project">Once の使い始め</.localized_link> を完了し、ワークスペースの `once.toml` でアーティファクトバインディングを追加してください。キャッシング用にすでに設定されている場合は、同じプロバイダーを再利用します。

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

レシーバーは、不明なインターフェースを含む完全なセット、メンバーマニフェスト、およびペイロードを保持します。サポートされているネイティブインターフェースは、プロジェクトのデフォルトの可視性、アクセス権、および配布設定を使用して非同期でプレビューに投影されます。一般的なアーティファクトの内容は、公開プロジェクトであってもプライベートのままです。領収書はアーティファクトの保存を確認するものであり、プレビュー処理の完了を示すものではありません。その URL はプロジェクトのプレビューリストを開きます。

## 対象となるアプリケーション

Apple プロジェクションは、macOS でエクスポートされたアドホック署名付き macOS およびシミュレーターアプリケーション用の `dev.once.apple-install.v2` メタデータを受け入れます。物理デバイス用アプリケーションは対象外です。Android プロジェクションは、検証済みの署名を持つ `dev.once.android-install.v1` メタデータを受け入れます。Once は、デバッグ署名付きで計装されていない APK のみが自動公開を承認します。不明なインターフェースは、プレビューを作成せずにアーティファクトとしてダウンロード可能です。Android インストールリンクは、ペイロードがコンテンツダイジェストの下に保存されていても、`.apk` ファイル名を保持します。

## ビルド後の公開をオプトイン

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

リクエストされたすべてのビルドが成功する必要があります。自動公開には、プロデューサーによるクロージャー全体の承認と、このマシン、ワークスペース、正確なエンドポイント、ターゲット、および安定した Tuist プロジェクト宛先に対するローカル認証も必要です。ポリシーまたは認証がない場合、アーティファクト公開のためのネットワークリクエストは行われません。通常の Once ビルドには、暗黙的な公開の副作用はありません。

同じ保持された公開を再実行すると、リモートの領収書が検証され、別のアップロードが回避されます。これは `tuist share` の重複ビルド動作とは異なります。

## 保持期間

ホスト型 Tuist では、アーティファクト公開は 30 日後に期限切れになります。セルフホスト型インスタンスでは `TUIST_APP_PREVIEW_RETENTION_DAYS` を使用します。これを未設定のままにすると、このファミリーの有効期限が無効になります。期限切れのレコードはトゥームストーンとして残り、同じ意図を再実行しても再有効化することはできません。既存の `tuist share` 署名、可視性、および配布ワークフローは変更されません。

公開されたビルドの実行、アクセス、トラック、および README バッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行</.localized_link> を参照してください。

## Apple プレビュー

対象となる Apple シミュレーターおよび macOS プレビューについては、<.localized_link href="/guides/features/previews/run/macos">Tuist macOS コンパニオンアプリの手順</.localized_link> を参照してください。物理デバイス用アプリケーションは Once 公開の対象外です。
