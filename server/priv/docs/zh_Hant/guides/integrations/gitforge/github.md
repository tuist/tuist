---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git 託管平台 | 整合 | 指南 | Tuist",
  "description": "了解如何將 Tuist 與 GitHub 整合，以強化工作流程。"
}
---
# GitHub 整合 {#github}

Git 儲存庫是絕大多數軟體專案的核心。我們與 GitHub 整合，讓 Tuist 洞察直接出現在你的拉取請求中，並省去部分設定步驟，例如同步預設分支。

## 設定 {#setup}

你需要在組織的 `Integrations` 分頁中安裝 Tuist GitHub App：![顯示整合分頁的圖片](/images/guides/integrations/gitforge/github/integrations.png)

你也可以直接從 GitHub 安裝該 App。如有需要，請登入 Tuist，授權 GitHub App 以便 Tuist 驗證你對安裝的存取權，然後選擇要連接的 Tuist 組織。你必須擁有安裝該 App 的 GitHub 組織（或個人 GitHub 帳戶）。系統僅提供你管理的 Tuist 組織與你的個人 Tuist 帳戶。只有當 App 安裝在你的個人 GitHub 帳戶且你的個人 Tuist 帳戶是唯一選項時，Tuist 才會略過選擇器。對於 GitHub 組織，即使你的個人帳戶是唯一選項，Tuist 仍會要求選擇。如果團隊的 Tuist 組織未列出，請選擇 **建立組織**，或請其中一位管理員將你設為管理員。清單會在頁面開啟期間更新，因此只要在返回 Tuist 後的十分鐘內選擇，組織就會出現而無需重新開始。當你從 Tuist 啟動時，組織已預先選取，此步驟會被略過。

接著，你可以在 GitHub 儲存庫與 Tuist 專案之間新增專案連接：

![顯示新增專案連接的圖片](/images/guides/integrations/gitforge/github/add-project-connection.png)

安裝 App 後，你也可以在不使用儀表板的情況下連結專案：

- **CLI：**`tuist project repository connect owner/name`，以及使用 `tuist project repository disconnect` 移除連結。
- **REST API：** 對 `/api/projects/{account_handle}/{project_handle}/vcs-connection` 執行 `PUT` 與 `DELETE`。
- **Model Context Protocol：** 使用 `connect_project_repository` 與 `disconnect_project_repository` 工具。

該儲存庫必須是 GitHub App 安裝可存取的儲存庫，且專案會採用儲存庫的預設分支。帳戶權杖需要 `project:admin:write` 範圍。

> [!TIP]
> **IP 允許清單**
>
> 如果你的 GitHub 組織使用 [IP 允許清單](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)，或你的 GitHub 執行個體位於防火牆後面，請務必將 Tuist 的 <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 位址</.localized_link> 加入允許清單，以便整合功能能與你的儲存庫通訊。

### GitHub Enterprise Server {#github-enterprise-server}

Tuist 也與自行託管的 GitHub Enterprise Server (GHES) 執行個體整合。在 GitHub 整合卡片中，切換至 **Enterprise server** 分頁，輸入你的 GHES 基礎 URL（例如 `https://github.example.com`），然後點擊安裝。

由於 GitHub Apps 的作用範圍限於單一 GitHub 執行個體，Tuist 無法在 GHES 上重複使用其 github.com App；相反地，安裝按鈕會引導你完成 GitHub 的 [App manifest 流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)：GHES 會協助管理員在執行個體上註冊全新的 Tuist App，然後將新 App 的憑證交還給 Tuist。Tuist 會以每安裝為單位加密儲存這些憑證，並在之後的每次 API 呼叫、webhook 簽章以及指向你儲存庫的連結中使用它們。

不需要額外的 Tuist 伺服器設定；manifest 流程會自動產生並佈建所有內容。

#### App 權限與 webhook 事件 {#github-app-permissions}

Tuist 需要以下 **儲存庫權限** 才能發布 PR 留言與執行套件大小檢查：

| 權限 | 存取 | 用途 |
|---|---|---|
| Metadata (`metadata`) | 唯讀 | 基本儲存庫中繼資料；GitHub 要求每個 App 都必須具備 |
| Pull requests (`pull_requests`) | 讀寫 | 讀取拉取請求（包括其 head commit SHA），以及列出、發布與更新 PR 留言 |
| Checks (`checks`) | 讀寫 | 建立與更新檢查執行，包括套件大小的通過／失敗檢查 |

Tuist 使用 `check_run` webhook 事件來處理套件大小檢查動作。Manifest 流程會自動設定此訂閱。

若要在 github.com 上手動設定 App 並搭配自行託管的 Tuist 伺服器，請參閱 <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">自行託管指南</.localized_link>。

#### 獨立的瀏覽器與 API URL {#separate-browser-and-api-urls}

如果工程師透過內部主機名稱存取 GitHub Enterprise，而第三方服務使用外部代理伺服器，請在點擊安裝前設定這兩個位址：

| 欄位 | 範例 | 使用者 |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | 你的瀏覽器，用於 App 註冊與安裝，以及從 Tuist 指向 GitHub 的連結 |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist 的伺服器，用於 manifest-code 交換、存取權杖、儲存庫存取、PR 留言與檢查 |

API URL 是完整的 REST API 基礎 URL，包括 `/api/v3` 或你的代理伺服器公開的等效路徑。Tuist 不會在明確指定的 API URL 後附加 `/api/v3`。如果同一個主機名稱同時適用於你的瀏覽器與 Tuist，請留空；現有連線會繼續使用 `<Server URL>/api/v3`。

兩個位址都必須路由至 **同一個 GitHub Enterprise 執行個體**。你的瀏覽器只需能到達 Server URL，不需要到達 API 代理伺服器。Tuist 的伺服器只需能到達 API URL，不需要到達內部瀏覽器主機名稱。

