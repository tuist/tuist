---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | インテグレーション | ガイド | Tuist",
  "description": "Tuist のビルド、テスト、バンドル、プレビューのインサイトを Entire Trails に公開します。"
}
---
# Entire 統合 {#entire}

Tuist は、接続された各リポジトリのオープンまたはドラフト状態の [Trail](https://docs.entire.com/guides/trails/overview) に要約ディスカッションを維持します。この要約には、利用可能なビルド結果、テストの失敗と不安定なテスト、バンドルサイズ、アプリプレビューが含まれ、Tuist 上の完全なレポートへのリンクが提供されます。

> [!IMPORTANT]
> **早期アクセス**
>
> Entire プラグインにはパートナー登録が必要であり、Trail ディスカッションと Webhook コントラクトは実験的なものです。Tuist 管理者は、すべてのアカウントまたは選択したアカウントに対してこの統合を有効にできます。また、Entire プロジェクトで登録済みプラグインのインストールを許可する必要があります。

## セットアップ {#setup}

インストール手順は GitHub 統合と同じフローに従います。まずアカウント用にプラグインをインストールし、その後リポジトリを Tuist プロジェクトに接続します。ホスト型 Tuist では、管理者がプラグイン登録とサーバー構成を担当するため、以下の手順だけを実行すれば済みます。

1. アカウントの **設定 → 統合** を開きます。
2. **Entire** で **Entire プラグインをインストール** を選択します。Tuist と共有したい Entire プロジェクトとリポジトリを選択してください。

   ![アカウント統合から Entire プラグインをインストール](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist に戻り、**新しいプロジェクト接続を追加** を選択します。**接続するリポジトリを選択** で、Tuist プロジェクトと Entire リポジトリを選び、**接続を作成** を選択します。Tuist プロジェクトが 1 つしかない場合は、自動的に選択されます。

   ![Tuist プロジェクトを Entire リポジトリに接続](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 既存の認証済み Tuist コマンドを使用して、CI からインサイトのアップロードを継続してください。Tuist はそれらを各 Trail の現在のコミット SHA に照合します。Entire 固有の CLI フラグは不要です。

Tuist プロジェクトは GitHub 接続を維持しながら、Entire にも要約を公開できます。これは GitHub ミラーに役立ちます。Trail の要約には Tuist の CI エグゼキューターは不要で、既存の CI プロバイダーを変更する必要もありません。

Tuist は、インサイトが届くたびに同じディスカッションを更新します。Trail を開いたり再開したりすると、ヘッドコミットに対して以前にアップロードされたインサイトも取り込まれます。クローズ済みおよびマージ済みの Trail は更新されません。古いコミットの結果が現在のヘッドの結果として表示されることはありません。現在のコミットにインサイトが存在しない場合、Tuist は既存の要約を変更せずに残します。各結果にはそのコミットハッシュが含まれます。

プロジェクト接続を削除するには、GitHub と同様に **管理** メニューを開き、**接続を削除** を選択します。これにより、今後の更新が停止し、Tuist のローカルディスカッションポインターが削除されます。すでに公開されたコメントは Entire に残ります。再接続すると、既存の要約がまだアクセス可能な場合に復元されます。プラグインのリポジトリアクセスを変更したりアンインストールしたりするには、Entire のプロジェクト **プラグイン** 設定を使用してください。

## サーバー構成 {#server-configuration}

このセクションは Tuist サーバー運営者向けです。[プラグイン登録ガイド](https://docs.entire.com/guides/api/plugins/register) を使用して、Entire にプラグインを登録してください。`contents:read` と `discussions:write` を要求します。読み取り権限は Trail イベントとディスカッションの検出に必要ですが、リポジトリへの書き込みアクセスは不要です。

以下のサーバー環境変数を構成してください。

| 変数 | 目的 |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entire によって確認されたスラッグ |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM 形式の Ed25519 秘密鍵。シークレットストア経由で提供 |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | JWKS ベースの鍵登録を使用する場合の鍵 ID。それ以外の場合は省略可能 |
| `TUIST_ENTIRE_CORE_URL` | インストールリクエストに使用される Entire Core。デフォルトは `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 登録時に Entire から提供される Webhook 署名鍵 URL |

マネージド Helm デプロイメントの場合、環境の 1Password ボールトに `ENTIRE_PLUGIN/private_key` として秘密 PEM を保存し、`server.config.managedSecrets` と併せて `server.config.entirePluginKey.enabled` を有効にします。External Secrets は、マルチライン PEM を切り詰めることなく、既存のサーバー構成 Secret を介して `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` を提供します。アイテム名とフィールド名は `server.config.entirePluginKey.item` および `.field` で構成可能です。このマッピングはデフォルトで無効になっており、スラッグや Webhook 署名鍵 URL は構成しません。登録後に別途指定してください。各環境では独自の署名鍵を使用すべきです。Entire と共有するのは公開 PEM のみとし、秘密鍵は決して共有しないでください。

`https://<your-tuist-host>/integrations/entire/callback` をインストール後 URL として、`https://<your-tuist-host>/webhooks/entire` を Webhook URL として登録します。サーバーマイグレーションを適用した後、`entire_trails` 機能フラグをグローバルに有効にしてすべてのアカウントに統合を提供するか、選択したアカウントに対してのみ有効にします。一般公開する場合、Entire の担当者に連絡し、プラグインを所有するプロジェクト外でのインストールを許可してもらってください。Tuist の機能フラグを有効にしても、Entire のインストールポリシーは変更されません。Entire Trail の要約は、Tuist の CI 実行構成や機能フラグとは独立しています。

Tuist はインストールレシートと Webhook 署名を検証し、短期間有効なリポジトリスコープのトークンを発行し、公開前に各リポジトリの現在の処理リージョンを検出します。トークンはレポートリンクに埋め込まれることはありません。
