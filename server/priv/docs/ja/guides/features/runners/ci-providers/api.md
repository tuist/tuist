---
{
  "title": "API",
  "titleTemplate": ":title · CI プロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "独自の Git フォージやオーケストレーターから Tuist Runners でジョブを実行します。1 回の API リクエストでジョブを作成し、Webhook でその状態を追跡できます。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

独自のランナープロトコルを持たない Git フォージ、マージキュー、エージェントオーケストレーターは、Tuist Runners でジョブを直接実行できます。1 回のリクエストでジョブを作成すると、選択した<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>の Tuist マシンがコミットをチェックアウトしてスクリプトを実行し、Tuist が結果を Webhook エンドポイントに報告します。

## ジョブの実行 {#run-a-job}

1. **アカウントトークンを作成する**（スコープ: `account:runners:write`）：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **ジョブを作成する。** 一般的な呼び出し元は、プッシュフックからこれを行い、マシンがリポジトリをクローンできるようにする短期有効なトークンを使用します：

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

   レスポンスにはジョブとその`workflow_job_id`が含まれます。これは Tuist ダッシュボードの**Runners**セクションにすぐに表示され、プロファイルのマシンが空き次第すぐに開始されます。ウォーム状態のマシンなら通常数秒以内に開始されます。

3. **ジョブを追跡する。**<.localized_link href="/guides/integrations/webhooks">Webhook エンドポイント</.localized_link>を`runner_job.started`および`runner_job.completed`に登録します。完了イベントにはジョブの`conclusion`（`success`、`failure`、または`cancelled`）が含まれます。また、`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`をポーリングしたり、`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`からログを読み取ったりすることもできます。

## Git フォージとの統合 {#integrate-a-git-forge}

ランナープロトコルを持たないフォージは、小さなブリッジを介して接続します。このブリッジは、フォージ自体のサービスでも、フックから呼び出す関数でも構いません：

1. **プッシュ時**、フォージのプッシュフックがブリッジに到達します。ブリッジはフックを検証し、コミットに必要なチェックを決定し、ジョブのタイムアウト後に失効するリポジトリ用の読み取り専用クローントークンを発行します。
2. **各チェックに対して**、ブリッジは`idempotency_key`を`<repository>:<commit>:<check>`に設定してジョブを作成するため、再配信されたフックによって新しいジョブが作成されることはありません。返された`workflow_job_id`を保存し、フォージ内でチェックを pending 状態としてマークできます。
3. **`runner_job.started`および`runner_job.completed`受信時**、ブリッジはエンドポイントのシークレットを使用して`Tuist-Signature`ヘッダーを検証し、`workflow_job_id`または`idempotency_key`によってチェックを特定して、`conclusion`でフォージのコミットステータスを更新します。ステータスを Tuist ダッシュボードのジョブページにリンクすることもできます。
4. **プッシュによってコミットが置き換えられた場合**、ブリッジは古いコミット用に作成したジョブをキャンセルします。

## ジョブの実行方法 {#how-the-job-runs}

マシンは HTTPS 経由で`repository_url`から`commit_sha`を取得します。サーバーが SHA によるコミットの提供に対応していない場合は、代わりにコミットを含む必要がある`ref`を取得します。`clone_token`（指定した場合）は、リポジトリのホストに対してのみ`Authorization: Bearer <token>`として送信され、スクリプトやジョブログに到達することはありません。

スクリプトは、チェックアウトのルートディレクトリで、ログインシェル内の Bash で`set -eo pipefail`付きで実行されます。スクリプトが非ゼロのステータスで終了するか、`timeout_minutes`（デフォルトは 60、最大 360）を超えて実行されると、ジョブは失敗します。`env`と`secrets`に加えて、スクリプトからは`CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF`、および`TUIST_JOB_COMMIT_SHA`が参照できます。`secrets`の値はジョブログでマスクされます。

## 再試行と冪等性 {#idempotency}

各ジョブに、その用途を示す`idempotency_key`（例：`<repository>:<commit>:<check>`）を指定します。アカウント内で既に使用されているキーを持つリクエストは、既存のジョブをステータス 201 ではなく 200 で返し、何も新規作成しません。これにより、プッシュフックは重複ジョブのリスクなしにリクエストを再試行キューに渡すことができます。

Webhook の配信は、エンドポイントが 2xx ステータスで応答するまで再試行されるため、イベントが複数回届くことがあります。重複排除には、エンベロープの`id`、またはイベントタイプと組み合わせたジョブの`workflow_job_id`を使用してください。

## ジョブのキャンセル {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

どのマシンも開始していないジョブは直ちにキャンセルされます。実行中のジョブは数秒以内に停止し、完了イベントでは`cancelled`が報告されます。24 時間以内にどのマシンも開始しなかったジョブは自動的にキャンセルされます。

## キャッシングと信頼 {#trust}

リポジトリにプッシュできる任何人がジョブの実行内容を変更できるため、API ジョブは信頼されていないものとして扱われます。これらのジョブは、アカウントの共有<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>やキャッシュ署名権限を利用できません。ジョブのシークレット、スクリプト、クローントークンは暗号化されて保存され、ジョブが完了すると削除されます。
