---
{
  "title": "GitHub",
  "titleTemplate": ":title | Gitフォージ | インテグレーション | ガイド | Tuist",
  "description": "TuistをGitHubと連携させて、ワークフローを強化する方法を学びましょう。"
}
---
# GitHubインテグレーション {#github}

Gitリポジトリは、大多数のソフトウェアプロジェクトの中核をなすものです。TuistではGitHubと連携し、プルリクエスト内で直接Tuistのインサイトを提供するとともに、デフォルトブランチの同期といった設定の手間を省きます。

## セットアップ {#setup}

組織の `Integrations` タブでTuist GitHubアプリをインストールする必要があります。![インテグレーションタブを示す画像](/images/guides/integrations/gitforge/github/integrations.png)

GitHubから直接アプリをインストールすることもできます。必要に応じてTuistにログインし、GitHubアプリを承認してTuistがインストールへのアクセス権を確認できるようにし、接続するTuist組織を選択してください。アプリをインストールするGitHub組織（または個人のGitHubアカウント）の所有者である必要があります。利用可能な選択肢は、あなたが管理するTuist組織と個人のTuistアカウントのみです。Tuistが選択画面を省略するのは、アプリが個人のGitHubアカウントにインストールされており、個人のTuistアカウントが唯一の選択肢である場合に限られます。GitHub組織の場合、個人のアカウントが唯一の選択肢であっても、Tuistは常に確認を行います。チームのTuist組織が一覧に表示されない場合は、**組織を作成** を選択するか、その管理者の一人にあなたを管理者として追加してもらうよう依頼してください。ページを開いている間はリストが更新されるため、Tuistに戻ってから10分以内に選択すれば、やり直すことなく組織が表示されます。Tuistから開始した場合、組織はすでに選択されており、この手順はスキップされます。

その後、GitHubリポジトリとTuistプロジェクトの間にプロジェクト接続を追加できます。

![プロジェクト接続の追加を示す画像](/images/guides/integrations/gitforge/github/add-project-connection.png)

アプリをインストールした後、ダッシュボードを使わずにプロジェクトをリンクすることもできます。

- **CLI:** `tuist project repository connect owner/name`、およびリンクを削除するには `tuist project repository disconnect`。
- **REST API:** `PUT` および `DELETE` on `/api/projects/{account_handle}/{project_handle}/vcs-connection`。
- **Model Context Protocol:** `connect_project_repository` ツールと `disconnect_project_repository` ツール。

リポジトリは、GitHubアプリのインストールがアクセスできるものでなければならず、プロジェクトはそのリポジトリのデフォルトブランチを採用します。アカウントトークンには `project:admin:write` スコープが必要です。

> [!TIP]
> **IPホワイトリスト登録**
>
> GitHub組織が [IP許可リスト](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) を使用している場合、またはGitHubインスタンスがファイアウォールの背後にある場合は、インテグレーションがリポジトリと通信できるように、Tuistの <.localized_link href="/guides/server/network#outbound-ip-addresses">送信IPアドレス</.localized_link> をホワイトリストに登録してください。

### GitHub Enterprise Server {#github-enterprise-server}

Tuistは、セルフホスト型のGitHub Enterprise Server（GHES）インスタンスとも連携します。GitHubインテグレーションカードで **Enterprise server** タブに切り替え、GHESのベースURL（例: `https://github.example.com`）を入力し、インストールをクリックしてください。

GitHubアプリは単一のGitHubインスタンスにスコープされるため、Tuistはgithub.com用アプリをGHESで再利用できません。代わりに、インストールボタンをクリックするとGitHubの [アプリマニフェストフロー](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) が始まります。GHES上で管理者が新しいTuistアプリを登録し、その認証情報をTuistに返します。Tuistはこれらの認証情報をインストールごとに暗号化して保存し、それ以降のすべてのAPI呼び出し、Webhook署名、およびリポジトリへのリンクに使用します。

追加のTuistサーバー設定は不要です。マニフェストフローによってすべてが自動的に生成・プロビジョニングされます。

#### アプリの権限とWebhookイベント {#github-app-permissions}

Tuistは、PRコメントとバンドルサイズチェックのために以下の **リポジトリ権限** を必要とします。

