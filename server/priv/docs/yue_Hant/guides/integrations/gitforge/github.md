---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git 託管平台 | 整合 | 指南 | Tuist",
  "description": "了解如何將 Tuist 與 GitHub 整合，以優化工作流程。"
}
---
# GitHub 整合 {#github}

Git 儲存庫係絕大多數軟件項目嘅核心。我哋同 GitHub 整合，令你喺 pull request 入面直接睇到 Tuist 嘅洞察報告，亦都慳返啲設定功夫，例如同步預設分支。

## 設定 {#setup}

你需要喺組織嘅 `Integrations` 分頁安裝 Tuist GitHub 應用程式：![顯示整合分頁嘅圖片](/images/guides/integrations/gitforge/github/integrations.png)

你亦都可以直接從 GitHub 安裝應用程式。如有需要，請登入 Tuist，授權 GitHub App 讓 Tuist 驗證你對該安裝嘅存取權，然後選擇要連接嘅 Tuist 組織。你必須擁有安裝該應用程式嘅 GitHub 組織（或個人 GitHub 帳戶）。系統只會顯示由你管理嘅 Tuist 組織同你嘅個人 Tuist 帳戶。只有當應用程式安裝喺你嘅個人 GitHub 帳戶，而且你嘅個人 Tuist 帳戶係唯一選項時，Tuist 先會跳過選擇器。對於 GitHub 組織，即使你嘅個人帳戶係唯一選項，Tuist 仍然會詢問。如果冇列出你團隊嘅 Tuist 組織，請選擇 **建立組織**，或者請該組織嘅其中一位管理員將你設為管理員。只要喺返回 Tuist 後十分鐘內作出選擇，列表就會喺頁面開啟期間更新，組織會出現而無需重新開始。當你從 Tuist 開始時，組織已經被選中，呢個步驟會被跳過。

之後，你可以喺你嘅 GitHub 儲存庫同 Tuist 項目之間添加項目連接：

![顯示添加項目連接嘅圖片](/images/guides/integrations/gitforge/github/add-project-connection.png)

安裝應用程式後，你亦都可以唔使用儀表板來連結項目：

- **CLI：** `tuist project repository connect owner/name`，以及使用 `tuist project repository disconnect` 來移除連結。
- **REST API：** 對 `/api/projects/{account_handle}/{project_handle}/vcs-connection` 執行 `PUT` 同 `DELETE`。
- **Model Context Protocol：** `connect_project_repository` 同 `disconnect_project_repository` 工具。

儲存庫必須係 GitHub App 安裝可以存取嘅其中一个，而且項目會採用儲存庫嘅預設分支。帳戶令牌需要 `project:admin:write` 範圍。

> [!TIP]
> **IP 允許清單**
>
> 如果你嘅 GitHub 組織使用 [IP 允許清單](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)，或者你嘅 GitHub 實例位於防火牆後面，請務必將 Tuist 嘅 <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 地址</.localized_link> 加入允許清單，以便整合可以同你嘅儲存庫通訊。

### GitHub Enterprise Server {#github-enterprise-server}

Tuist 亦都整合咗自託管嘅 GitHub Enterprise Server (GHES) 實例。喺 GitHub 整合卡片中，切換到 **Enterprise server** 分頁，輸入你嘅 GHES 基礎 URL（例如 `https://github.example.com`），然後點擊安裝。

由於 GitHub Apps 限定於單一 GitHub 實例，Tuist 無法喺你嘅 GHES 上重用其 github.com App — 相反，安裝按鈕會引導你完成 GitHub 嘅 [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)：GHES 會指導你嘅管理員喺實例上註冊一個全新嘅 Tuist App，然後將新 App 嘅憑證交回給 Tuist。Tuist 會按安裝加密儲存呢啲憑證，並從此以後用於每次 API 調用、webhook 簽名以及指向你儲存庫嘅連結。

不需要額外嘅 Tuist 伺服器設定；manifest flow 會自動生成並配置所有內容。