針對外部代理伺服器：

- 使用 HTTPS，並採用 Tuist 伺服器信任的憑證，且公開 DNS 需解析為公開 IP 位址。API URL 覆寫不會繞過 Tuist 的私有 IP／SSRF 防護。覆寫目標必須是你的 Enterprise 執行個體，而非 `github.com` 或 `*.github.com` 端點。
- 將每個 Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">出站 IP 位址</.localized_link>加入允許清單。
- 轉發 Tuist 使用的 REST API 端點，包括 `POST /api/v3/app-manifests/{code}/conversions`、`POST /api/v3/app/installations/{installation_id}/access_tokens`，以及用於留言與檢查的儲存庫 API 端點。這些是 GitHub 的上游路徑；如果你的代理伺服器公開不同的前綴，請相應翻譯。
- 將請求轉發至 GitHub，不要使用 HTTP 重新導向或互動式登入頁面。Tuist 不會自動追蹤 Enterprise API 重新導向，因此它們無法繞過公開 IP 檢查。在設定期間、Tuist 取得 App 憑證之前，manifest 轉換端點必須可達。GitHub Actions 日誌下載是例外：Tuist 僅透過 HTTPS 追蹤已簽署的封存重新導向，檢查並將每個目的地固定到公開 IP，且不會轉發安裝權杖。

GitHub 可能會使用其內部主機名稱傳回分頁連結。Tuist 會將來自已設定 GitHub 執行個體的連結重新基準化到 API URL，保留你代理伺服器的路徑前綴；指向無關來源的連結會被拒絕。

另外，GitHub 必須能夠將 webhooks 傳遞至 `https://tuist.dev/webhooks/github`（或在你的自行託管 Tuist 伺服器上為 `/webhooks/github`）。工程師必須能夠返回 Tuist 以完成瀏覽器回呼。API URL 不會改變這兩個目的地。

組織管理員也可以使用整合卡片中的 **Save API URL** 來變更或清除現有 Enterprise 整合的 API URL。不需要重新安裝 App 或重新連線專案。清除後會恢復為 `<Server URL>/api/v3`。儲存動作會驗證 URL 格式，而非代理伺服器連線能力。由於安裝查詢會被快取，webhook 處理可能需要最多一分鐘才會使用變更後的位址；已在進行中的請求仍可能使用先前的位址。

> [!NOTE]
> **僅限託管 Tuist 伺服器上的 Enterprise 方案**
>
> 在託管的 Tuist 伺服器（`https://tuist.dev`）上，GitHub Enterprise Server 整合僅提供給採用 **Enterprise** 方案的組織。自行託管的 Tuist 部署可以在任何方案上使用。

## 拉取／合併請求留言 {#pull-merge-request-comments}

GitHub app 會發布 Tuist 執行報告，其中包含 PR 摘要，包括指向最新 <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">預覽</.localized_link> 或 <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">測試</.localized_link> 的連結：

Tuist 會在結果到達時更新一則留言。Gradle 建置會針對每個根專案與請求的工作集分別顯示；重新執行相同工作會取代該次叫用的先前結果。完整的建置歷史記錄仍可在 Tuist 上查看。

留言預設為啟用，以保留現有整合的報告功能。若要為專案關閉或重新開啟留言，請開啟 **Project Settings → Integrations** 並切換 **GitHub → Run report comments**。每個專案都有各自的設定；儲存庫連線仍在組織設定中管理。

停用留言不會停用建置或測試上傳、GitHub Actions 工作摘要、儲存庫連線或其他 GitHub 整合功能。現有留言不會被刪除。

![顯示拉取請求留言的圖片](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **需求**
>
> 只有在你的 CI 執行已 <.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link> 時，才會發布留言。

> [!NOTE]
> **`GITHUB_REF`**
>
> 如果你有一個自訂工作流程，不是由 PR commit 觸發，而是例如由 GitHub 留言觸發，你可能需要確保 `GITHUB_REF` 變數設定為 `refs/pull/<PR_NUMBER>/merge` 或 `refs/pull/<PR_NUMBER>/head`。
>
> 你可以執行相關命令，例如 `tuist share`，並加上前置的 `GITHUB_REF` 環境變數：<code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions 工作摘要 {#github-actions-job-summary}

Tuist CLI 與 Gradle 外掛程式會將測試與建置結果寫入 GitHub Actions 中的 [工作摘要](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)。該摘要會連結至 Tuist 上的完整報告，提供更豐富的見解，例如不穩定測試與套件大小差異。

對於 Gradle，每次成功上傳的建置或測試報告都會附加其自身的摘要，保留由 `gradle/actions/setup-gradle` 等工具寫入的其他內容。這需要包含工作摘要支援的外掛程式版本；較舊的 Gradle 外掛程式版本僅透過 GitHub App 的 PR 留言進行報告。工作摘要不需要連線 GitHub App，且停用 **Run report comments** 不會影響它們。

當 GitHub Actions 摘要目的地可用時，Gradle 會在結束前等待上傳與摘要完成，即使已啟用 `uploadInBackground`。GitHub 會在工作流程步驟結束時擷取摘要。

![顯示 GitHub Actions 工作摘要中 Tuist 執行報告的圖片](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

這在使用 [合併佇列](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) 時特別有用。合併佇列執行未附加至拉取請求，因此不會發布留言，但工作摘要仍會呈現結果。

> [!NOTE]
> **需求**
>
> 工作摘要需要成功的報告上傳。在託管的 Tuist 伺服器上，你的 CI 執行必須 <.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。自行託管的執行個體在啟用網路信任的報告發布時，也可以接受無需憑證的報告。
