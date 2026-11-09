---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 提供者 · 執行器 · 功能 · 指南 · Tuist",
  "description": "透過管線標籤選擇機器，在 Tuist 執行器上執行 GitLab CI 工作。"
}
---
# GitLab CI {#gitlab-ci}

<!-- @snippet: ./_invite-only -->

你的流水線仍留在 GitLab。Tuist 為每個作業提供隔離的 Linux 或 macOS 機器，並將日誌與結果回報給 GitLab 和 Tuist 儀表板。需要使用 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 與自管實例。

1. **建立 GitLab runner。** 在專案的**Settings → CI/CD → Runners**中，建立專案 runner。你也可以使用群組 runner。將你想要使用的 Tuist 設定檔標籤全部加入為 runner 標籤，例如`tuist-linux`與`tuist-macos`，並停用**Run untagged jobs**。保留 GitLab 顯示的驗證權杖，其開頭為`glrt-`。你不需要在自己的機器上安裝 runner。
2. **在 Tuist 中連線一次。** 在**Settings → Integrations**中，於 GitLab CI 卡片上選擇**Connect**。輸入你的 GitLab URL 與 runner 驗證權杖。此連線可服務使用不同設定檔的作業。權杖會以加密方式儲存，之後不會再次顯示。你可以選擇新增 API 存取權杖，讓合併請求流水線能夠儲存快取磁碟區；請參閱[Merge request pipelines](#merge-request-pipelines)。
3. **在每個作業中選擇機器。** 在作業的`tags`中設定恰好一個<.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。允許其他標籤，前提是已註冊的 GitLab runner 也擁有這些標籤：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。作業會出現在**Runners**下方，並提供連結回到 GitLab 作業、日誌與機器指標。GitLab 會在作業執行期間接收日誌；Tuist 則在作業完成時接收遮罩後的日誌。

Tuist 會從每個指派讀取`CI_JOB_TAGS`，並在已連線的 Tuist 帳戶中解析設定檔。它不會從`CI_RUNNER_TAGS`推斷機器，也不會使用預設設定檔。若缺少、未知或存在多個 Tuist 設定檔標籤，已取得的作業將會失敗，並在 GitLab 日誌中提供說明。不要在你的流水線變數中覆寫`CI_JOB_TAGS`。

## Execution environment {#execution-environment}

作業在隔離機器內使用 GitLab 的**shell executor**。簽出、CI 變數、`before_script`、`script`、`after_script`、產物與取消都由 GitLab Runner 處理。流水線的`image:`與`services:`設定不會設定此 shell 環境；請使用安裝在<.localized_link href="/guides/features/runners/profiles">runner image</.localized_link>上的工具，或在你的腳本中安裝它們。

可重複使用的 runner 驗證權杖會留在 Tuist 伺服器上。機器僅取得其指派作業的憑證。目前對 GitLab 作業暫停快取簽署授權。自訂 Linux 快取磁碟區會透過 GitLab 的 API 驗證作業身分與儲存權限；可覆寫的 CI 變數無法建立信任。

一旦 Tuist 取得作業，GitLab 即將其標記為執行中，並開始計算逾時。當 Tuist 已取得的作業耗盡你帳戶的並行限制時，後續作業會在 GitLab 中保持待處理。已取得的作業會等待機器，最多等到其作業逾時（上限為 12 小時）。若到時仍無可用機器，Tuist 會以`runner_system_failure`使該指派失敗，而上述重試政策會讓 GitLab 重試。相同的政策也涵蓋遺失的 runner 機器。

## Rotating tokens and disconnecting {#rotating-tokens-and-disconnecting}

更新連線的權杖並選擇**Save changes**以輪替它們。將權杖留空會保留現有的憑證。

**Disconnect**會停止取得作業，並使等待中的指派失敗。執行中的作業會以其自身憑證繼續執行。若無法連線至 GitLab，Tuist 會保留已停用的連線，同時重試取消等待中的指派。當這些指派穩定後，連線會被移除。

## Cache volumes {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>在作業之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在簽出之後、在使用這些目錄的命令之前加入它們。

### Merge request pipelines {#merge-request-pipelines}

專案的推送、排程與網頁流水線會將其變更儲存到快取磁碟區。合併請求流水線會使用快取，但僅在連線具有 API 存取權杖時才會儲存其變更：

1. 在 GitLab 中，建立具有**Reporter**角色與`read_api`範圍的專案或群組存取權杖。群組權杖涵蓋在 Tuist runners 上執行的群組內所有專案。
2. 在**Settings → Integrations**中，將其貼到 GitLab CI 卡片上的**API access token**，並選擇**Save changes**。

接著 Tuist 會讀取每個合併請求流水線的合併請求。從專案本身分支開啟的合併請求，其流水線會將變更儲存在合併請求的來源分支下，因此 runner 設定檔的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link>會套用到該分支。來自分叉的合併請求永遠不會儲存。若 Tuist 無法讀取合併請求，作業仍會執行並使用快取，但其變更會被捨棄。
