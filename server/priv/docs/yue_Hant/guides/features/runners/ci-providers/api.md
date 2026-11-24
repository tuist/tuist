---
{
  "title": "API",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "透過你嘅 Git Forge 或編排器喺 Tuist Runners 上執行工作：用一個 API 請求建立工作，並透過 webhook 追蹤進度。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

冇自己 runner 協議嘅 Git forge、merge queue 同 agent orchestrator，都可以直接喺 Tuist Runners 上執行 job。你只需發出一個請求就可以建立 job；一部你所選 <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> 嘅 Tuist 機器會 checkout 該 commit 並執行你嘅 script，然後 Tuist 會將結果回報到你嘅 webhook endpoint。

## 執行 job {#run-a-job}

1. **建立帳戶 token**，並賦予 `account:runners:write` 權限：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **建立 job。** 一般呼叫者會喺 push hook 中執行呢一步，使用一個短效 token，讓機器可以 clone 儲存庫：

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

   回應會包含該 job 及其 `workflow_job_id`。佢會立即出現喺你 Tuist 儀表板嘅 **Runners** 區段，並且一旦有符合 profile 嘅機器空閒就會開始執行。處於 warm 狀態嘅機器通常幾秒內就會啟動。

3. **追蹤 job。** 將 <.localized_link href="/guides/integrations/webhooks">webhook endpoint</.localized_link> 訂閱 `runner_job.started` 同 `runner_job.completed`。完成事件會攜帶 job 嘅 `conclusion`：`success`、`failure` 或 `cancelled`。你亦可以輪詢 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`，並從 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` 讀取日誌。

## 整合 git forge {#integrate-a-git-forge}

冇 runner 協議嘅 forge 會透過一個小型橋接器連接，該橋接器可以是 forge 本身嘅服務，或者係佢從 hook 中呼叫嘅函數：

1. **當 push 時**，forge 嘅 push hook 會到達橋接器。橋接器會驗證 hook，決定該 commit 需要哪些檢查，併為儲存庫簽發一個唯讀 clone token，該 token 會喺 job 超時後過期。
2. **對於每個檢查**，橋接器會建立一個 job，並將 `idempotency_key` 設定為 `<repository>:<commit>:<check>`，這樣即使 hook 被重新傳送，亦不會建立新嘅 job。佢會儲存返回嘅 `workflow_job_id`，並可以喺 forge 中將該檢查標記為 pending。
3. **當收到 `runner_job.started` 同 `runner_job.completed`** 時，橋接器會使用 endpoint 嘅 secret 驗證 `Tuist-Signature` header，透過 `workflow_job_id` 或 `idempotency_key` 找到對應檢查，並用 `conclusion` 更新 forge 嘅 commit 狀態。佢可以將狀態連結到 Tuist 儀表板中該 job 嘅頁面。
4. **當一次 push 取代咗某個 commit**，橋接器會取消佢為較舊 commit 所建立嘅 job。

## job 點樣執行 {#how-the-job-runs}

機器會透過 HTTPS 從 `repository_url` 獲取 `commit_sha`。如果伺服器無法按 SHA 提供 commit，佢會改為獲取 `ref`，其中必須包含該 commit。如果你提供 `clone_token`，佢只會以 `Authorization: Bearer <token>` 嘅形式發送畀儲存庫主機。佢永遠唔會暴露俾你嘅 script 或 job 日誌。

你嘅 script 會喺 login shell 中使用 Bash 執行，並啟用 `set -eo pipefail`，工作目錄為 checkout 嘅根目錄。當 script 以非零狀態退出，或者運行時間超過 `timeout_minutes`（預設為 60，最高可達 360）時，job 會失敗。除咗你嘅 `env` 同 `secrets` 之外，script 仲會見到 `CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF` 同 `TUIST_JOB_COMMIT_SHA`。`secrets` 嘅值會喺 job 日誌中被遮罩。

## 重試與冪等性 {#idempotency}

為每個 job 提供一個 `idempotency_key` 來指明其用途，例如 `<repository>:<commit>:<check>`。如果請求使用咗帳戶中已經存在嘅 key，系統會返回現有 job（狀態碼為 200 而非 201），而唔會建立新 job。這讓你嘅 push hook 可以將請求放入重試隊列，而唔必擔心產生重複 job。

Webhook 投遞會不斷重試，直到你嘅 endpoint 回應 2xx 狀態碼為止，因此事件可能會到達多次。請使用信封嘅 `id`，或者結合事件類型使用 job 嘅 `workflow_job_id` 來進行去重。

## 取消 job {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

尚未被任何機器啟動嘅 job 會立即被取消。正在運行嘅 job 會在幾秒內停止，其完成事件會報告 `cancelled`。如果一個 job 喺 24 小時內都冇被任何機器啟動，它會被自動取消。

## 快取與信任 {#trust}

任何能夠 push 到儲存庫嘅人都可以改變 job 執行嘅內容，因此 API job 會被視為不可信：佢哋無法存取你帳戶共享嘅 <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link> 或其快取簽署授權。job 嘅 secrets、script 同 clone token 會以加密方式儲存，並喺 job 完成後刪除。
