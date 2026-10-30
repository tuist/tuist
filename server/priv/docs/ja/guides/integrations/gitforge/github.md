---
{
  "title": "GitHub",
  "titleTemplate": ":title | Gitフォージ | インテグレーション | ガイド | Tuist",
  "description": "TuistをGitHubと統合してワークフローを強化する方法を学びます。"
}
---
# GitHub インテグレーション {#github}

Git リポジトリは、大多数のソフトウェアプロジェクトの中核です。Tuist は GitHub とインテグレートすることで、プルリクエスト内で Tuist のインサイトを提供し、デフォルトブランチの同期などの設定作業を削減します。

## セットアップ {#setup}

組織の `Integrations` タブで Tuist GitHub アプリをインストールする必要があります。![インテグレーションタブを示す画像](/images/guides/integrations/gitforge/github/integrations.png)

GitHub から直接アプリをインストールすることもできます。必要に応じて Tuist にログインし、GitHub App を承認して Tuist がインストールへのアクセス権を検証できるようにし、接続する Tuist 組織を選択してください。アプリをインストールする GitHub 組織（または個人の GitHub アカウント）を所有している必要があります。利用可能なのは、あなたが管理する Tuist 組織と個人の Tuist アカウントのみです。アカウントが 1 つしかない場合、Tuist は選択画面を表示せずに自動的に接続します。Tuist から開始した場合、組織はすでに選択されており、この手順はスキップされます。

その後、GitHub リポジトリと Tuist プロジェクトの間にプロジェクト接続を追加できます。

![プロジェクト接続の追加を示す画像](/images/guides/integrations/gitforge/github/add-project-connection.png)

アプリをインストールした後、ダッシュボードを使わずにプロジェクトをリンクすることもできます。

- **CLI:** `tuist project repository connect owner/name`、およびリンクを削除するには `tuist project repository disconnect`。
- **REST API:** `/api/projects/{account_handle}/{project_handle}/vcs-connection` に対する `PUT` および `DELETE`。
- **Model Context Protocol:** `connect_project_repository` ツールと `disconnect_project_repository` ツール。

リポジトリは GitHub App のインストールがアクセスできるものでなければならず、プロジェクトはそのリポジトリのデフォルトブランチを採用します。アカウントトークンには `project:admin:write` スコープが必要です。

> [!TIP]
> **IP 許可リスト**
>
> GitHub 組織で [IP 許可リスト](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) を使用している場合、または GitHub インスタンスがファイアウォールの背後にある場合は、インテグレーションがリポジトリと通信できるように、Tuist の <.localized_link href="/guides/server/network#outbound-ip-addresses">アウトバウンド IP アドレス</.localized_link> を許可リストに追加してください。

### GitHub Enterprise Server {#github-enterprise-server}

Tuist はセルフホスト型の GitHub Enterprise Server (GHES) インスタンスともインテグレートします。GitHub インテグレーションカードで **Enterprise server** タブに切り替え、GHES のベース URL（例: `https://github.example.com`）を入力して、インストールをクリックしてください。

GitHub Apps は単一の GitHub インスタンスにスコープされるため、Tuist はその github.com App を GHES で再利用できません。代わりに、インストールボタンをクリックすると GitHub の [App マニフェストフロー](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) が開始されます。GHES が管理者の手順に従ってインスタンス上に新しい Tuist App を登録し、その新しい App の認証情報を Tuist に返します。Tuist はそれらの認証情報をインストールごとに暗号化して保存し、以降のすべての API コール、Webhook 署名、およびリポジトリへのリンクに使用します。

追加の Tuist サーバー設定は不要です。マニフェストフローがすべてを自動的に生成およびプロビジョニングします。

#### App の権限と Webhook イベント {#github-app-permissions}

PR コメントとバンドルサイズチェックのために、Tuist は以下の **リポジトリ権限** を必要とします。