| 権限 | アクセス | 用途 |
|---|---|---|
| メタデータ (`metadata`) | 読み取り専用 | 基本的なリポジトリメタデータ。GitHubがすべてのアプリに対して必須としています。 |
| プルリクエスト (`pull_requests`) | 読み取りと書き込み | プルリクエストの読み取り（ヘッドコミットのSHAを含む）、およびPRコメントの一覧表示、投稿、更新 |
| Checks (`checks`) | 読み取りと書き込み | チェックランの作成と更新（バンドルサイズの合格/不合格チェックを含む） |

Tuistは `check_run` Webhookイベントを使用してバンドルサイズチェックアクションを処理します。マニフェストフローにより、このサブスクリプションは自動的に構成されます。

セルフホスト型Tuistサーバーでgithub.com上に手動でアプリを設定する場合は、<.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">セルフホスティングガイド</.localized_link> を参照してください。

#### ブラウザ用URLとAPI用URLの分離 {#separate-browser-and-api-urls}

エンジニアが内部ホスト名を通じてGitHub Enterpriseにアクセスし、サードパーティサービスが外部プロキシを使用する場合、インストールをクリックする前に両方のアドレスを設定してください。

| フィールド | 例 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | アプリの登録とインストール、およびTuistからGitHubへのリンクに使用 |
| **API URL** | `https://github-proxy.company.com/api/v3` | マニフェストコードの交換、アクセストークン、リポジトリアクセス、PRコメント、およびチェックに使用されるTuistサーバー |

API URLは、`/api/v3`またはプロキシが公開する同等のパスを含む完全なREST APIベースURLです。Tuistは明示的なAPI URLに`/api/v3`を追加しません。ブラウザとTuistの両方で同じホスト名が機能する場合は空のままにしてください。既存の接続は引き続き`<Server URL>/api/v3`を使用します。

両方のアドレスは、**同じGitHub Enterpriseインスタンス**にルーティングされる必要があります。ブラウザはServer URLに到達できればよく、APIプロキシへの到達は不要です。TuistサーバーはAPI URLに到達できればよく、内部ブラウザ用ホスト名への到達は不要です。

外部プロキシの場合：

- Tuistサーバーが信頼する証明書を使用したHTTPSと、パブリックIPアドレスに解決されるパブリックDNSを使用してください。API URLの上書きは、TuistのプライベートIP/SSRF保護をバイパスしません。上書き先はあなたのEnterpriseインスタンスである必要があり、`github.com`や`*.github.com`エンドポイントであってはなりません。
- Tuistの<.localized_link href="/guides/server/network#outbound-ip-addresses">送信元IPアドレス</.localized_link>をすべて許可リストに登録してください。
- Tuistが使用するREST APIエンドポイントを転送してください。`POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens`、およびコメントとチェック用のリポジトリAPIエンドポイントが含まれます。これらはGitHubの上流パスです。プロキシが異なるプレフィックスを公開している場合は、それらに合わせて翻訳してください。
- HTTPリダイレクトやインタラクティブなサインインページなしで、GitHubへのリクエストを転送してください。TuistはEnterprise APIのリダイレクトを自動的に追従しないため、パブリックIPチェックをバイパスできません。マニフェスト変換エンドポイントは、Tuistがアプリの認証情報を取得する前のセットアップ中に到達可能である必要があります。GitHub Actionsのログダウンロードは例外です。Tuistは署名付きアーカイブのリダイレクトをHTTPS経由でのみ追従し、すべての宛先をパブリックIPにチェックおよび固定し、インストールトークンは転送しません。

GitHubは内部ホスト名を使用してページネーションリンクを返す場合があります。Tuistは、構成されたGitHubインスタンスからのリンクをAPI URLに基づき直し、プロキシのパスプレフィックスを保持します。無関係なオリジンへのリンクは拒否されます。

別途、GitHubはWebhookを`https://tuist.dev/webhooks/github`（セルフホスト型Tuistサーバーの場合は`/webhooks/github`）に配信できる必要があります。エンジニアはブラウザのコールバックを完了するためにTuistに戻れる必要があります。API URLはどちらの宛先も変更しません。

