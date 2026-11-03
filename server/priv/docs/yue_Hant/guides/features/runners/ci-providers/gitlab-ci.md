---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 供應商 · Runner · 功能 · 指南 · Tuist",
  "description": "透過流水線標籤選擇機器，喺 Tuist Runners 上執行 GitLab CI 工作。"
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **只限邀請**
>
> Tuist Runners 目前只限邀請。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權。

你的 pipeline 會保留在 GitLab。Tuist 為每個 job 提供獨立的 Linux 或 macOS 機器，並將日誌和結果回報到 GitLab 和 Tuist 儀表板。需要使用 GitLab 19.3 或更新版本。支援 GitLab.com 以及可透過公開 HTTPS 存取的自託管實例。

1. **建立 GitLab runner。** 在專案的**Settings → CI/CD → Runners**中，建立專案 runner。你也可以使用群組 runner。將所有你想使用的 Tuist profile 標籤加入為 runner tags，例如`tuist-linux`和`tuist-macos`，並停用**Run untagged jobs**。保留 GitLab 顯示的驗證 token，它以`glrt-`開頭。你無需在自家機器上安裝 runner。
2. **在 Tuist 中連接一次。** 在**Settings → Integrations**中，於 GitLab CI 卡片上選擇**Connect**。輸入你的 GitLab URL 和 runner 驗證 token。此連接可以服務使用不同 profiles 的 jobs。Tokens 會加密儲存，且不會再次顯示。你可以選擇加入 API access token，讓 merge request pipelines 能夠儲存 cache volumes；請參閱[Merge request pipelines](#merge-request-pipelines)。
3. **為每個 job 選擇機器。** 在 job 的`tags`中設定恰好一個<.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。只要已註冊的 GitLab runner 也擁有其他 tags，則允許使用它們：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。Jobs 會出現在**Runners**下方，並附有連結回到 GitLab job、日誌和機器指標。GitLab 會在 job 執行期間接收日誌；Tuist 則在 job 完成時接收經過遮罩的日誌。

Tuist 會從每個分配中讀取`CI_JOB_TAGS`，並在已連接的 Tuist 帳戶內解析 profile。它不會從`CI_RUNNER_TAGS`推斷機器，也不會使用預設 profile。如果缺少、未知或多個 Tuist profile tags，獲取的 job 會失敗，並在 GitLab 日誌中提供說明。請勿在你的 pipeline 變數中覆蓋`CI_JOB_TAGS`。

## 執行環境 {#execution-environment}

Jobs 在獨立機器內使用 GitLab 的**shell executor**。Checkout、CI 變數、`before_script`、`script`、`after_script`、artifacts 和取消操作均由 GitLab Runner 處理。Pipeline 的`image:`和`services:`設定不會配置此 shell 環境；請使用安裝在<.localized_link href="/guides/features/runners/profiles">runner image</.localized_link>上的工具，或在你的 script 中安裝它們。

可重用的 runner 驗證 token 會保留在 Tuist 伺服器上。機器只會收到其分配 job 的憑證。Cache-signing grants 目前對 GitLab jobs 暫停授予。自訂 Linux cache volumes 會透過 GitLab 的 API 驗證 job 身分和儲存權限；可覆蓋的 CI 變數無法建立信任。

一旦 Tuist 獲取 job，GitLab 便會將其標記為執行中，並開始計時超時。當 Tuist 已獲取的 jobs 用盡你帳戶的併發限制時，後續 jobs 會在 GitLab 中保持待定狀態。已獲取的 job 會等待機器，最多達到其 job 超時時間（最長 12 小時）。如果屆時沒有機器可用，Tuist 會以`runner_system_failure`使分配失敗，而上述重試政策會讓 GitLab 重試它。相同的政策也適用於遺失的 runner 機器。

## 輪換 tokens 和斷開連接 {#rotating-tokens-and-disconnecting}

更新連接的 tokens 並選擇**Save changes**以輪換它們。將 token 留空會保留現有的憑證。

**Disconnect**會停止獲取並使待定的分配失敗。執行中的 jobs 會使用其自身的憑證繼續進行。如果無法連線到 GitLab，Tuist 會保留已停用的連接，同時重試取消待定的分配。一旦這些分配已解決，連接就會被移除。

## Cache volumes {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>在 jobs 之間保留 Xcode、module 和 Gradle caches 以及其他目錄。在 checkout 之後和使用它們的命令之前加入它們。

### Merge request pipelines {#merge-request-pipelines}

專案的 push、schedule 和 web pipelines 會將變更儲存到 cache volumes。Merge request pipelines 會使用 cache，但只有在連接具有 API access token 時才會儲存變更：

1. 在 GitLab 中，建立具有**Reporter**角色和`read_api`範圍的專案或群組 access token。群組 token 涵蓋群組中所有在 Tuist runners 上執行的專案。
2. 在**Settings → Integrations**中，將其貼到 GitLab CI 卡片上的**API access token**，並選擇**Save changes**。

然後 Tuist 會讀取每個 merge request pipeline 的 merge request。從專案本身分支開啟的 merge request pipelines 會將變更儲存在 merge request 的來源分支下，因此 runner profile 的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link>會套用到該分支。來自 fork 的 merge requests 永遠不會儲存。如果 Tuist 無法讀取 merge request，job 仍會執行並使用 cache，但其變更會被捨棄。
