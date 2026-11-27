---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "透過流水線標籤選擇機器，在 Tuist Runners 上執行 GitLab CI 工作。"
}
---
# GitLab CI {#gitlab-ci}

你嘅 pipeline 會留喺 GitLab。Tuist 為每個 job 提供一部隔離嘅 Linux 或 macOS 機器，並將日誌同結果回報俾 GitLab 同 Tuist 儀表板。需要使用 GitLab 19.3 或更新版本。支援 GitLab.com 同可以透過公開 HTTPS 連接嘅自託管實例。

1. **建立 GitLab runner。** 喺你項目嘅**Settings → CI/CD → Runners**入面，建立一個項目 runner。你亦都可以使用群組 runner。將你想用嘅所有 Tuist profile 標籤加入為 runner tags，例如`tuist-linux`同`tuist-macos`，並停用**Run untagged jobs**。保留 GitLab 顯示嘅驗證 token，佢以`glrt-`開頭。你唔需要喺自己部機安裝 runner。
2. **喺 Tuist 連接一次。** 喺**Settings → Integrations**，揀選 GitLab CI 卡片上嘅**Connect**。輸入你嘅 GitLab URL 同 runner 驗證 token。呢個連接可以服務使用唔同 profile 嘅 job。Token 會加密儲存，之後唔會再顯示。可選地，加入 API access token，令 merge request pipeline 可以儲存 cache volume；參閱[Merge request pipelines](#merge-request-pipelines)。
3. **喺每個 job 選擇機器。** 喺 job 嘅`tags`設定 exactly 一個<.localized_link href="/guides/features/runners/profiles">Tuist profile label</.localized_link>。只要已註冊嘅 GitLab runner 都有其他 tags，就允許使用：

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

4. **推送並監察。** Tuist 會喺一分鐘內開始輪詢。Job 會出現喺**Runners**底下，並附有返回 GitLab job、日誌同機器指標嘅連結。GitLab 會喺 job 運行期間接收日誌；Tuist 會喺完成時接收遮蔽後嘅日誌。

Tuist 會從每個分配讀取`CI_JOB_TAGS`，並喺已連接嘅 Tuist 帳戶內解析 profile。佢唔會從`CI_RUNNER_TAGS`推斷機器，亦都唔會使用預設 profile。如果缺少、未知或有多個 Tuist profile tags，已獲取嘅 job 會失敗，並喺其 GitLab 日誌中提供解釋。唔好喺你嘅 pipeline 變數中覆蓋`CI_JOB_TAGS`。

## 執行環境 {#execution-environment}

Job 喺隔離機器內使用 GitLab 嘅**shell executor**。Checkout、CI 變數、`before_script`、`script`、`after_script`、artifacts 同取消都由 GitLab Runner 處理。Pipeline 嘅`image:`同`services:`設定並唔會配置呢個 shell 環境；請使用安裝咗喺<.localized_link href="/guides/features/runners/profiles">runner image</.localized_link>上嘅工具，或者喺你嘅 script 中安裝佢哋。

可重用嘅 runner 驗證 token 會留喺 Tuist 伺服器。機器只會收到指派俾佢哋嘅 job 嘅憑證。目前 GitLab job 嘅 cache-signing 權限會被扣留。自訂 Linux cache volume 會透過 GitLab 嘅 API 驗證 job 身份同儲存權限；可覆蓋嘅 CI 變數並唔能建立信任。

一旦 Tuist 獲取 job，GitLab 就會將 job 標記為運行中，並開始計時。雖然 Tuist 已經獲取嘅 job 會用盡你帳戶嘅併發限制，但進一步嘅 job 會喺 GitLab 保持 pending 狀態。已獲取嘅 job 會等待機器，最多等到其 job timeout，最長 12 小時。如果到時仍然無機器可用，Tuist 會以`runner_system_failure`使分配失敗，而上述重試策略會讓 GitLab 重試。同樣嘅策略亦適用於丟失嘅 runner 機器。

## 輪換 token 同斷開連接 {#rotating-tokens-and-disconnecting}

更新連接嘅 token 並選擇**Save changes**以輪換佢哋。留空 token 會保留現有憑證。

**Disconnect**會停止獲取並使等待中嘅分配失敗。運行中嘅 job 會繼續使用佢哋自己嘅憑證。如果無法連接 GitLab，Tuist 會保留已停用嘅連接，同時重試取消等待中嘅分配。一旦嗰啲分配解決，連接就會被移除。

## Cache volume {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>喺 job 之間保留 Xcode、module 同 Gradle cache 以及其他目錄。喺 checkout 之後同使用佢哋嘅命令之前加入佢哋。

### Merge request pipeline {#merge-request-pipelines}

項目嘅 push、schedule 同 web pipeline 會將更改儲存到 cache volume。Merge request pipeline 會使用 cache，但只有當連接擁有 API access token 時先會儲存更改：

1. 喺 GitLab，建立一個具有**Reporter**角色同`read_api`範圍嘅項目或群組 access token。群組 token 涵蓋群組內所有喺 Tuist runner 上運行嘅項目。
2. 喺**Settings → Integrations**，將佢貼入 GitLab CI 卡片上嘅**API access token**，並選擇**Save changes**。

之後 Tuist 會讀取每個 merge request pipeline 嘅 merge request。從項目本身分支開啟嘅 merge request 嘅 pipeline 會將更改儲存喺 merge request 嘅來源分支底下，因此 runner profile 嘅<.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">branch settings</.localized_link>會應用於該分支。來自 fork 嘅 merge request 永遠唔會儲存。如果 Tuist 無法讀取 merge request，job 仍然會運行並使用 cache，但其更改會被丟棄。