| 権限 | アクセス | 用途 |
|---|---|---|
| メタデータ (`metadata`) | 読み取り専用 | 基本的なリポジトリメタデータ。GitHub がすべての App に要求 |
| プルリクエスト (`pull_requests`) | 読み取りと書き込み | プルリクエストの読み取り（ヘッドコミットの SHA を含む）、および PR コメントの一覧表示、投稿、更新 |
| Checks (`checks`) | 読み取りと書き込み | チェックランの作成と更新（バンドルサイズの合格/不合格チェックを含む） |

Tuist は `check_run` Webhook イベントを使用してバンドルサイズチェックアクションを処理します。マニフェストフローがこのサブスクリプションを自動的に構成します。

セルフホスト型 Tuist サーバーで github.com 上で手動で App を設定する場合は、<.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">セルフホスティングガイド</.localized_link> を参照してください。

#### ブラウザ用 URL と API 用 URL の分離 {#separate-browser-and-api-urls}

エンジニアが内部ホスト名を通じて GitHub Enterprise にアクセスし、サードパーティサービスが外部プロキシを使用する場合、インストールをクリックする前に両方のアドレスを設定してください。

| フィールド | 例 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | App の登録とインストール、および Tuist から GitHub へのリンクに使用 |
| **API URL** | `https://github-proxy.company.com/api/v3` | マニフェストコードの交換、アクセストークン、リポジトリアクセス、PR コメント、およびチェックに使用される Tuist のサーバー |

API URL は、`/api/v3` またはプロキシが公開する同等のパスを含む完全な REST API ベース URL です。Tuist は明示的な API URL に `/api/v3` を追加しません。ブラウザと Tuist の両方で同じホスト名が機能する場合は空のままにしてください。既存の接続は引き続き `<Server URL>/api/v3` を使用します。

両方のアドレスは **同じ GitHub Enterprise インスタンス** にルーティングされる必要があります。ブラウザは Server URL に到達できればよく、API プロキシには到達する必要はありません。Tuist のサーバーは API URL に到達できればよく、内部ブラウザ用ホスト名には到達する必要はありません。

外部プロキシの場合：

- Tuist のサーバーが信頼する証明書を使用した HTTPS と、パブリック IP アドレスに解決されるパブリック DNS を使用してください。API URL のオーバーライドは、Tuist のプライベート IP/SSRF 保護をバイパスしません。オーバーライドは Enterprise インスタンスを対象とする必要があり、`github.com` や `*.github.com` エンドポイントを対象としてはいけません。
- すべての Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">送信元 IP アドレス</.localized_link> を許可リストに追加してください。
- Tuist が使用する REST API エンドポイントを転送してください。`POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens`、およびコメントとチェック用のリポジトリ API エンドポイントが含まれます。これらは GitHub のアップストリームパスです。プロキシが異なるプレフィックスを公開している場合は、それに応じて変換してください。
- HTTP リダイレクトやインタラクティブなサインインページなしで、GitHub へのリクエストを転送してください。Tuist は Enterprise API のリダイレクトを自動的に追従しないため、パブリック IP チェックをバイパスすることはできません。マニフェスト変換エンドポイントは、Tuist が App の認証情報を取得する前のセットアップ中に到達可能である必要があります。GitHub Actions のログダウンロードは例外です。Tuist は署名付きアーカイブのリダイレクトを HTTPS 経由でのみ追従し、すべての宛先をパブリック IP にチェックして固定し、インストールトークンを転送しません。

GitHub は内部ホスト名を使用してページネーションリンクを返す場合があります。Tuist は、構成された GitHub インスタンスからのリンクを API URL に基づいて再構築し、プロキシのパスプレフィックスを保持します。無関係なオリジンへのリンクは拒否されます。

別途、GitHub は Webhook を `https://tuist.dev/webhooks/github`（またはセルフホスト型 Tuist サーバー上の `/webhooks/github`）に配信できる必要があります。エンジニアはブラウザのコールバックを完了するために Tuist に戻れる必要があります。API URL はどちらの宛先も変更しません。

組織管理者は、統合カード内の **Save API URL** を使用して、既存の Enterprise 統合の API URL を変更またはクリアすることもできます。App の再インストールやプロジェクトの再接続は不要です。クリアすると `<Server URL>/api/v3` に復元されます。保存時には URL 形式のみが検証され、プロキシの接続性は検証されません。インストールのルックアップはキャッシュされるため、Webhook の処理が変更されたアドレスを使用するまで最大 1 分かかる場合があります。すでに進行中のリクエストは引き続き以前のアドレスを使用する可能性があります。

