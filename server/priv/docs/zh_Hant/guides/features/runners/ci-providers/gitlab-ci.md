---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run GitLab CI jobs on Tuist Runners with machine selection through pipeline tags."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以請求存取您的帳戶。

您的管線仍保留在 GitLab 中。Tuist 為每個工作提供隔離的 Linux 或 macOS 機器，並將其日誌和結果回報給 GitLab 和 Tuist 儀表板。需要使用 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 和自託管實例。

1. **建立 GitLab Runner。** 在專案的 **Settings → CI/CD → Runners** 中，建立一個專案層級的 Runner。你也可以使用群組層級的 Runner。將所有你想要使用的 Tuist 設定檔標籤加入為 Runner 標籤，例如 `tuist-linux` 和 `tuist-macos`，並停用 **Run untagged jobs**。請保留 GitLab 顯示的驗證權杖，該權杖以 `glrt-` 開頭。你不需要在自己的機器上安裝 Runner。
2. **在 Tuist 中進行一次連線。** 在 **Settings → Integrations** 中，於 GitLab CI 卡片上選擇 **Connect**。輸入你的 GitLab URL 與 Runner 驗證權杖。此連線可服務使用不同設定檔的工作。權杖會以加密方式儲存，且不會再次顯示。你可以選擇性加入 API 存取權杖，讓合併請求管線能夠儲存快取磁碟區；請參閱 [Merge request pipelines](#merge-request-pipelines)。
3. **為每個工作選擇機器。** 在工作的 `tags` 中設定恰好一個 <.localized_link href="/guides/features/runners/profiles">Tuist 設定檔標籤</.localized_link>。只要已註冊的 GitLab Runner 也擁有其他標籤，則允許使用這些標籤：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。工作會出現在 **Runners** 下方，並提供連結回到 GitLab 工作、日誌與機器指標。GitLab 會在工作執行期間接收日誌；Tuist 則會在工作完成時接收遮罩後的日誌。

Tuist 會從每個指派中讀取`CI_JOB_TAGS`，並在連接的 Tuist 帳戶中解析設定檔。它不會從`CI_RUNNER_TAGS`推斷機器或使用預設設定檔。缺少、未知或多個 Tuist 設定檔標籤會導致已獲取的工作失敗，並在其 GitLab 日誌中提供說明。請勿在您的管線變數中覆寫`CI_JOB_TAGS`。

## 執行環境 {#execution-environment}

工作在隔離的機器內使用 GitLab 的**shell 執行器**。簽出、CI 變數、`before_script`、`script`、`after_script`、產物和取消均由 GitLab Runner 處理。管線的`image:`和`services:`設定不會設定此 shell 環境；請使用安裝在<.localized_link href="/guides/features/runners/profiles">runner 映像</.localized_link>上的工具，或在您的腳本中安裝它們。

可重複使用的 runner 驗證權杖會保留在 Tuist 伺服器上。機器僅接收其指派工作的憑證。目前 GitLab 工作會暫緩快取簽署授權。自訂 Linux 快取卷冊會透過 GitLab 的 API 驗證工作身分和儲存權限；可覆寫的 CI 變數無法建立信任。

一旦 Tuist 獲取工作，GitLab 就會將工作標記為執行中，並開始其逾時。當 Tuist 已獲取的工作用完您帳戶的併發限制時，進一步的工作會在 GitLab 中保持擱置狀態。已獲取的工作會等待機器，最多達到其工作逾時時間，最長為 12 小時。如果到那時沒有機器可用，Tuist 會使指派失敗並顯示`runner_system_failure`，上述重試政策會讓 GitLab 重試它。相同的政策也涵蓋遺失的 runner 機器。

## 輪換權杖和斷開連接 {#rotating-tokens-and-disconnecting}

更新連接的權杖並選擇**儲存變更**以輪換它們。將權杖留空會保留現有的憑證。

**斷開連接**會停止獲取並使等待中的指派失敗。執行中的工作會繼續使用其自身的憑證。如果無法連線到 GitLab，Tuist 會保留已停用的連接，同時重試取消等待中的指派。一旦這些指派穩定下來，連接就會被移除。

## 快取卷冊 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在簽出之後以及在使用它們的命令之前新增它們。

### 合併請求管線 {#merge-request-pipelines}

專案的推送、排程和網頁管線會將其變更儲存到快取卷冊。合併請求管線會使用快取，並且僅在連接具有 API 存取權杖時才會儲存其變更：

1. 在 GitLab 中，建立具有**Reporter**角色和`read_api`範圍的專案或群組存取權杖。群組權杖涵蓋在 Tuist runners 上執行的群組中的每個專案。
2. 在**設定 → 整合**中，將其貼到 GitLab CI 卡片上的**API 存取權杖**中，並選擇**儲存變更**。

Tuist 隨後會讀取每個合併請求管線的合併請求。從專案本身的分支開啟的合併請求管線會將其變更儲存在合併請求的來源分支下，因此 runner 設定檔的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">分支設定</.localized_link>會套用至該分支。來自分叉的合併請求永遠不會儲存。如果 Tuist 無法讀取合併請求，工作仍會執行並使用快取，但其變更會被捨棄。
