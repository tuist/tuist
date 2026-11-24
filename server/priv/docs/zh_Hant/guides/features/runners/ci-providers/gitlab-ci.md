---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 執行器上執行 GitLab CI 工作，並透過管線標籤選擇機器。"
}
---
# GitLab CI {#gitlab-ci}

你的管線保留在 GitLab 中。Tuist 為每個工作提供一台隔離的 Linux 或 macOS 機器，並將日誌與結果回報給 GitLab 和 Tuist 儀表板。需要 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 與自建實例。

1. **建立 GitLab runner。** 在專案的 **Settings → CI/CD → Runners** 中，建立專案 runner。你也可以使用群組 runner。將你想要使用的 Tuist 設定檔標籤加入為 runner 標籤，例如 `tuist-linux` 和 `tuist-macos`，並停用 **Run untagged jobs**。保留 GitLab 顯示的驗證權杖，其開頭為 `glrt-`。你不需要在自己的機器上安裝 runner。
2. **在 Tuist 中連接一次。** 在 **Settings → Integrations** 中，於 GitLab CI 卡片上選擇 **Connect**。輸入你的 GitLab URL 與 runner 驗證權杖。此連線可以服務使用不同設定檔的工作。權杖會以加密方式儲存，且不會再次顯示。你可以選擇新增 API 存取權杖，讓合併請求管線能夠儲存快取磁碟區；請參閱 [Merge request pipelines](#merge-request-pipelines)。
3. **在每個工作中選擇機器。** 在工作的 `tags` 中設定恰好一個 <.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。只要已註冊的 GitLab runner 也擁有其他標籤，就可以使用它們：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。工作會出現在 **Runners** 下方，並提供返回 GitLab 工作、日誌與機器指標的連結。GitLab 會在工作執行期間接收日誌；Tuist 會在工作完成時接收遮罩後的日誌。

Tuist 會從每個指派讀取 `CI_JOB_TAGS`，並在已連接的 Tuist 帳戶中解析設定檔。它不會從 `CI_RUNNER_TAGS` 推斷機器，也不會使用預設設定檔。若缺少、未知或存在多個 Tuist 設定檔標籤，已取得的工作將會失敗，並在 GitLab 日誌中提供說明。請勿在你的管線變數中覆寫 `CI_JOB_TAGS`。

## Execution environment {#execution-environment}

工作在隔離機器內使用 GitLab 的 **shell executor**。簽出、CI 變數、`before_script`、`script`、`after_script`、產物與取消由 GitLab Runner 處理。管線的 `image:` 與 `services:` 設定不會設定此 shell 環境；請使用安裝在 <.localized_link href="/guides/features/runners/profiles">runner image</.localized_link> 上的工具，或在你的腳本中安裝它們。

可重複使用的 runner 驗證權杖會留在 Tuist 伺服器上。機器只會收到其指派工作的憑證。目前對 GitLab 工作保留快取簽署授權。自訂 Linux 快取磁碟區會透過 GitLab 的 API 驗證工作身分與儲存權限；可覆寫的 CI 變數無法建立信任。

一旦 Tuist 取得工作，GitLab 就會將工作標記為執行中，並開始計算其逾時時間。當 Tuist 已取得的工作耗盡你帳戶的併發限制時，其他工作會在 GitLab 中保持待處理狀態。已取得的等候機器時間最多為其工作逾時時間，上限為 12 小時。若到時仍無可用機器，Tuist 會以 `runner_system_failure` 使指派失敗，上述重試政策會讓 GitLab 重試該工作。相同的政策也涵蓋遺失的 runner 機器。

## Rotating tokens and disconnecting {#rotating-tokens-and-disconnecting}

更新連線的權杖並選擇 **Save changes** 以輪換它們。將權杖留空會保留現有的憑證。

**Disconnect** 會停止取得並使等待中的指派失敗。執行中的工作會以其自身憑證繼續執行。若無法連線至 GitLab，Tuist 會保留已停用的連線，同時重試取消等待中的指派。一旦這些指派穩定後，連線就會被移除。

## Cache volumes {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link> 在工作之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在簽出之後、在使用它們的命令之前加入它們。

### Merge request pipelines {#merge-request-pipelines}

專案的推送、排程與網頁管線會將其變更儲存到快取磁碟區。合併請求管線會使用快取，但只有在連線具有 API 存取權杖時才會儲存其變更：

1. 在 GitLab 中，建立具有 **Reporter** 角色與 `read_api` 範圍的專案或群組存取權杖。群組權杖涵蓋群組中所有在 Tuist runners 上執行的專案。
2. 在 **Settings → Integrations** 中，將其貼到 GitLab CI 卡片上的 **API access token**，並選擇 **Save changes**。

Tuist 接著會讀取每個合併請求管線的合併請求。從專案本身的分支開啟的合併請求管線，會將其變更儲存在合併請求的來源分支下，因此 runner 設定檔的 <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link> 會套用到該分支。來自分叉的合併請求永遠不會儲存。若 Tuist 無法讀取合併請求，工作仍會執行並使用快取，但其變更會被捨棄。
