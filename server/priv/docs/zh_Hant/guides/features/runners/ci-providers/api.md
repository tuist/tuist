---
{
  "title": "API",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "從你自己的 Git 平台或協調器在 Tuist 執行器上執行工作：透過單一 API 請求建立工作，並使用 Webhook 追蹤進度。"
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

沒有自有執行器協定的 Git 託管平台、合併佇列與代理協調器，可以直接在 Tuist Runners 上執行工作。你只需發出一次請求即可建立工作；你所選<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>對應的 Tuist 機器會检出該提交並執行你的腳本，Tuist 則將結果回報至你的 webhook 端點。

## 執行工作 {#run-a-job}

1. **建立帳戶權杖**，並賦予 `account:runners:write` 範圍：

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **建立工作。** 一般呼叫者會在推送鉤子中執行此操作，並使用短期權杖讓機器克隆儲存庫：

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

   回應即為該工作，其中包含其 `workflow_job_id`。它會立即出現在 Tuist 儀表板的 **執行器** 區段，並在所選設定檔的機器有空閒時立刻開始執行。處於暖機狀態的機器通常會在數秒內啟動。

3. **追蹤工作進度。** 將 <.localized_link href="/guides/integrations/webhooks">webhook 端點</.localized_link> 訂閱至 `runner_job.started` 與 `runner_job.completed`。完成事件會攜帶工作的 `conclusion`：`success`、`failure` 或 `cancelled`。你也可以輪詢 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}`，並從 `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs` 讀取日誌。

## 整合 Git 託管平台 {#integrate-a-git-forge}

沒有執行器協定的託管平台可透過一個小型橋接服務進行連接，該橋接可以是託管平台本身的服務，或是由其鉤子呼叫的函式：

1. **推送時**，託管平台的推送鉤子會觸達橋接服務。橋接服務會驗證鉤子、決定該提交需要哪些檢查，並為儲存庫簽發一個唯讀克隆權杖，該權杖會在工作超時後過期。
2. **針對每項檢查**，橋接服務會建立一項工作，並將 `idempotency_key` 設為 `<repository>:<commit>:<check>`，因此重新遞送鉤子時不會建立新的工作。它會儲存回傳的 `workflow_job_id`，並可在託管平台中將該檢查標記為待處理。
3. **當收到 `runner_job.started` 與 `runner_job.completed`** 時，橋接服務會使用端點密鑰驗證 `Tuist-Signature` 標頭，依據 `workflow_job_id` 或 `idempotency_key` 找到對應檢查，並以 `conclusion` 更新託管平台的提交狀態。它可以將狀態連結至 Tuist 儀表板中的工作頁面。
4. **當推送取代既有提交時**，橋接服務會取消它為較舊提交所建立的工作。

## 工作如何執行 {#how-the-job-runs}

機器會透過 HTTPS 從 `repository_url` 取得 `commit_sha`。若伺服器無法依 SHA 提供該提交，則會改為取得 `ref`，且該參考必須包含該提交。`clone_token`（若有提供）僅會以 `Authorization: Bearer <token>` 的形式傳送給儲存庫主機，絕不會進入你的腳本或工作日誌。

你的腳本會在登入 shell 中以 Bash 執行，並啟用 `set -eo pipefail`，從檢出目錄的根目錄開始。當腳本以非零狀態碼結束，或執行時間超過 `timeout_minutes`（預設為 60，最高可設為 360）時，工作會失敗。除了你的 `env` 與 `secrets` 之外，腳本還會看到 `CI=true`、`TUIST_JOB_ID`、`TUIST_JOB_NAME`、`TUIST_JOB_REPOSITORY_URL`、`TUIST_JOB_REF` 與 `TUIST_JOB_COMMIT_SHA`。`secrets` 的值在工作日誌中會被遮蔽。

## 重試與冪等性 {#idempotency}

為每項工作提供一個 `idempotency_key` 來說明其用途，例如 `<repository>:<commit>:<check>`。若請求使用的金鑰已在你的帳戶中使用過，系統會回傳既有的工作（狀態碼為 200 而非 201），且不會建立新工作。這讓你的推送鉤子可以將請求放入重試佇列，而無需擔心產生重複工作。

Webhook 投遞會重試直到你的端點回覆 2xx 狀態碼，因此同一事件可能多次送達。請使用信封的 `id`，或結合事件的類型與工作的 `workflow_job_id` 來進行去重。

## 取消工作 {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

尚未被任何機器啟動的工作會立即取消。正在執行的工作會在數秒內停止，其完成事件會回報 `cancelled`。若在 24 小時內沒有任何機器啟動工作，該工作會自動取消。

## 快取與信任 {#trust}

任何能推送到儲存庫的人都能改變工作執行的內容，因此 API 工作被視為不可信：它們無法存取你帳戶共用的 <.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>，也無法使用快取簽署授權。工作的密鑰、腳本與克隆權杖會以加密方式儲存，並在工作完成後刪除。