#### App 權限同 webhook 事件 {#github-app-permissions}

Tuist 需要以下 **儲存庫權限** 來進行 PR 評論同 bundle 大小檢查：

| 權限 | 存取 | 用途 |
|---|---|---|
| Metadata (`metadata`) | 只讀 | 基本儲存庫元數據；GitHub 要求每個 App 都必須具備 |
| Pull requests (`pull_requests`) | 讀寫 | 讀取 pull requests，包括其 head commit SHA，以及列出、發布同更新 PR 評論 |
| Checks (`checks`) | 讀寫 | 創建同更新 check runs，包括 bundle 大小通過/失敗檢查 |

Tuist 使用 `check_run` webhook 事件來處理 bundle 大小檢查操作。manifest flow 會自動配置此訂閱。

對於喺 github.com 上使用自託管 Tuist 伺服器嘅手動 App 設定，請參閱 <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">自託管指南</.localized_link>。

#### 分開瀏覽器同 API URL {#separate-browser-and-api-urls}

如果工程師通過內部主機名訪問 GitHub Enterprise，而第三方服務使用外部代理，請喺點擊安裝之前配置兩個地址：

| 欄位 | 示例 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | 你嘅瀏覽器，用於 App 註冊同安裝，以及從 Tuist 到 GitHub 嘅連結 |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist 嘅伺服器，用於 manifest-code 交換、存取令牌、儲存庫訪問、PR 評論同檢查 |

API URL 係完整嘅 REST API 基礎 URL，包括 `/api/v3` 或你嘅代理公開嘅等效路徑。Tuist 不會將 `/api/v3` 附加到明確指定嘅 API URL。如果一個主機名同時適用於你嘅瀏覽器同 Tuist，請留空；現有連接會繼續使用 `<Server URL>/api/v3`。

兩個地址都必須路由到 **同一個 GitHub Enterprise 實例**。你嘅瀏覽器只需要能夠到達 Server URL，不需要到達 API 代理。Tuist 嘅伺服器只需要能夠到達 API URL，不需要到達內部瀏覽器主機名。

對於外部代理：

- 使用 HTTPS 並配備 Tuist 伺服器信任嘅證書，且公共 DNS 解析為公共 IP 地址。API URL 覆蓋不會繞過 Tuist 嘅私有 IP/SSRF 保護。覆蓋必須指向你嘅 Enterprise 實例，而不是 `github.com` 或 `*.github.com` 端點。
- 將每個 Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 地址</.localized_link> 加入白名單。
- 轉發 Tuist 使用嘅 REST API 端點，包括 `POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens` 以及用於評論同檢查嘅儲存庫 API 端點。呢啲係 GitHub 嘅上游路徑；如果你嘅代理公開咗不同嘅前綴，請相應翻譯。
- 將請求轉發到 GitHub，不要包含 HTTP 重定向或互動式登錄頁面。Tuist 不會自動跟隨 Enterprise API 重定向，因此它們無法繞過公共 IP 檢查。manifest 轉換端點必須在設置期間可達，即在 Tuist 獲得 App 憑證之前。GitHub Actions 日誌下載係例外：Tuist 僅通過 HTTPS 跟隨簽名存檔重定向，檢查並將每個目的地固定到公共 IP，並且不轉發安裝令牌。

GitHub 可能會使用其內部主機名返回分頁連結。Tuist 會將來自配置嘅 GitHub 實例嘅連結重新基於 API URL，保留你代理嘅路徑前綴；指向無關來源嘅連結會被拒絕。

另外，GitHub 必須能夠將 webhooks 傳遞到 `https://tuist.dev/webhooks/github`（或者在你自託管嘅 Tuist 伺服器上嘅 `/webhooks/github`）。工程師必須能夠返回 Tuist 以完成瀏覽器回調。API URL 不會改變任一目的地。

