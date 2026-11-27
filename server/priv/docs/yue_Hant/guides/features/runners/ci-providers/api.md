---
{
  "title": "API",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺你自己嘅 git forge 或協調器上透過 Tuist Runners 執行工作：用一個 API 請求建立工作，並透過 webhook 追蹤進度。"
}
---
# API {#api}

沒有自己 runner 協定的 Git forge、合併佇列同代理協調器，可以直接喺 Tuist Runners 上執行工作。你只需要發出一次請求來建立工作，你所選<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>對應嘅 Tuist 機器會 checkout 該 commit 並執行你嘅腳本，然後 Tuist 會將結果回報到你嘅 webhook 端點。

## 執行工作 {#run-a-job}

1. **建立帳戶權杖**，並帶有 `account:runners:write` 權限：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **建立工作。** 一般呼叫者會喺 push hook 中執行此操作，使用一個短效權杖讓機器 clone 儲存庫：

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

   回應係該工作，包含其 `workflow_job_id`。佢會立即出現喺你 Tuist 儀表板嘅 **Runners** 區域，並且一旦有屬於該設定檔嘅機器空闲就會開始執行。熱機通常喺幾秒內就會開始執行。

3. **追蹤工作進度。** 訂閱 <.localized_link href="/guides/integrations/webhooks">webhook 端點</.localized_link> 以接收 `runner_job.started` 同 `runner_job.completed` 事件。完成事件會攜帶工作嘅 `conclusion`：`success`、`failure` 或 `cancelled`。你也可以輪詢 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` 並從 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` 讀取日誌。

## 整合 Git forge {#integrate-a-git-forge}

沒有 runner 協定嘅 forge 可以透過一個小型橋接器連接，它可以是 forge 本身嘅服務，或者是從其 hooks 調用嘅函數：

1. **當 push 時**，forge 嘅 push hook 會到達橋接器。橋接器驗證 hook，決定該 commit 需要哪些檢查，併為儲存庫生成一個只讀 clone 權杖，該權杖會喺工作超時後過期。
2. **對於每個檢查**，橋接器會建立一個工作，並將 `idempotency_key` 設置為 `<repository>:<commit>:<check>`，這樣重新發送 hook 時不會建立新工作。它會儲存返回嘅 `workflow_job_id`，並可以喺 forge 中將檢查標記為 pending。
3. **當收到 `runner_job.started` 同 `runner_job.completed`** 時，橋接器使用端點密鑰驗證 `Tuist-Signature` 標頭，通過 `workflow_job_id` 或 `idempotency_key` 找到對應檢查，並使用 `conclusion` 更新 forge 中嘅 commit 狀態。它可以將狀態連結到 Tuist 儀表板中工作嘅頁面。
4. **當 push 取代某個 commit 時**，橋接器會取消它為舊 commit 建立嘅工作。

## 工作如何運行 {#how-the-job-runs}

機器通過 HTTPS 從 `repository_url` 獲取 `commit_sha`。如果伺服器無法通過 SHA 提供 commit，它會改為獲取 `ref`，其中必須包含該 commit。`clone_token`（如果你提供咗）只會作為 `Authorization: Bearer <token>` 發送給儲存庫嘅主機。它永遠不會到達你嘅腳本或工作日誌。

你嘅腳本會喺 login shell 中使用 Bash 運行，帶有 `set -eo pipefail`，並從 checkout 嘅根目錄開始。當腳本以非零狀態退出或運行超過 `timeout_minutes`（預設為 60，最高可達 360）時，工作會失敗。除了你嘅 `env` 同 `secrets` 之外，腳本還可以訪問 `CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF` 同 `TUIST_JOB_COMMIT_SHA`。`secrets` 嘅值會喺工作日誌中被遮蔽。

## 重試與冪等性 {#idempotency}

為每個工作提供一個 `idempotency_key` 來標示其用途，例如 `<repository>:<commit>:<check>`。如果請求使用咗帳戶中已經存在嘅鍵，則會返回現有工作，狀態碼為 200 而非 201，並且不會建立新工作。這讓你嘅 push hook 可以將請求放入重試佇列，而無需擔心重複工作。

Webhook 交付會不斷重試，直到你嘅端點返回 2xx 狀態碼，因此事件可能會多次到達。使用信封嘅 `id`，或者工作嘅 `workflow_job_id` 連同事件類型來進行去重。

## 取消工作 {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

尚未被任何機器啟動嘅工作會立即被取消。正在運行嘅工作會喺幾秒內停止，其完成事件會報告 `cancelled`。如果 24 小時內沒有任何機器啟動工作，則會自動取消。

## 快取與信任 {#trust}

任何能夠 push 到儲存庫嘅人都可以改變工作運行嘅內容，因此 API 工作被視為不受信任：它們無法訪問你帳戶共享嘅 <.localized_link href="/guides/features/runners/cache-volumes">快取卷</.localized_link> 或其快取簽名授權。工作嘅密鑰、腳本同 clone 權杖會被加密儲存，並喺工作完成後刪除。
