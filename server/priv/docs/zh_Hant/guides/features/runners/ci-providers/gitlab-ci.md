---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "透過管線標籤選擇機器，在 Tuist Runners 上執行 GitLab CI 工作。"
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以申請帳號存取權限。

你的流水線仍保留在 GitLab 中。Tuist 為每個工作提供一台隔離的 Linux 或 macOS 機器，並將其日誌與結果回報至 GitLab 和 Tuist 儀表板。需要 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 與自管實例。

1. **建立 GitLab runner。** 在專案的**設定 → CI/CD → Runners**中，建立專案 runner。你也可以使用群組 runner。將所有你想使用的 Tuist 設定檔標籤加入為 runner 標籤，例如 `tuist-linux` 和 `tuist-macos`，並停用**執行未標記的工作**。保留 GitLab 顯示的驗證令牌，其開頭為 `glrt-`。你不需要在自己的機器上安裝 runner。
2. **在 Tuist 中連接一次。** 在**設定 → 整合**中，於 GitLab CI 卡片上選擇**連接**。輸入你的 GitLab URL 與 runner 驗證令牌。此連接可服務使用不同設定檔的工作。令牌會加密儲存，且不會再次顯示。可選地，新增 API 存取令牌，以便合併請求流水線可以儲存快取卷；請參閱[合併請求流水線](#merge-request-pipelines)。
3. **為每個工作選擇機器。** 在工作的`tags`中設定恰好一個<.localized_link href="/guides/features/runners/profiles">Tuist 設定檔標籤</.localized_link>。只要已註冊的 GitLab runner 也擁有其他標籤，則允許使用這些標籤：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。工作會出現在**Runners**下方，並附有連結回 GitLab 工作、日誌與機器指標。GitLab 會在工作執行期間接收日誌；Tuist 會在工作完成時接收遮罩後的日誌。

Tuist 從每個分配中讀取`CI_JOB_TAGS`，並在已連接的 Tuist 帳號內解析設定檔。它不會從`CI_RUNNER_TAGS`推斷機器，也不會使用預設設定檔。若缺少、未知或存在多個 Tuist 設定檔標籤，已取得的工作將會失敗，並在 GitLab 日誌中提供說明。請勿在你的流水線變數中覆寫`CI_JOB_TAGS`。

## 執行環境 {#execution-environment}

工作在隔離機器內使用 GitLab 的**shell executor**。Checkout、CI 變數、`before_script`、`script`、`after_script`、產物與取消作業均由 GitLab Runner 處理。流水線的`image:`與`services:`設定不會設定此 shell 環境；請使用安裝在<.localized_link href="/guides/features/runners/profiles">runner 映像</.localized_link>上的工具，或在你的腳本中安裝它們。

可重複使用的 runner 驗證令牌會保留在 Tuist 伺服器上。機器僅接收其指派工作的憑證。GitLab 工作目前不授予快取簽署權限。自訂 Linux 快取卷會透過 GitLab 的 API 驗證工作身分與儲存權限；可覆寫的 CI 變數無法建立信任關係。

一旦 Tuist 取得工作，GitLab 即將其標記為執行中，並開始計時超時。當 Tuist 已取得的工作耗盡你帳號的並行限制時，後續工作會在 GitLab 中保持待處理狀態。已取得的工作會等待機器，最多達到其工作超時時間（最長 12 小時）。若屆時仍無可用機器，Tuist 會以`runner_system_failure`使該分配失敗，而上述重試政策會讓 GitLab 重試該工作。相同的政策也適用於遺失的 runner 機器。

## 輪換令牌與斷開連接 {#rotating-tokens-and-disconnecting}

更新連接的令牌並選擇**儲存變更**以輪換它們。將令牌留空會保留現有的憑證。

**斷開連接**會停止取得作業，並使等待中的分配失敗。執行中的工作會繼續使用其自身的憑證。若無法連線至 GitLab，Tuist 會保留已停用的連接，同時重試取消等待中的分配。一旦這些分配 settled，連接就會被移除。

## 快取卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷</.localized_link>在不同工作之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在 checkout 之後、在使用它們的命令之前加入這些卷。

### 合併請求流水線 {#merge-request-pipelines}

專案的推送、排程與網頁流水線會將其變更儲存至快取卷。合併請求流水線會使用快取，但僅在連接具有 API 存取令牌時才會儲存其變更：

1. 在 GitLab 中，建立具備**Reporter**角色與`read_api`範圍的專案或群組存取令牌。群組令牌涵蓋群組中所有在 Tuist runners 上執行的專案。
2. 在**設定 → 整合**中，將其貼入 GitLab CI 卡片上的**API 存取令牌**欄位，並選擇**儲存變更**。

接著，Tuist 會讀取每個合併請求流水線的合併請求。從專案本身分支開啟的合併請求，其流水線會將變更儲存在合併請求的來源分支下，因此 runner 設定檔的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">分支設定</.localized_link>會套用於該分支。來自分叉的合併請求永遠不會儲存。若 Tuist 無法讀取合併請求，工作仍會執行並使用快取，但其變更會被捨棄。