組織管理員還可以通過整合卡片中嘅 **Save API URL** 來更改或清除現有 Enterprise 整合嘅 API URL。無需重新安裝 App 或重新連接項目。清除它會恢復 `<Server URL>/api/v3`。保存操作驗證 URL 格式，而非代理連通性。由於安裝查找係緩存嘅，Webhook 處理可能需要長達一分鐘才能使用更改後嘅地址；已經在傳輸中嘅請求可能仍會使用之前嘅地址。

> [!NOTE]
> **僅限託管 Tuist 伺服器上嘅 Enterprise 計劃**
>
> 喺託管嘅 Tuist 伺服器 (`https://tuist.dev`) 上，GitHub Enterprise Server 整合僅提供給使用 **Enterprise** 計劃嘅組織。自託管嘅 Tuist 部署可以在任何計劃上使用它。

## Pull/merge request 評論 {#pull-merge-request-comments}

GitHub app 會發布 Tuist 運行報告，其中包括 PR 摘要，以及指向最新 <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link> 或 <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">tests</.localized_link> 嘅連結：

Tuist 會在結果到達時更新一條評論。Gradle 構建會為每個根項目同請求嘅任務集單獨顯示；重新運行相同嘅任務會替換該次調用嘅先前結果。完整嘅構建歷史記錄仍然可在 Tuist 上查看。

評論默認啟用，以保留現有整合嘅報告。要為項目關閉或重新開啟評論，請打開 **Project Settings → Integrations** 並切換 **GitHub → Run report comments**。每個項目都有自己嘅設置；儲存庫連接仍然在組織設置中管理。

禁用評論不會禁用構建或測試上傳、GitHub Actions 作業摘要、儲存庫連接或其他 GitHub 整合功能。現有評論不會被刪除。

![顯示 pull request 評論嘅圖片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **要求**
>
> 僅當你的 CI 運行已 <.localized_link href="/guides/server/authentication#continuous-integration">認證</.localized_link> 時，才會發布評論。

> [!NOTE]
> **`GITHUB_REF`**
>
> 如果你有一個不是由 PR commit 觸發，而是例如由 GitHub 評論觸發嘅自定義工作流，你可能需要確保 `GITHUB_REF` 變量設置為 `refs/pull/<PR_NUMBER>/merge` 或 `refs/pull/<PR_NUMBER>/head`。
>
> 你可以運行相關命令，例如 `tuist share`，並帶有前綴嘅 `GITHUB_REF` 環境變量：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions 作業摘要 {#github-actions-job-summary}

Tuist CLI 同 Gradle 插件將測試同構建結果寫入 GitHub Actions 中嘅 [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)。摘要連結到 Tuist 上嘅完整報告，那裡提供更豐富嘅見解，例如不穩定測試同 bundle 大小差異。

對於 Gradle，每個成功上傳嘅構建或測試報告都會附加其自己嘅摘要，保留由 `gradle/actions/setup-gradle` 等工具寫入嘅其他內容。這需要一個包含作業摘要支持嘅插件版本；較舊嘅 Gradle 插件版本僅通過 GitHub App 嘅 PR 評論進行報告。作業摘要不需要連接 GitHub App，禁用 **Run report comments** 也不會影響它們。

當 GitHub Actions 摘要目標可用時，即使啟用了 `uploadInBackground`，Gradle 也會在退出前等待上傳同摘要完成。GitHub 會在工作流步驟結束時捕獲摘要。

![顯示 GitHub Actions 作業摘要中 Tuist 運行報告嘅圖片](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

這在使用 [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) 時特別有用。merge queue 運行不附屬於 pull request，因此不會發布評論，但作業摘要仍然會顯示結果。

> [!NOTE]
> **要求**
>
> 作業摘要需要成功上傳報告。喺託管嘅 Tuist 伺服器上，你的 CI 運行必須 <.localized_link href="/guides/server/authentication#continuous-integration">認證</.localized_link>。自託管實例在啟用網絡可信報告發布時，也可以接受無憑證報告。
