---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 提供者 · 執行器 · 功能 · 指南 · Tuist",
  "description": "透過管線標籤選擇機器，在 Tuist 執行器上執行 GitLab CI 工作。"
}
---
# GitLab CI {#gitlab-ci}

<!-- @snippet: ./_invite-only -->

你的管線保留在 GitLab 中。Tuist 為每個作業提供隔離的 Linux 或 macOS 機器，並將日誌與結果回報至 GitLab 和 Tuist 儀表板。需要使用 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 與自建實例。

1. **建立 GitLab Runner。** 在專案的 **Settings → CI/CD → Runners** 中建立專案層級 Runner。你也可以使用群組層級 Runner。將所有要使用的 Tuist 設定檔標籤加入為 Runner 標籤，例如 `tuist-linux` 與 `tuist-macos`，並停用 **Run untagged jobs**。保留 GitLab 顯示的驗證權杖，其開頭為 `glrt-`。你不需要在自己的機器上安裝 Runner。
2. **在 Tuist 中連線一次。** 前往 **Settings → Integrations**，在 GitLab CI 卡片上選擇 **Connect**。輸入你的 GitLab URL 與 Runner 驗證權杖。此連線可服務使用不同設定檔的作業。權杖會以加密方式儲存，且不會再次顯示。可選地，加入 API 存取權杖，讓合併請求管線能夠儲存快取卷；請參閱 [Merge request pipelines](#merge-request-pipelines)。
3. **在每個作業中選擇機器。** 在作業的 `tags` 中設定恰好一個 <.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。允許其他標籤，前提是已註冊的 GitLab Runner 也擁有這些標籤：

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。作業會出現在 **Runners** 下方，並提供返回 GitLab 作業、日誌與機器指標的連結。GitLab 會在作業執行期間接收日誌；Tuist 則在作業完成時接收遮罩後的日誌。

Tuist 會從每個指派讀取 `CI_JOB_TAGS`，並在已連線的 Tuist 帳戶內解析設定檔。它不會從 `CI_RUNNER_TAGS` 推斷機器，也不會使用預設設定檔。若缺少、未知或存在多個 Tuist 設定檔標籤，獲取的作業將會失敗，並在 GitLab 日誌中提供說明。不要在你的管線變數中覆寫 `CI_JOB_TAGS`。

## Execution environment {#execution-environment}

作業在隔離機器內使用 GitLab 的 **shell executor**。檢出、CI 變數、`before_script`、`script`、`after_script`、成品與取消都由 GitLab Runner 處理。管線的 `image:` 與 `services:` 設定不會設定此 Shell 環境；請使用安裝在 <.localized_link href="/guides/features/runners/profiles">runner image</.localized_link> 上的工具，或在你的腳本中安裝它們。

可重複使用的 Runner 驗證權杖會留在 Tuist 伺服器上。機器僅接收其指派作業的憑證。目前對 GitLab 作業保留快取簽署授權。自訂 Linux 快取卷會透過 GitLab 的 API 驗證作業身分並儲存權限；可覆寫的 CI 變數無法建立信任。

一旦 Tuist 取得作業，GitLab 便會將其標記為執行中，並開始計時超時。當 Tuist 已取得的作業耗盡你帳戶的並行限制時，後續作業會在 GitLab 中保持擱置。已取得的作業會等待機器，最多達到其作業超時時間，上限為 12 小時。若到時仍無可用機器，Tuist 會以 `runner_system_failure` 使指派失敗，上述重試政策會讓 GitLab 重試該作業。相同的政策也涵蓋遺失的 Runner 機器。

## Rotating tokens and disconnecting {#rotating-tokens-and-disconnecting}

更新連線的權杖並選擇 **Save changes** 以輪替它們。將權杖留空會保留現有的憑證。

**Disconnect** 會停止獲取並使等待中的指派失敗。執行中的作業會以其自身的憑證繼續進行。若無法連線至 GitLab，Tuist 會保留已停用的連線，同時重試取消等待中的指派。待這些指派穩定後，連線會被移除。

## Cache volumes {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link> 在作業之間保留 Xcode、模組與 Gradle 快取及其他目錄。在檢出之後、在使用它們的命令之前加入這些目錄。

### Merge request pipelines {#merge-request-pipelines}

專案的推送、排程與網頁管線會將變更儲存至快取卷。合併請求管線會使用快取，且僅在連線具有 API 存取權杖時才會儲存變更：

1. 在 GitLab 中，建立具備 **Reporter** 角色與 `read_api` 範圍的專案或群組存取權杖。群組權杖涵蓋群組內所有在 Tuist Runner 上執行的專案。
2. 在 **Settings → Integrations** 中，將其貼入 GitLab CI 卡片上的 **API access token**，並選擇 **Save changes**。

接著，Tuist 會讀取每個合併請求管線的合併請求。從專案本身分支開啟的合併請求管線，會將變更儲存在合併請求的來源分支下，因此 Runner 設定檔的 <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link> 會套用至該分支。來自分叉的合併請求永遠不會儲存。若 Tuist 無法讀取合併請求，作業仍會執行並使用快取，但其變更會被捨棄。
