---
{
  "title": "API",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "独自のGitフォージやオーケストレーターからTuistランナーでジョブを実行します。1回のAPIリクエストでジョブを作成し、Webhookで後続処理を行います。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

独自のランナープロトコルを持たないGitフォージ、マージキュー、エージェントオーケストレーターは、Tuist Runners上で直接ジョブを実行できます。1回のリクエストでジョブを作成すると、選択した<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>のTuistマシンがコミットをチェックアウトしてスクリプトを実行し、Tuistが結果をWebhookエンドポイントに報告します。

## ジョブの実行 {#run-a-job}

1. **アカウントトークンを作成する**（スコープ: `account:runners:write`）:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **ジョブを作成する。** 一般的な呼び出し元は、pushフックからこれを実行し、マシンがリポジトリをクローンできるように短期有効なトークンを使用します:

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   レスポンスには、その`workflow_job_id`を含むジョブ情報が返されます。これはTuistダッシュボードの**Runners**セクションにすぐに表示され、選択したプロファイルのマシンが空き次第実行を開始します。ウォーム状態のマシンであれば、通常数秒以内に開始されます。

3. **ジョブを追跡する。**<.localized_link href="/guides/integrations/webhooks">Webhookエンドポイント</.localized_link>を`runner_job.started`および`runner_job.completed`に登録します。完了イベントには、ジョブの`conclusion`（`success`、`failure`、または`cancelled`）が含まれます。また、`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`をポーリングしたり、`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`からログを読み取ったりすることもできます。

## Gitフォージの統合 {#integrate-a-git-forge}

ランナープロトコルを持たないフォージは、小さなブリッジを通じて接続します。このブリッジは、フォージ自体のサービスであっても、フックから呼び出される関数であっても構いません:

1. **Push時**、フォージのpushフックがブリッジに到達します。ブリッジはフックを検証し、コミットに必要なチェックを決定し、ジョブのタイムアウト後に失効するリポジトリ用の読み取り専用クローントークンを発行します。
2. **各チェックについて**、ブリッジは`idempotency_key`を`<repository>:<commit>:<check>`に設定してジョブを作成するため、再配信されたフックによって新しいジョブが作成されることはありません。返された`workflow_job_id`を保存し、フォージ内でチェックをpending状態としてマークできます。
3. **`runner_job.started`および`runner_job.completed`発生時**、ブリッジはエンドポイントのシークレットを使用して`Tuist-Signature`ヘッダーを検証し、`workflow_job_id`または`idempotency_key`によってチェックを特定し、`conclusion`を使用してフォージのコミットステータスを更新します。ステータスをTuistダッシュボードのジョブページにリンクすることもできます。
4. **Pushによってコミットが置き換えられた場合**、ブリッジは古いコミット用に作成したジョブをキャンセルします。

## ジョブの実行方法 {#how-the-job-runs}

マシンはHTTPS経由で`repository_url`から`commit_sha`を取得します。サーバーがSHAによるコミットの提供に対応していない場合は、代わりにコミットを含む必要がある`ref`を取得します。`clone_token`（指定した場合）は、リポジトリのホストに対してのみ`Authorization: Bearer <token>`として送信されます。これがスクリプトやジョブログに届くことはありません。

スクリプトは、チェックアウトのルートディレクトリで、ログインシェル内のBashにより`set -eo pipefail`付きで実行されます。スクリプトが非ゼロのステータスで終了するか、`timeout_minutes`（デフォルトは60分、最大360分）を超えて実行されると、ジョブは失敗します。`env`および`secrets`に加え、スクリプトからは`CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF`、および`TUIST_JOB_COMMIT_SHA`が参照できます。`secrets`の値はジョブログでマスクされます。

## リトライと冪等性 {#idempotency}

各ジョブには、その用途を示す`idempotency_key`（例: `<repository>:<commit>:<check>`）を指定してください。アカウントですでに使用されているキーを持つリクエストの場合、新規作成は行われず、既存のジョブがステータス200（201ではなく）で返されます。これにより、pushフックがリクエストをリトライキューに渡しても、重複ジョブのリスクを防ぐことができます。

Webhook配信は、エンドポイントが2xxステータスで応答するまで再試行されるため、イベントが複数回到達することがあります。重複排除には、エンベロープの`id`、またはイベントタイプを組み合わせたジョブの`workflow_job_id`を使用してください。

## ジョブのキャンセル {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

どのマシンでも開始されていないジョブは即座にキャンセルされます。実行中のジョブは数秒以内に停止し、その完了イベントでは`cancelled`が報告されます。24時間以内にどのマシンでも開始されなかったジョブは自動的にキャンセルされます。

## キャッシングと信頼 {#trust}

リポジトリにpushできる任何人がジョブの実行内容を変更できるため、APIジョブは信頼されていないものとして扱われます。これらのジョブは、アカウントの共有<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>やキャッシュ署名権限を利用できません。ジョブのシークレット、スクリプト、クローントークンは暗号化されて保存され、ジョブ完了後に削除されます。
