---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "了解如何將 Tuist 與 GitHub 整合，以優化工作流程。"
}
---
# GitHub 整合 {#github}

Git 儲存庫係絕大多數軟件項目嘅核心。我哋同 GitHub 整合，令你喺 pull request 入面直接睇到 Tuist 洞察報告，亦都慳返啲設定功夫，例如同步你嘅預設分支。

## 設定 {#setup}

你需要喺組織嘅 `Integrations` 分頁安裝 Tuist GitHub app：![顯示整合分頁嘅圖片](/images/guides/integrations/gitforge/github/integrations.png)

你亦都可以直接從 GitHub 安裝 app。如有需要，請登入 Tuist，授權 GitHub App 以便 Tuist 驗證你對安裝嘅存取權，然後選擇要連接嘅 Tuist 組織。你必須擁有安裝該 app 嘅 GitHub 組織（或個人 GitHub 帳戶）。系統只會顯示由你管理嘅 Tuist 組織同你嘅個人 Tuist 帳戶。如果只有一個帳戶可用，Tuist 會自動連接而唔會顯示選擇器。當你從 Tuist 開始操作時，組織已經選好，呢個步驟會被跳過。

之後，你可以喺你嘅 GitHub 儲存庫同 Tuist 項目之間新增項目連接：

![顯示新增項目連接嘅圖片](/images/guides/integrations/gitforge/github/add-project-connection.png)

安裝 app 之後，你亦可以唔經 dashboard 就連結項目：

- **CLI：** `tuist project repository connect owner/name`，以及用 `tuist project repository disconnect` 移除連結。
- **REST API：** 對 `/api/projects/{account_handle}/{project_handle}/vcs-connection` 執行 `PUT` 同 `DELETE`。
- **Model Context Protocol：** `connect_project_repository` 同 `disconnect_project_repository` 工具。

儲存庫必須係 GitHub App 安裝可以存取嘅其中一個，而且項目會採用儲存庫嘅預設分支。帳戶 token 需要 `project:admin:write` 範圍。

> [!TIP]
> **IP 允許清單**
>
> 如果你嘅 GitHub 組織使用 [IP 允許清單](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)，或者你嘅 GitHub 實例位於防火牆後面，請務必將 Tuist 嘅 <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 位址</.localized_link> 加入允許清單，以便整合可以同你嘅儲存庫通訊。

### GitHub Enterprise Server {#github-enterprise-server}

Tuist 亦都整合自託管嘅 GitHub Enterprise Server (GHES) 實例。喺 GitHub 整合卡片中，切換到 **Enterprise server** 分頁，輸入你嘅 GHES 基礎 URL（例如 `https://github.example.com`），然後點擊安裝。

由於 GitHub Apps 限定於單一 GitHub 實例，Tuist 無法將佢喺 github.com 嘅 App 重用喺你嘅 GHES 上——相反，安裝按鈕會帶你經過 GitHub 嘅 [App manifest 流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)：GHES 會引導你嘅管理員喺實例上註冊全新嘅 Tuist App，然後將新 App 嘅憑證交回 Tuist。Tuist 會按安裝加密儲存呢啲憑證，並用佢哋進行之後每一次 API 呼叫、webhook 簽名，以及連結到你嘅儲存庫。

無需額外設定 Tuist 伺服器；manifest 流程會自動生成並配置所有內容。

#### App 權限同 webhook 事件 {#github-app-permissions}

Tuist 需要以下 **儲存庫權限** 用於 PR 評論同 bundle 大小檢查：

| 權限 | 存取 | 用途 |
|---|---|---|
| Metadata (`metadata`) | 唯讀 | 基本儲存庫元數據；GitHub 要求每個 App 都必須有 |
| Pull requests (`pull_requests`) | 讀寫 | 讀取 pull request，包括其 head commit SHA，以及列出、發佈同更新 PR 評論 |
| Checks (`checks`) | 讀寫 | 建立同更新 check run，包括 bundle 大小通過／失敗檢查 |

Tuist 使用 `check_run` webhook 事件來處理 bundle 大小檢查動作。Manifest 流程會自動配置此訂閱。

如需喺 github.com 上手動設定 App 並搭配自託管 Tuist 伺服器，請參閱 <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">自託管指南</.localized_link>。

#### 分離瀏覽器同 API URL {#separate-browser-and-api-urls}

如果工程師透過內部主機名存取 GitHub Enterprise，而第三方服務使用外部代理，請喺點擊安裝之前配置兩個位址：

| 欄位 | 例子 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | 你嘅瀏覽器，用於 App 註冊同安裝，以及從 Tuist 連結到 GitHub |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist 嘅伺服器，用於 manifest-code 交換、存取權杖、儲存庫存取、PR 評論同檢查 |

API URL 係完整嘅 REST API 基礎 URL，包括 `/api/v3` 或你嘅代理公開嘅等效路徑。Tuist 唔會將 `/api/v3` 附加到明確指定嘅 API URL。如果一個主機名同時適用於你嘅瀏覽器同 Tuist，請留空；現有連線會繼續使用 `<Server URL>/api/v3`。

兩個位址都必須路由到 **同一個 GitHub Enterprise 實例**。你嘅瀏覽器只需要能夠到達 Server URL，唔需要到達 API 代理。Tuist 嘅伺服器只需要能夠到達 API URL，唔需要到達內部瀏覽器主機名。

對於外部代理：

