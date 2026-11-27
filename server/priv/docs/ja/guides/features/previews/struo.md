---
{
  "title": "Struo プレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Struo のネイティブな Tuist プロバイダーを通じて、Android、Apple シミュレーター、および macOS アプリケーションのプレビューを公開します。"
}
---
# Struo プレビュー {#struo-previews}

<a id="once-previews"></a>

[Struo](https://struo.run/docs/guide/infrastructure/tuist#publish-application-previews) は、アプリケーションの成果物を Tuist に公開し、チームメンバーがローカルで再ビルドせずにビルドを試せるようにします。[Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 以降と、アーティファクトレシーバーを備えた Tuist サーバーを使用してください。

## 宛先の設定

<.localized_link href="/guides/get-started/struo-project">Struo を使い始める</.localized_link> を完了し、ワークスペースの `struo.toml` にアーティファクトバインディングを追加します。キャッシュ用にすでに設定されている場合は、プロバイダーを再利用してください。

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
struo auth login --provider tuist
struo artifact publish MyApplication --track review
```

レシーバーは、不明なインターフェースを含む完全なセット、メンバーマニフェスト、およびペイロードを保持します。サポートされているネイティブインターフェースは、プロジェクトのデフォルトの可視性、アクセス権、および配布設定を使用して、非同期でプレビューに投影されます。一般的なアーティファクトの内容は、パブリックプロジェクトであっても非公開のままです。領収書はアーティファクトの保存を確認するものであり、プレビュー処理の完了を示すものではありません。その URL はプロジェクトのプレビューリストを開きます。

## 対象となるアプリケーション

Apple の投影は、macOS でエクスポートされたアドホック署名付き macOS およびシミュレーターアプリケーション用の `dev.struo.apple-install.v2` メタデータを受け入れます。物理デバイス用アプリケーションは対象外です。Android の投影は、検証済み署名を持つ `dev.struo.android-install.v1` メタデータを受け入れます。Struo は、デバッグ署名された非計装 APK のみを自動公開として承認します。不明なインターフェースは、プレビューを作成せずにアーティファクトとしてダウンロード可能なままです。Android インストールリンクは、ペイロードがコンテンツダイジェストの下に保存されていても、`.apk` ファイル名を保持します。

## ビルド後の公開へのオプトイン

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
struo artifact publish MyApplication --allow-on-build
struo build MyApplication
```

リクエストされたすべてのビルドが成功する必要があります。自動公開には、プロデューサーによるクロージャ全体の承認と、このマシン、ワークスペース、正確なエンドポイント、ターゲット、および安定した Tuist プロジェクト宛先に対するローカル承認も必要です。ポリシーまたは承認がない場合、アーティファクト公開のためのネットワークリクエストは行われません。通常の Struo ビルドは、暗黙的な公開の副作用がありません。

同じ保持された公開を再実行すると、リモート領収書が検証され、別のアップロードが回避されます。これは `tuist share` の重複ビルド動作とは異なります。

## 保持期間

ホスト型 Tuist では、アーティファクト公開は 30 日後に期限切れになります。セルフホスト型インスタンスでは `TUIST_APP_PREVIEW_RETENTION_DAYS` を使用します。これを未設定のままにすると、このファミリーの有効期限が無効になります。期限切れのレコードは墓碑として残り、同じ意図を再実行しても再有効化することはできません。既存の `tuist share` 署名、可視性、および配布ワークフローは変更されません。

公開されたビルドの実行、アクセス、トラック、および README バッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行する</.localized_link> を参照してください。

## Apple プレビュー

対象となる Apple シミュレーターおよび macOS プレビューについては、<.localized_link href="/guides/features/previews/run/macos">Tuist macOS コンパニオンアプリの手順</.localized_link> を参照してください。物理デバイス用アプリケーションは、Struo 公開の対象外です。
