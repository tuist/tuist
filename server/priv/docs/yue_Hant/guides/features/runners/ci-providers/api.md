---
{
  "title": "API",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "透過你自家嘅 git forge 或調度器，喺 Tuist Runners 上執行工作：用一個 API 請求建立工作，並透過 webhook 追蹤進度。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

冇自己 runner 協定嘅 Git forges、merge queues 同 agent orchestrators，可以直接喺 Tuist Runners 上執行 job。你只需要發出一次請求來建立 job，一台你所選<.localized_link href="/guides/features/runners/profiles">profile</.localized_link>嘅 Tuist 機器就會 checkout 該 commit 並執行你嘅腳本，然後 Tuist 會將結果報告到你嘅 webhook endpoint。

## 執行 job {#run-a-job}

1. **建立帳戶 token**，並附上 `account:runners:write` scope：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **建立 job。** 一般呼叫者會從其 push hook 執行此操作，使用一個短期 token 讓機器 clone 儲存庫：

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

   回應係該 job，包含其 `workflow_job_id`。佢會立即出現喺你 Tuist 儀表板嘅 **Runners** 部分，並且一旦有屬於該 profile 嘅機器空闲就會開始執行。暖機嘅機器通常喺幾秒內就會開始執行。

3. **追蹤 job。** 訂閱一個 <.localized_link href="/guides/integrations/webhooks">webhook endpoint</.localized_link> 以接收 `runner_job.started` 同 `runner_job.completed` 事件。完成事件會攜帶 job 嘅 `conclusion`：`success`、`failure` 或 `cancelled`。你亦可以輪詢 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` 並從 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` 讀取日誌。

## 整合 git forge {#integrate-a-git-forge}

冇 runner 協定嘅 forge 會透過一個小型橋接器連接，呢個橋接器可以係 forge 本身嘅服務，或者係佢從 hooks 呼叫嘅函數：

1. **當 push 時**，forge 嘅 push hook 會到達橋接器。橋接器會驗證 hook，決定 commit 需要哪些檢查，並為儲存庫鑄造一個只讀 clone token，該 token 會喺 job 超時後過期。
2. **對於每個檢查**，橋接器會建立一個 job，並將 `idempotency_key` 設定為 `<repository>:<commit>:<check>`，這樣重新發送 hook 時唔會建立新嘅 job。佢會儲存返回嘅 `workflow_job_id`，並可以喺 forge 中將檢查標記為 pending。
3. **當收到 `runner_job.started` 同 `runner_job.completed`** 時，橋接器會使用 endpoint 嘅 secret 驗證 `Tuist-Signature` header，通過 `workflow_job_id` 或 `idempotency_key` 找到檢查，並用 `conclusion` 更新 forge 嘅 commit 狀態。佢可以將狀態連結到 Tuist 儀表板中 job 嘅頁面。
4. **當 push 取代咗某個 commit**，橋接器會取消佢為較舊 commit 建立嘅 job。

## Job 點樣執行 {#how-the-job-runs}

機器會通過 HTTPS 從 `repository_url` 獲取 `commit_sha`。如果伺服器唔能按 SHA 提供 commit，佢會改為獲取 `ref`，其中必須包含該 commit。如果你提供 `clone_token`，佢只會作為 `Authorization: Bearer <token>` 發送給儲存庫嘅主機。佢永遠唔會到達你嘅腳本或 job 日誌。

你嘅腳本會喺 login shell 中使用 Bash 執行，帶有 `set -eo pipefail`，並從 checkout 嘅根目錄開始。當腳本以非零狀態退出或運行超過 `timeout_minutes`（預設為 60，最高可達 360）時，job 會失敗。除了你嘅 `env` 同 `secrets` 之外，腳本還可以訪問 `CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF` 同 `TUIST_JOB_COMMIT_SHA`。`secrets` 嘅值會喺 job 日誌中被遮蔽。

## 重試與冪等性 {#idempotency}

為每個 job 提供一個 `idempotency_key` 來指明其用途，例如 `<repository>:<commit>:<check>`。如果請求使用咗帳戶中已經存在嘅 key，則會返回現有 job，狀態碼為 200 而非 201，並且唔會建立新嘅 job。這讓你嘅 push hook 可以將請求放入重試隊列，而唔必擔心重複 job。

Webhook 交付會不斷重試，直到你嘅 endpoint 返回 2xx 狀態碼，因此事件可能會多次到達。使用信封嘅 `id`，或者結合事件類型使用 job 嘅 `workflow_job_id` 來進行去重。

## 取消 job {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

未被任何機器啟動嘅 job 會立即被取消。正在運行嘅 job 會喺幾秒內停止，其完成事件會報告 `cancelled`。24 小時內未被任何機器啟動嘅 job 會自動被取消。

## 快取與信任 {#trust}

任何可以 push 到儲存庫嘅人都可以改變 job 執行嘅內容，因此 API job 被視為不可信：佢哋無法訪問你帳戶共享嘅 <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link> 或其快取簽名授權。Job 嘅 secrets、腳本同 clone token 會以加密方式儲存，並喺 job 完成後刪除。