> [!NOTE]
> **ホスト型 Tuist サーバーでは Enterprise プラン限定**
>
> ホスト型 Tuist サーバー（`https://tuist.dev`）では、GitHub Enterprise Server 統合は **Enterprise** プランの組織のみ利用可能です。セルフホスト型 Tuist デプロイメントでは、どのプランでも使用できます。

## プル/マージリクエストのコメント {#pull-merge-request-comments}

GitHub App は Tuist の実行レポートを投稿します。これには PR の概要が含まれ、最新の <.localized_link href="/guides/features/previews#pullmerge-request-comments">プレビュー</.localized_link> または <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">テスト</.localized_link> へのリンクが含まれます。

Tuist は結果が届くにつれて 1 つのコメントを更新します。Gradle ビルドは、各ルートプロジェクトと要求されたタスクのセットごとに個別に表示されます。同じタスクを再実行すると、その呼び出しの以前の結果が置き換えられます。完全なビルド履歴は Tuist で引き続き利用可能です。

コメントはデフォルトで有効になっており、既存の統合のレポート機能を維持します。プロジェクトでコメントをオフまたはオンに戻すには、**Project Settings → Integrations** を開き、**GitHub → Run report comments** を切り替えます。各プロジェクトには独自の設定があります。リポジトリ接続は組織設定で管理されます。

コメントを無効にしても、ビルドまたはテストのアップロード、GitHub Actions ジョブサマリー、リポジトリ接続、またはその他の GitHub 統合機能は無効になりません。既存のコメントは削除されません。

![プルリクエストのコメントを示す画像](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **要件**
>
> コメントは、CI 実行が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link> の場合にのみ投稿されます。

> [!NOTE]
> **Github_ref**
>
> PR コミットではなく、例えば GitHub コメントなどでトリガーされるカスタムワークフローがある場合、`GITHUB_REF` 変数が `refs/pull/<PR_NUMBER>/merge` または `refs/pull/<PR_NUMBER>/head` のいずれかに設定されていることを確認する必要があります。
>
> 関連するコマンド（例：`tuist share`）を、前置された `GITHUB_REF` 環境変数と共に実行できます。<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions ジョブサマリー {#github-actions-job-summary}

Tuist CLI と Gradle プラグインは、テストとビルドの結果を GitHub Actions の [ジョブサマリー](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) に書き込みます。サマリーには Tuist 上の完全なレポートへのリンクが含まれており、不安定なテストやバンドルサイズの差分などのより豊富な洞察を利用できます。

Gradle では、正常にアップロードされた各ビルドまたはテストレポートが独自のサマリーを追加し、`gradle/actions/setup-gradle` などのツールによって書き込まれた他のコンテンツを保持します。これには、ジョブサマリーサポートを含むプラグインバージョンが必要です。古い Gradle プラグインバージョンは、GitHub App の PR コメントを通じてのみレポートします。ジョブサマリーのために GitHub App を接続する必要はなく、**Run report comments** を無効にしても影響しません。

GitHub Actions サマリーの宛先が利用可能な場合、Gradle は `uploadInBackground` が有効であっても、終了前にアップロードとサマリーを待ちます。GitHub はワークフローステップが完了した時点でサマリーを取得します。

![GitHub Actions ジョブサマリー内の Tuist 実行レポートを示す画像](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

これは [マージキュー](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) と特に併用する場合に役立ちます。マージキューの実行はプルリクエストに関連付けられないため、コメントは投稿されませんが、ジョブサマリーには結果が表示されます。

> [!NOTE]
> **要件**
>
> ジョブサマリーには、レポートの正常なアップロードが必要です。ホスト型 Tuist サーバーでは、CI 実行が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link> である必要があります。セルフホスト型インスタンスでは、ネットワーク信頼型レポート公開が有効になっている場合、認証情報不要のレポートも受け入れることができます。