組織管理者は、統合カード内の**Save API URL**を使用して、既存のEnterprise統合のAPI URLを変更またはクリアすることもできます。アプリの再インストールやプロジェクトの再接続は不要です。クリアすると`<Server URL>/api/v3`が復元されます。保存時はURL形式のみが検証され、プロキシの接続性は検証されません。インストールルックアップはキャッシュされるため、Webhook処理が変更後のアドレスを使用するまでに最大1分かかる場合があります。すでに進行中のリクエストは、引き続き以前のアドレスを使用する可能性があります。

> [!NOTE]
> **ホスト型TuistサーバーではEnterpriseプラン限定**
>
> ホスト型Tuistサーバー（`https://tuist.dev`）では、GitHub Enterprise Server統合は**Enterprise**プランの組織のみが利用できます。セルフホスト型Tuistデプロイメントでは、どのプランでも利用できます。

## プル/マージリクエストのコメント {#pull-merge-request-comments}

GitHubアプリはTuistの実行レポートを投稿します。これにはPRの概要が含まれ、最新の<.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">プレビュー</.localized_link>または<.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">テスト</.localized_link>へのリンクが含まれます。

Tuistは結果が届くにつれて1つのコメントを更新します。Gradleビルドは、各ルートプロジェクトと要求されたタスクのセットごとに個別に表示されます。同じタスクを再実行すると、その呼び出しの以前の結果が置き換えられます。完全なビルド履歴はTuistで引き続き利用可能です。

コメントはデフォルトで有効になっており、既存の統合に対するレポート機能を維持します。プロジェクトに対してコメントをオフまたはオンにするには、**Project Settings → Integrations**を開き、**GitHub → Run report comments**を切り替えます。各プロジェクトには独自の設定があります。リポジトリ接続は組織設定で管理されます。

コメントを無効にしても、ビルドまたはテストのアップロード、GitHub Actionsジョブサマリー、リポジトリ接続、または他のGitHub統合機能は無効になりません。既存のコメントは削除されません。

![プルリクエストコメントを示す画像](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **要件**
>
> コメントは、CI実行が<.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link>の場合にのみ投稿されます。

> [!NOTE]
> **`GITHUB_REF`**
>
> PRコミットではなく、例えばGitHubコメントなどでトリガーされるカスタムワークフローがある場合、`GITHUB_REF`変数が`refs/pull/<PR_NUMBER>/merge`または`refs/pull/<PR_NUMBER>/head`のいずれかに設定されていることを確認する必要があります。
>
> 関連するコマンド（例：`tuist share`）を、前置きされた`GITHUB_REF`環境変数と共に実行できます：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actionsジョブサマリー {#github-actions-job-summary}

Tuist CLIとGradleプラグインは、テストとビルドの結果をGitHub Actionsの[ジョブサマリー](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)に書き込みます。サマリーからはTuist上の完全なレポートにリンクでき、不安定なテストやバンドルサイズの変動など、より豊富なインサイトを利用できます。

Gradleの場合、正常にアップロードされた各ビルドまたはテストレポートは独自のサマリーを追加し、`gradle/actions/setup-gradle`などのツールによって書き込まれた他のコンテンツを保持します。これにはジョブサマリーサポートを含むプラグインバージョンが必要です。古いGradleプラグインバージョンは、GitHubアプリのPRコメントを通じてのみレポートします。ジョブサマリーのためにGitHubアプリを接続する必要はなく、**Run report comments**を無効にしても影響しません。

GitHub Actionsサマリーの宛先が利用可能な場合、Gradleは`uploadInBackground`が有効であっても、アップロードとサマリーが完了するまで待ってから終了します。GitHubはワークフローステップが終了した時点でサマリーを取得します。

![GitHub Actionsジョブサマリー内のTuist実行レポートを示す画像](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

これは[マージキュー](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)で使用する場合に特に便利です。マージキューの実行はプルリクエストに紐付けられないためコメントは投稿されませんが、ジョブサマリーには結果が表示されます。

> [!NOTE]
> **要件**
>
> ジョブサマリーには、レポートの正常なアップロードが必要です。ホスト型Tuistサーバーでは、CI実行が<.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link>である必要があります。セルフホスト型インスタンスでは、ネットワーク信頼レポート公開が有効になっている場合、認証情報不要のレポートも受け入れることができます。