- 使用 HTTPS，並採用 Tuist 伺服器信任嘅證書，且公共 DNS 解析為公共 IP 位址。API URL 覆蓋唔會繞過 Tuist 嘅私有 IP/SSRF 保護。覆蓋必須指向你嘅 Enterprise 實例，而唔係 `github.com` 或 `*.github.com` 端點。
- 將每個 Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 位址</.localized_link> 加入白名單。
- 轉發 Tuist 使用嘅 REST API 端點，包括 `POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens`，以及用於評論同檢查嘅儲存庫 API 端點。呢啲係 GitHub 嘅上游路徑；如果你嘅代理公開咗不同嘅前綴，請相應翻譯。
- 將請求轉發到 GitHub，唔帶 HTTP 重定向或互動式登入頁面。Tuist 唔會自動跟隨 Enterprise API 重定向，所以佢哋無法繞過公共 IP 檢查。Manifest 轉換端點喺設定期間、Tuist 取得 App 憑證之前必須可達。GitHub Actions 日誌下載係例外：Tuist 只透過 HTTPS 跟隨已簽名嘅存檔重定向，檢查並將每個目的地固定到公共 IP，且唔會轉發安裝權杖。

GitHub 可能會使用其內部主機名返回分頁連結。Tuist 會將來自已配置 GitHub 實例嘅連結重新基於 API URL，保留你代理嘅路徑前綴；指向無關來源嘅連結會被拒絕。

另外，GitHub 必須能夠將 webhooks 傳遞到 `https://tuist.dev/webhooks/github`（或你自託管 Tuist 伺服器上嘅 `/webhooks/github`）。工程師必須能夠返回 Tuist 以完成瀏覽器回調。API URL 唔會改變任何一個目的地。

組織管理員亦可以透過整合卡片中嘅 **Save API URL** 來更改或清除現有 Enterprise 整合嘅 API URL。無需重新安裝 App 或重新連接項目。清除後會恢復為 `<Server URL>/api/v3`。儲存時會驗證 URL 格式，而唔係代理連通性。由於安裝查找係緩存嘅，Webhook 處理可能需要長達一分鐘才能使用更改後嘅位址；已經進行中嘅請求可能仍然使用之前嘅位址。

> [!NOTE]
> **僅限託管 Tuist 伺服器上嘅 Enterprise 方案**
>
> 喺託管 Tuist 伺服器（`https://tuist.dev`）上，GitHub Enterprise Server 整合僅限於使用 **Enterprise** 方案嘅組織。自託管 Tuist 部署可以在任何方案上使用。

## Pull/merge request 評論 {#pull-merge-request-comments}

GitHub app 會發佈 Tuist 運行報告，其中包括 PR 摘要，包括指向最新 <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">預覽</.localized_link> 或 <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">測試</.localized_link> 嘅連結：

Tuist 會隨著結果到來更新一條評論。Gradle 構建會為每個根項目同請求嘅任務集單獨顯示；重新運行相同任務會替換該次調用嘅先前結果。完整嘅構建歷史記錄仍然喺 Tuist 上可用。

評論預設啟用，以保留現有整合嘅報告。要為項目關閉或重新開啟，請打開 **Project Settings → Integrations** 並切換 **GitHub → Run report comments**。每個項目都有自己嘅設定；儲存庫連線仍然喺組織設定中管理。

禁用評論唔會禁用構建或測試上傳、GitHub Actions 工作摘要、儲存庫連線或其他 GitHub 整合功能。現有評論唔會被刪除。

![顯示 pull request 評論嘅圖片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **要求**
>
> 只有當你嘅 CI 運行係 <.localized_link href="/guides/server/authentication#continuous-integration">已認證</.localized_link> 時，才會發佈評論。

> [!NOTE]
> **`GITHUB_REF`**
>
> 如果你有一個自定義工作流程，唔係由 PR commit 觸發，而係例如由 GitHub 評論觸發，你可能需要確保 `GITHUB_REF` 變量設置為 `refs/pull/<PR_NUMBER>/merge` 或 `refs/pull/<PR_NUMBER>/head`。
>
> 你可以運行相關命令，例如 `tuist share`，並帶有前綴 `GITHUB_REF` 環境變量：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions 工作摘要 {#github-actions-job-summary}

Tuist CLI 同 Gradle 插件會將測試同構建結果寫入 GitHub Actions 中嘅 [工作摘要](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)。摘要連結到 Tuist 上嘅完整報告，那裡提供更豐富嘅見解，例如不穩定測試同 bundle 大小差異。

對於 Gradle，每個成功上傳嘅構建或測試報告都會附加自己嘅摘要，保留由 `gradle/actions/setup-gradle` 等工具編寫嘅其他內容。這需要包含工作摘要支持嘅插件版本；較舊嘅 Gradle 插件版本只通過 GitHub App 嘅 PR 評論進行報告。工作摘要無需連接 GitHub App，禁用 **Run report comments** 亦唔會影響佢哋。

當 GitHub Actions 摘要目標可用時，Gradle 會等待上傳同摘要完成後才退出，即使啟用咗 `uploadInBackground`。GitHub 會喺工作流程步驟結束時捕獲摘要。

![顯示 GitHub Actions 工作摘要中 Tuist 運行報告嘅圖片](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

這喺使用 [合併隊列](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) 時特別有用。合併隊列運行唔會附加到 pull request，所以唔會發佈評論，但工作摘要仍然會顯示結果。

> [!NOTE]
> **要求**
>
> 工作摘要需要成功上傳報告。喺託管 Tuist 伺服器上，你嘅 CI 運行必須係 <.localized_link href="/guides/server/authentication#continuous-integration">已認證</.localized_link>。自託管實例喺啟用網絡可信報告發佈時，亦可以接受無憑證報告。
