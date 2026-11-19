---
{
  "title": "API",
  "titleTemplate": ":title · CIプロバイダー · ランナー · 機能 · ガイド · Tuist",
  "description": "独自のGitフォージやオーケストレーターからTuistランナーでジョブを実行します。1回のAPIリクエストでジョブを作成し、Webhookで後続処理を行います。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

独自のランナープロトコルを持たない Git フォージ、マージキュー、エージェントオーケストレーターは、Tuist Runners でジョブを直接実行できます。リクエスト 1 回でジョブを作成すると、選択した<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>の Tuist マシンがコミットをチェックアウトしてスクリプトを実行し、結果を Webhook エンドポイントに報告します。

## ジョブの実行 {#run-a-job}

1. **アカウントトークンを作成する**（スコープ: `account:runners:write`）：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **ジョブを作成する。** 一般的な呼び出し元は、push フックからこれを行い、マシンがリポジトリをクローンできるようにする短命トークンを使用します：

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

   レスポンスにはジョブと、その`workflow_job_id`が含まれます。これは Tuist ダッシュボードの**Runners**セクションにすぐに表示され、プロファイルのマシンが利用可能になるとすぐに開始されます。ウォーム状態のマシンなら通常数秒以内に開始します。

3. **ジョブを追跡する。**<.localized_link href="/guides/integrations/webhooks">Webhook エンドポイント</.localized_link>を`runner_job.started`および`runner_job.completed`に登録します。完了イベントにはジョブの`conclusion`（`success`、`failure`、または`cancelled`）が含まれます。`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`をポーリングしたり、`GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`からログを読み取ったりすることもできます。

## Git フォージとの統合 {#integrate-a-git-forge}

ランナープロトコルを持たないフォージは、小さなブリッジを通じて接続します。このブリッジは、フォージ自体のサービスでも、フックから呼び出す関数でも構いません：

1. **Push 時**、フォージの push フックがブリッジに到達します。ブリッジはフックを検証し、コミットに必要なチェックを決定し、ジョブのタイムアウト後に失効するリポジトリ用の読み取り専用クローントークンを発行します。
2. **各チェックに対して**、ブリッジは`idempotency_key`を`<repository>:<commit>:<check>`に設定してジョブを作成するため、フックが再配信されても新しいものは作成されません。返された`workflow_job_id`を保存し、フォージでチェックを pending 状態としてマークできます。
3. **`runner_job.started`および`runner_job.completed`時**、ブリッジはエンドポイントのシークレットを使って`Tuist-Signature`ヘッダーを検証し、`workflow_job_id`または`idempotency_key`によってチェックを見つけ、`conclusion`でフォージのコミットステータスを更新します。ステータスを Tuist ダッシュボードのジョブページにリンクすることもできます。
4. **Push によってコミットが置き換えられた場合**、ブリッジは古いコミット用に作成したジョブをキャンセルします。

## ジョブの実行方法 {#how-the-job-runs}

マシンは HTTPS 経由で`repository_url`から`commit_sha`を取得します。サーバーが SHA によるコミットの提供に対応していない場合は、代わりにコミットを含む必要がある`ref`を取得します。`clone_token`（指定した場合）は、リポジトリのホストに対してのみ`Authorization: Bearer <token>`として送信されます。スクリプトやジョブログに届くことはありません。

スクリプトは、チェックアウトのルートディレクトリで、ログインシェル内の Bash により`set -eo pipefail`付きで実行されます。スクリプトが非ゼロのステータスで終了するか、`timeout_minutes`（デフォルト 60、最大 360）を超えて実行されると、ジョブは失敗します。`env`および`secrets`に加え、スクリプトからは`CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF`、`TUIST_JOB_COMMIT_SHA`が見えます。`secrets`の値はジョブログでマスクされます。

## リトライと冪等性 {#idempotency}

各ジョブには、その用途を示す`idempotency_key`（例：`<repository>:<commit>:<check>`）を指定してください。アカウント内で既に使用されているキーを持つリクエストは、既存のジョブをステータス 200（201 ではなく）で返し、何も新規作成しません。これにより、push フックは重複ジョブのリスクなしにリクエストをリトライキューに渡せます。

Webhook の配信は、エンドポイントが 2xx ステータスで応答するまで再試行されるため、イベントが複数回届くことがあります。エンベロープの`id`、またはイベントタイプを組み合わせたジョブの`workflow_job_id`を使用して重複排除を行ってください。

## ジョブのキャンセル {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

どのマシンも開始していないジョブは即座にキャンセルされます。実行中のジョブは数秒以内に停止し、完了イベントでは`cancelled`が報告されます。24 時間以内にどのマシンも開始しないジョブは自動的にキャンセルされます。

## キャッシングと信頼 {#trust}

リポジトリに push できる任何人がジョブの実行内容を変更できるため、API ジョブは信頼されていないものとして扱われます。アカウントの共有<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリューム</.localized_link>やキャッシュ署名権限は付与されません。ジョブのシークレット、スクリプト、クローントークンは暗号化して保存され、ジョブ完了後に削除されます。
