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
> Tuist Runners 目前僅限邀請。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權限。

你的 pipeline 會保留在 GitLab。Tuist 為每個 job 提供隔離的 Linux 或 macOS 機器，並將其日誌和結果回報給 GitLab 和 Tuist dashboard。需要使用 GitLab 19.3 或更新版本。支援可透過公開 HTTPS 存取的 GitLab.com 和自管實例。

1. **建立 GitLab runner。** 在專案的 **Settings → CI/CD → Runners** 中，建立專案 runner。你也可以使用群組 runner。將所有你想使用的 Tuist profile 標籤加入為 runner tags，例如 `tuist-linux` 和 `tuist-macos`，並停用 **Run untagged jobs**。保留 GitLab 顯示的驗證 token，它以 `glrt-` 開頭。你不需要在自己的機器上安裝 runner。
2. **在 Tuist 中連接一次。** 在 **Settings → Integrations** 中，於 GitLab CI 卡片上選擇 **Connect**。輸入你的 GitLab URL 和 runner 驗證 token。此連接可以服務使用不同 profile 的 job。Token 會以加密方式儲存，且不會再次顯示。你可以選擇性地加入 API access token，以便 merge request pipelines 能夠儲存 cache volumes；請參閱 [Merge request pipelines](#merge-request-pipelines)。
3. **在每個 job 中選擇機器。** 在 job 的 `tags` 中設定恰好一個 <.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。只要已註冊的 GitLab runner 也擁有其他 tags，則允許使用它們：

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

4. **推送並觀察。** Tuist 會在一分鐘內開始輪詢。Jobs 會出現在 **Runners** 下方，並附有返回 GitLab job 的連結、日誌和機器指標。GitLab 會在 job 執行期間接收日誌；Tuist 則會在 job 完成時接收遮蔽後的日誌。

Tuist 從每個分配中讀取`CI_JOB_TAGS`，並在連接的 Tuist 帳戶中解析 profile。它不會從`CI_RUNNER_TAGS`推斷機器或使用預設 profile。缺少、未知或多個 Tuist profile tags 會導致獲取的 job 失敗，並在其 GitLab 日誌中提供解釋。不要在你的 pipeline 變數中覆蓋`CI_JOB_TAGS`。

## 執行環境 {#execution-environment}

Jobs 在隔離機器內使用 GitLab 的**shell executor**。Checkout、CI 變數、`before_script`、`script`、`after_script`、artifacts 和取消均由 GitLab Runner 處理。Pipeline 的`image:`和`services:`設定不會配置此 shell 環境；請使用安裝在<.localized_link href="/guides/features/runners/profiles">runner image</.localized_link>上的工具，或在你的腳本中安裝它們。

可重用的 runner 驗證 token 會保留在 Tuist 伺服器上。機器僅接收其分配 job 的憑證。Cache-signing grants 目前對 GitLab jobs  withheld。自訂 Linux cache volumes 會透過 GitLab 的 API 驗證 job 身份和儲存權限；可覆蓋的 CI 變數不會建立信任。

一旦 Tuist 獲取 job，GitLab 就會將其標記為運行中，並開始其超時。當 Tuist 已獲取的 jobs 用完你帳戶的併發限制時，進一步的 jobs 會在 GitLab 中保持待處理狀態。獲取的 job 會等待機器，最多達到其 job 超時時間，最長為 12 小時。如果到那時沒有機器可用，Tuist 會使分配失敗並顯示`runner_system_failure`，上述重試策略會讓 GitLab 重試它。相同的策略也涵蓋遺失的 runner 機器。

## 輪換 tokens 和斷開連接 {#rotating-tokens-and-disconnecting}

更新連接的 tokens 並選擇**Save changes**以輪換它們。將 token 留空會保留現有憑證。

**Disconnect**會停止獲取並使等待中的分配失敗。運行中的 jobs 會繼續使用其自身的憑證。如果無法存取 GitLab，Tuist 會保留已停用的連接，同時重試取消等待中的分配。一旦這些分配穩定下來，連接就會被移除。

## Cache volumes {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>在 jobs 之間保留 Xcode、module 和 Gradle caches 以及其他目錄。在 checkout 之後和使用它們的命令之前添加它們。

### Merge request pipelines {#merge-request-pipelines}

專案的 push、schedule 和 web pipelines 會將其變更儲存到 cache volumes。Merge request pipelines 會使用 cache，並且僅當連接具有 API access token 時才會儲存其變更：

1. 在 GitLab 中，建立具有**Reporter**角色和`read_api`範圍的專案或群組 access token。群組 token 涵蓋在 Tuist runners 上運行的群組中的每個專案。
2. 在**Settings → Integrations**中，將其貼上到 GitLab CI 卡片上的**API access token**，然後選擇**Save changes**。

Tuist 隨後會讀取每個 merge request pipeline 的 merge request。從專案本身的分支開啟的 merge request 的 pipelines 會將其變更儲存在 merge request 的來源分支下，因此 runner profile 的<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link>會應用於該分支。來自 fork 的 merge request 永遠不會儲存。如果 Tuist 無法讀取 merge request，job 仍會運行並使用 cache，但其變更會被丟棄。
