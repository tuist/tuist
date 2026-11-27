---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解如何在你的基礎設施上部署 Tuist server。"
}
---
# 伺服器 {#server}

我們提供 Tuist 伺服器的自託管版本，適合需要對基礎設施擁有更多控制權的組織。此版本讓你能夠在自己的基礎設施上託管 Tuist，確保資料安全且私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要具備法律效力的付費授權。Tuist 的內部部署版本僅適用於 Enterprise 方案的組織。若你有興趣使用此版本，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊有的自託管快取節點技術已不建議用於新安裝。請參閱<.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link>以了解目前的自託管快取基礎設施。
>
> 現有部署仍可參考 GitHub Markdown 檢視器中的舊版原始文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)與[快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔通道發布：**canary**（每次提交至 `main`）、**release candidate**（每週一釋出，觀察一週）與**stable**（隔週一提升）。只有穩定版會推進 `:latest` 並預設解析；canary 與 release candidate 屬於 GitHub 預先發布版本，需固定其標籤才會選用。伺服器與 Kura 採用相同的每週發布列車，與<.localized_link href="/cli/release/channels">Tuist CLI 的發布時程</.localized_link>同步。

我們遵循[語義化版本](https://semver.org/)以確保版本可預測且相容。主要版本用於標示 Tuist 伺服器中需要與自託管使用者協調的重大變更；你不必預期我們會頻繁使用它，若確實需要，我們會協助你順利過渡。

請參閱<.localized_link href="/guides/server/self-host/release/channels">發布通道</.localized_link>頁面，了解各通道的建立方式、如何在部署中固定特定通道，以及建議策略：讓生產環境停留在變動較少的穩定線，同時讓預備環境觀察即將推出的版本。

## 瀏覽器工作階段升級 {#browser-session-upgrade}

若七天內沒有經過認證的頁面請求或 LiveView 互動，瀏覽器工作階段將會過期，且最遲不會超過認證後的 30 天。「記住我」會還原相同的伺服器端工作階段，但無法延長任一期限。活動每分鐘檢查一次，因此閒置的工作階段可能提前最多 59 秒過期。WebSocket 心跳、自動重新連線與背景更新不會更新活動狀態。這些期限不會改變機器憑證或 API 權杖的生命週期。

在啟動升級後的應用程式程序之前，先執行累加式 `users_tokens` 遷移。現有的資料列不會回填：其建立時間會限制閒置與絕對過期時間，且在存取強制 SSO 的組織之前必須重新認證。回呼的提供者、簽發者或已驗證的 Workspace，以及自訂 SSO 連線會儲存在伺服器端，並與組織的目前設定進行比對。連結的帳號並非工作階段認證的證明。

在將政策視為已強制執行之前，請升級所有提供服務的網頁複本。較舊的二進位檔仍可能接受原先的 60 天工作階段，且不會強制執行新的 LiveView 邊界；混合版本在結構描述上相容，但在政策上不等效。請預期使用者需要再次登入。回滾到較舊的二進位檔會削弱這些控制措施；若需要結構描述回滾，請在移除新欄位之前停止所有讀取該欄位的二進位檔。切勿延長舊工作階段或推斷來源以避免重新認證。

## 驗證器應用程式 MFA {#authenticator-app-mfa}

伺服器內建原生驗證器應用程式（TOTP）雙因素認證。儀表板目前尚未提供連結；後續版本將加入設定入口。它不需要啟用旗標、託管服務相依性或身分提供者憑證：只需 PostgreSQL、下方的遷移、TOTP 驗證器，以及所有服務複本共用的穩定加密金鑰（`TUIST_SECRET_KEY_ENCRYPTION`， fallback 為 `TUIST_SECRET_KEY_BASE`）。請保持伺服器與驗證器的時鐘同步。MFA 驗證及其每五分鐘五次失敗碼的共用配額使用 PostgreSQL 資料列鎖定，而非 Redis。

設定需要在過去五分鐘內登入，將設定金鑰輸入 TOTP 驗證器應用程式，並確認應用程式產生的代碼。系統只會顯示一次十組單次使用的復原碼；請安全儲存。停用該因素也需要近期登入，以及未使用的驗證器或復原碼。因素變更會撤銷其他瀏覽器工作階段。重設密碼不會移除 MFA，且此實作不提供僅限電子郵件或管理員繞過遺失因素的機制。

一旦註冊，每次新的瀏覽器登入（包括聯合登入）在取得工作階段或完成基於瀏覽器的 CLI/裝置授權之前，都需要原生的第二因素。直接密碼與 Apple API 登入會拒絕已註冊的使用者，並指示他們使用瀏覽器登入。已註冊使用者的新電子郵件代理程式聲明需要經過 MFA 驗證的瀏覽器工作階段；僅限信箱的舊版聲明會被拒絕。現有的 API 權杖、機器憑證、工作負載身分及其更新規則維持不變。這是針對個別使用者的選擇性支援，並非全組織的 MFA 強制要求，也不代表驗證身分提供者自身的 MFA 政策。組織 SSO 除了原生因素外，仍需正確設定的提供者/簽發者。

註冊、登入、使用復原碼或停用 MFA 都不需要提供電子郵件。因素變更通知採盡力而為；傳送失敗不會撤銷已完成的變更。

在新版二進位檔之前，執行獨立的累加式 `user_mfa`/`users_tokens.mfa_verified_at` 遷移。TOTP 秘密金鑰使用現有的 Vault 加密金鑰；請保留該金鑰及其備份。在允許 MFA 註冊之前，先完成 **所有認證服務複本的升級**。舊版二進位檔可以繞過原生 MFA，因此註冊後它們不是符合政策的回滾目標。刪除 MFA 結構描述會破壞註冊和復原狀態；請先停止讀取器並保留加密備份。混合版本結構描述相容性並非 MFA 或瀏覽器工作階段控制已強制實施的證據。

## OAuth 升級與回滾邊界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 實體快取需要對現有安裝進行分階段升級。在部署停止 OAuth 快取失效的版本之前，請先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 的權威讀取相容版本部署到 **每個 OAuth 讀取器和寫入器**。此相容階段首次出現在 **1.355** 發行系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升，生產部署應使用穩定的 `1.355.x` 版本。安裝在 1.354 或更早版本的系統必須在完成此階段後，才能升級到包含移除功能的後續版本。保持 1.355 系列僅用於相容性：不要將失效移除回溯移植到其中。

原始相容性提交也可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 取得。另一個映像檔僅在保留權威讀取 **並保留舊版失效** 且舊版消費者仍存在時，才適合作為相容階段。在提供流量之前，執行該階段的常規資料庫遷移，包括重新整理權杖查找索引。

檢查每個環境中的所有 Web 複本、背景工作器、排程工作和單獨固定的處理器映像檔。等待相容性推出完成，並在移除失效之前驗證沒有剩餘的快取讀取二進位檔。不要在自動升級期間讓浮動映像檔標籤跳過此階段。沒有舊版消費者的全新安裝不需要中間部署。

> [!WARNING]
> **保留權威讀取的回滾目標**
>
> 移除失效後，常規的滾動回滾必須針對 #14040 或其他權威讀取版本。即使每個無失效程序都已停止，保留的 OAuth 快取條目仍可能過時，且重新啟動的快取讀取複本可以從對等節點匯入它們。
>
> 進一步回滾需要停止並排空 **所有** 無失效 OAuth 消費者，然後在啟動任何快取讀取消費者之前清除或替換 **每個** 保留的 Boruta 快取參與者。防止保留的參與者重新加入。僅排空入口或僅重新啟動 Web 複本是不夠的；請與您的 Tuist 支援聯絡人協調此恢復，而不是自動清除快取或回滾資料庫遷移。

## 多複本叢集 {#multi-replica-clustering}

支援的多複本 Web 部署需要 Erlang 叢集來進行跨複本 Phoenix PubSub 和 Oban PG 通知，而非作為認證授權。當 `server.cluster.enabled` 為 false 時，圖表會拒絕多個複本，包括可以增長超過一個複本的自動縮放器。先前接受的未叢集部署必須規劃此升級，而不是繞過防護。在更改成員資格之前，完成 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括失效移除。

使用您的秘密管理器在發布命名空間中建立私有 Cookie Secret，然後設定其名稱和金鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵並由所有參與的 Web 複本共用。切勿使用嵌入在已發布映像檔中的 Cookie：擁有分發 Cookie 即授予在其節點上遠端執行的權限。分散式發布啟動現在拒絕缺少私有 `RELEASE_COOKIE` 或無效埠，包括明確設定的 `RELEASE_DISTRIBUTION=name` 或 `sname` 而沒有 DNS 發現。非圖表部署也必須一致地設定 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 以及 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

使用常規伺服器連接的 `helm upgrade`，將 `cookieExistingSecret` 留空會建立 Cookie Secret 並在後續升級中重用其當前值。離線 `helm template`、Argo CD 和其他沒有即時 Secret 查找的 GitOps 轉譯器無法保留該生成的值；它們必須使用由單獨管理的穩定 Secret 支援的 `cookieExistingSecret`。不要更改 Cookie 金鑰以隱式輪換活動叢集。Cookie 輪換需要協調每個參與者的遷移/重新啟動；僅更新 Secret 不會更新現有程序。

從映像檔內建 Cookie 的首次推出會形成單獨的新舊成員島嶼，直到所有 Web 複本都使用私有 Secret。為即時更新規劃遷移視窗。後續的滾動部署會形成混合版本叢集，因此請根據實際的新舊版本限定 PubSub、Oban 通知和對等替換。這些通知不是持久的交付保證。保留權威讀取的回滾映像檔，並在回滾相容版本時保留相同的私有 Cookie。

僅在受信任的伺服器對等節點之間允許 EPMD（TCP 4369）和設定的分發埠，絕不允許來自租戶工作負載或公共網路。驗證您環境中的實際入口/出口隔離；轉譯 NetworkPolicy 並不證明強制執行或後端可達性。兩複本金絲雀在連續負載下必須通過加入、滾動替換和故障/恢復才能提升。DNS 用於發現對等節點，而不是在瞬態失敗或部分回應時斷開健康節點；真實節點丟失和 OTP 分割預防仍然適用。libcluster 可能仍會記錄保留回呼的成功「斷開」操作而不斷開連接；從節點上線/下線事件或 `Node.list()` 建立實際成員資格，而不僅依賴該日誌行。

## 持續部署 {#continuous-deployment}

我們建議將生產環境鎖定在穩定的次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），這樣日常升級只會包含回溯移植的修復程式。穩定版本線會在候選發布通道上經過一週的浸泡測試後，於每週一 UTC 06:00 提升；在金絲雀或當前候選發布標籤上的暫存環境可以在問題影響使用者之前捕捉到回歸問題。請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布通道</.localized_link> 以了解建議的鎖定策略。

如果您希望在不修改清單檔案的情況下吸收新功能，請鎖定 `:latest`。該標籤每週一早上更新一次，因此請相應安排您的部署視窗。以下是一個 GitHub Actions 工作流程範例，它會按照此頻率檢查並部署最新的穩定映像檔：

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 8 * * 1' # Mondays 08:00 UTC, after the weekly stable promote
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

<span id="network-trusted-report-publishing"></span>
<span id="network-trusted-cache-access"></span>

## 網路信任存取 {#network-trusted-access}

自託管安裝可以允許受信任網路上的開發人員在無需登入的情況下提交洞察報告、使用快取，或兩者兼有。儀表板和管理功能仍然需要驗證。

僅啟用您需要的功能：

| 伺服器環境變數 | 允許無需登入 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交建置和測試洞察報告 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀寫快取的建置輸出 |

這兩個設定預設均為 **關閉**，彼此獨立，並適用於所有帳戶和專案（包括私有專案）的整個實例。它們在託管的 Tuist 上不可用，也不能取代自託管授權。

當未設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 時，舊的 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍作為相容性備援保留。

> [!WARNING]
> 僅在強制執行的辦公網路或 VPN 邊界後方啟用這些設定。任何能夠存取已啟用端點的人都可以提交報告，或者在啟用快取存取時讀取和覆寫快取輸出。這可能導致偽造的遙測資料、快取污染和容量耗盡。報告回應也可能洩露私有專案控制代碼和建置系統。Tuist 不會驗證 VPN 成員資格，也不會信任轉發的 IP 標頭作為成員資格的證明。

### 設定實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口，將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器以及任何 Bazel BES 入口限制在您的受信任網路內。
2. 在升級用戶端之前，先升級每個伺服器和 Kura 複本。保持 Kura 驗證啟用，並使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑證；停用它会繞過這些限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 設定您的快取端點。
3. 在每個相關的 Tuist 伺服器複本上設定上述所需的變數，然後重新啟動或重新部署它們。只有確切的值 `true` 才能啟用設定。沒有儀表板切換開關或單獨的 Kura 標誌。

### 設定用戶端 {#network-trusted-client-configuration}

在每個相容的用戶端上設定最終的自託管伺服器 URL 和專案。當缺少憑證時，用戶端會自動發現哪些功能已啟用；無需用戶端選擇加入。發現過程不會遵循重新導向。現有憑證會繼續使用，無效或刷新失敗的憑證會導致錯誤，而不是匿名回退。請重新登入或明確登出以恢復。

在啟用洞察存取之前，將所有共用憑證的工具升級到能夠保留損壞或被拒絕的憑證、拒絕無法讀取的憑證目錄，並從未簽名報告中省略 Git 來源的版本。較舊的工具可能會刪除憑證並意外允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏發現支援或回滾到較舊版本，用戶端必須進行驗證。舊的 `TUIST_NETWORK_TRUSTED_PUBLISHING` 用戶端設定不再適用。

- **洞察：** 僅提交已完成的 Xcode、Gradle、Elixir/Mix 和 Bazel 報告，不包含封存、附件、涵蓋率、分片規劃或現有報告存取權限。參與者聲明未經驗證；未簽名的遙測資料不會驅動受信任的測試證據或自動化。請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 和 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南以了解用戶端設定和隱私詳細資訊。
- **快取：** 支援 CLI 編譯/模組快取、Bazel 快取和 Gradle 任務快取。快取清除和遠端資產下載仍然需要憑證。不支援的用戶端必須繼續進行驗證。
- **Bazel：** 報告需要明確的 `TUIST_BAZEL_BES_BACKEND` 和相容的 Kura。快取和報告選項是獨立啟用的。在更改憑證或任一設定後，重新執行 `tuist bazel setup`；在更改編譯快取設定後，重新執行 `tuist cache config`。

報告請求限制為每個專案 8 MB、每分鐘 60 個請求和每天 10,000 個請求。為具有多個複本的部署範圍配額設定共用的 Valkey；否則限制是按程序計算的。如果設定的共用配額後端不可用，則會拒絕未簽名的報告。同時添加入口連接、主體和速率限制。

### 停用網路信任存取 {#disable-network-trusted-publishing}

將相關變數設定為 `false`，然後重新啟動 **每個相關的伺服器複本**。舊複本在被替換之前可以繼續接受無需憑證的請求。在最後一個複本切換後的 60 秒內，新請求的快取存取將停止；進行中的傳輸不會被取消。如果需要立即撤銷，請先在入口處封鎖流量。現有報告保留其通常的可見性和保留期，經過驗證的用戶端繼續正常工作。

## 執行時期需求 {#runtime-requirements}

本節概述了在您的基礎設施上託管 Tuist 伺服器的需求。

### 相容性矩陣 {#compatibility-matrix}

Tuist 伺服器已通過測試，並與以下最低版本相容：

| 元件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析所需 |

### 執行 Docker 虛擬化映像檔 {#running-dockervirtualized-images}

我們透過 [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像檔的形式分發伺服器。

要執行它，您的基礎設施必須支援執行 Docker 映像檔。請注意，大多數基礎設施供應商都支援它，因為它已成為在生產環境中分發和執行軟體的標準容器。

### Postgres 資料庫 {#postgres-database}

除了執行 Docker 映像檔外，您還需要一個 [Postgres 資料庫](https://www.postgresql.org/) 來儲存關聯式資料。大多數基礎設施供應商在其產品中都包含 Postgres 資料庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的結構描述遷移。


### ClickHouse 資料庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來儲存和查詢大量分析資料。像建置洞察等功能**需要** ClickHouse。您可以選擇自行託管 ClickHouse，或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的 ClickHouse 結構描述遷移。

內建的 Docker Compose 和 Helm 嵌入式 ClickHouse 設定會將 ClickHouse 文字記錄層級從映像檔預設的 `trace` 降低至 `information`，因為 `system.text_log` 的大部分容量都來自此處。兩者也可以限制 ClickHouse 本身的 `system.*` 作業記錄表（否則這些記錄表沒有上限），但此功能預設為關閉——請參閱下文。外部 ClickHouse 部署應在其 ClickHouse 服務中直接設定這些作業記錄。

#### ClickHouse 複寫拓撲 {#clickhouse-replication-topology}

Tuist 後端的多複本 ClickHouse 僅在 ClickHouse Cloud 上支援。自行管理的 ClickHouse 為單複本。

匯入遷移會產生普通的 `MergeTree` 引擎。在 Cloud 上，這會透明地變成 `SharedMergeTree`，因此寫入會進入共用的物件儲存空間，且任何複本數量皆可運作。在自行管理的 ClickHouse 上，`MergeTree` 只會寫入單一複本的本地磁碟；多複本設定要麼會靜默地在複本之間分割匯入，要麼會以 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒絕 CREATE，具體取決於連線使用者如何設定 `database_replicated_allow_only_replicated_engine`。

在自行管理的 ClickHouse 上執行一個含有一個複本的分片，並定期備份 ClickHouse 資料目錄。如果節點遺失，沒有第二個複本可以回退。

#### 限制作業記錄保留期 {#capping-operational-log-retention}

保留期可套用於 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 和 `system.part_log`。

在已有資料的實例上啟用此功能是一次性且不可逆的步驟，這就是為什麼兩個套件都不會為您執行此操作。任何保留視窗都會導致這些表格定義不再符合其設定，因此 ClickHouse 會將每個表格重新命名並啟動一個新表格，如[已取代的記錄表](#superseded-log-tables)所述。留下的世代包含迄今累積的所有內容，且自身不帶有任何保留期，因此除非您在同一步驟中回收它，否則它將永久保留在磁碟上，而新視窗僅限制從那時起寫入的資料列。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

那單一的 `helm upgrade` 是自包含的，因為將 `ttlDays` 從空白變更為設定值會新增 drop-in 掛載並滾動更新 ClickHouse Pod：它會重新啟動、取代表格，然後升級後作業會刪除它們。使用 `helm upgrade --wait` 進行部署，以便在作業執行前先滾動更新 Pod；否則世代會在作業檢查後才出現，而下一次 `helm upgrade` 則會改為回收它們。

使用 Docker Compose 時，取消註解 `docker-compose.yml` 中 `clickhouse` 服務上的 `clickhouse-log-ttl.xml` 卷冊，並在 `.env` 中設定這兩個變數：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，您可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，這樣後續的 ClickHouse 升級就不會自行丟棄歷史記錄。

#### 已取代的記錄表 {#superseded-log-tables}

ClickHouse 在啟動時會檢查每個系統記錄表是否仍符合其設定。當不符合時，它會將現有表格重新命名為 `system.<name>_0`，然後是 `_1`、`_2` 等，並啟動一個新表格。這會在您更改保留視窗時發生，也會在任何更改系統記錄結構描述的 ClickHouse 升級時發生。

重新命名表格不會複製其資料，因此不會消耗額外的磁碟空間。已取代表格後續的情況取決於其來源表格，因為它會保留被取代那一刻即時表格所擁有的任何保留期。第一次啟用保留期時，被取代的表格沒有任何保留期，因此它會保存迄今累積的所有歷史記錄並無限期保留。隨後對視窗的更改會取代已帶有 TTL 的表格，因此這些表格會自行過期並留下一個空表格。ClickHouse 永遠不會刪除表格本身，因此在長期運行的實例上，它們無論如何都會累積。

預設會保留已取代的表格，這樣升級就不會自行丟棄作業歷史記錄。將政策設定為 `delete` 以改為刪除它們，這會在 `docker compose up` 和每次 `helm upgrade` 時發生：

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

使用 Helm chart 時，將相同政策設定為值：

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

刪除已取代的表格會回收其磁碟空間。即時表格絕不會受到影響，自被取代以來寫入的資料列也不會受到影響。

若要在不更改政策的情況下一次性回收空間，請手動刪除表格：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 資料庫使用 `Atomic` 引擎，這會將普通的 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（預設為八分鐘）。`SYNC` 會立即刪除資料，這正是您在因磁碟已滿而刪除這些表格時想要的行為。


### 儲存空間 {#storage}

您還需要一種解決方案來儲存檔案（例如框架和函式庫的二進位檔）。Tuist 伺服器支援與 S3 相容的儲存空間和 Azure Blob Storage，用於儲存伺服器拥有的工件。

> [!TIP]
> **最佳化快取**
>
> 如果您的主要目標是減少快取延遲，您可能不需要自行託管整個伺服器。您可以在靠近您的 CI 或開發者網路的地方部署自行託管的 Kura 節點，並將它們連接到託管的 Tuist 伺服器或您的自行託管伺服器。
>
> 請參閱<.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link>。


### 自行託管的 Kura 節點 {#self-hosted-cache-nodes}

若要將自行託管的 Kura 節點與自行託管的 Tuist 伺服器搭配使用：

1. 在 Tuist 伺服器上設定 `KURA_CONTROL_PLANE_CLIENT_ID` 和 `KURA_CONTROL_PLANE_CLIENT_SECRET`。用戶端 ID **必須是 UUID**。使用<.localized_link href="/guides/cache/self-host#control-plane-client">自行託管快取指南</.localized_link>中的命令產生 UUID 和隨機金鑰，並將它們儲存在您的部署金鑰中。
2. 依照<.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link>部署 Kura 節點，使用相同的控制平面憑證。
3. 使用 `KURA_REGISTRATION_URL` 和 `KURA_ADVERTISED_HTTP_URL` 設定每個 Kura 節點。註冊心跳會告訴伺服器哪些就緒且面向用戶端的 Kura 端點可以向 CLI 廣播。

## 設定 {#configuration}

服務的設定在執行階段透過環境變數完成。鑑於這些變數的敏感性，我們建議將其加密並儲存在安全的密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變數，確保它們絕不會顯示在日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要的變數會在啟動時進行驗證。如果缺少任何變數，啟動將會失敗，且錯誤訊息會詳細說明缺少的變數。


### 授權設定 {#license-configuration}

作為內部部署使用者，您將收到一個授權，需要將其公開為環境變數。該授權用於驗證部署，並確保服務在協議條款範圍內運行。

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務等級協議後提供的授權。接受標準授權金鑰，或用於無法連線外部服務的隔離環境中的 base64 編碼憑證。 | 是 | | `******` |

> [!WARNING]
> **到期日**
>
> 授權具有到期日。如果授權在 30 天內到期，使用者在使用與伺服器互動的 Tuist 命令時會收到警告。如果您有興趣續訂授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境設定 {#base-environment-configuration}

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從網際網路存取執行個體的基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密資訊的金鑰（例如 Cookie 中的工作階段） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於產生雜湊密碼的鹽值 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於產生隨機權杖的金鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS_PREVIOUS` | 先前的 `TUIST_SECRET_KEY_TOKENS`，仍可驗證輪替前發出的權杖。一旦它們過期（30 天），請將其移除 | 否 | | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於對敏感資料進行 AES-GCM 加密的金鑰。超過 32 位元組的值會被截斷為前 32 位元組；建議使用 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 逗號分隔的 `id:base64` 加密金鑰，每個 32 位元組（`openssl rand -base64 32`）。第一個金鑰用於加密新資料；其他金鑰和 `TUIST_SECRET_KEY_ENCRYPTION`（ID `V1`）仍可用於解密現有資料。使用 `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` 將現有資料移至目前金鑰 | 否 | | `k2:3q2+7w...` |
| `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` | 當不應為 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` 的第一個金鑰時，用於加密新資料的金鑰 ID | 否 | | `V1` |
| `TUIST_SSO_CLIENT_ASSERTION_PRIVATE_KEYS` | 一個或多個 RSA 私鑰（2048 位元或更多），以 PEM 格式串連，讓組織能夠使用 `private_key_jwt` 而非用戶端金鑰向 OAuth2 SSO 提供者驗證 Tuist。第一個金鑰用於簽章；每個金鑰都會發布在 `/.well-known/sso-client-jwks.json`，並在 `/.well-known/sso-client-certificates/<kid>.pem` 提供對應的憑證。若要輪替，請附加新金鑰，讓組織註冊它，然後將其移至第一位。若沒有它，組織只能使用用戶端金鑰。 | 否 | | |
| `TUIST_USE_IPV6` | 當設為 `1` 時，會將應用程式設定為使用 IPv6 位址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程式使用的記錄層級 | 否 | `info` | [記錄層級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 您的 GitHub 應用程式的 slug，取自 `https://github.com/apps/<slug>`。安裝應用程式時需要。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式的 base64 編碼私鑰，以解鎖額外功能，例如自動發布 PR 評論 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程式的私鑰，以解鎖額外功能，例如自動發布 PR 評論。**我們建議改用 base64 編碼版本，以避免特殊字元造成問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件地址以 `@<this-domain>` 結尾且已證明擁有該網域控制權的使用者，可以存取營運 URL（`/ops/*`）。若未設定，則無人可以存取。請參閱 [營運](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 顯示在儀表板導覽列上的標籤徽章，用於識別伺服器執行個體（例如版本號或分支名稱） | 否 | 開發環境中的 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用網頁伺服器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許在未登入的情況下提交建置和測試洞察資料。請參閱 [網路信任存取](#network-trusted-access) 以了解設定和安全需求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許在未登入的情況下讀取和寫入快取。請參閱 [網路信任存取](#network-trusted-access) 以了解設定和安全需求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端點，用於傳送追蹤資料 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | Loki 相容端點的基礎 URL，用於推送記錄（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **透過 HTTPS 提供應用程式**
>
> 工作階段 Cookie 標記為 `Secure`，因此瀏覽器會在純 `http://` 連線中捨棄它們，導致使用者無法登入。請在伺服器前方終止 TLS（使用內部 CA 憑證的反向 Proxy 即可），並將 `TUIST_APP_URL` 設為 `https://` URL，即使是內部或僅限 VPN 的部署也是如此。

#### 反向 Proxy 後方的用戶端位址 {#client-addresses-behind-a-reverse-proxy}

伺服器根據用戶端位址進行登入金鑰驗證、API 速率限制和請求記錄。在反向 Proxy 後方，它會從 `X-Forwarded-For` 讀取該位址，且僅信任來自私有網路（RFC 1918、電信級 NAT、迴路、鏈路本地或 IPv6 唯一本地位址）的 Proxy 所寫入的內容：它會採用標頭中最右側的公開位址，因此用戶端無法透過傳送標頭來選擇自己的位址。帶有連接埠的項目（例如 `203.0.113.7:51234`）也會被讀取。

如果 Proxy 從公開位址連線到伺服器，伺服器會忽略該標頭，且每個請求都視為來自 Proxy，因此所有用戶端共用同一個速率限制預算。請透過私有網路將 Proxy 連線到伺服器，以維持每個用戶端的限制。較早的版本會從任何連線中取得最左側的 `X-Forwarded-For` 項目。

### 資料庫設定 {#database-configuration}

下列環境變數用於設定資料庫連線：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 存取 Postgres 資料庫的 URL。請注意，URL 應包含驗證資訊 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程式資料表所使用的 PostgreSQL 結構描述。當您的資料庫政策不允許使用 `public` 結構描述時，請設定此變數。結構描述名稱必須是未加引號的 PostgreSQL 識別碼。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用的選用 Postgres URL。當 `DATABASE_URL` 指向權限較窄的執行階段角色時，請將此變數設為擁有者角色的 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程式資料表權限的執行階段 Postgres 角色。當網頁伺服器不應以結構描述擁有者身分連線時，請搭配 `TUIST_MIGRATION_DATABASE_URL` 使用此變數。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 存取 ClickHouse 資料庫的 URL。請注意，URL 應包含驗證資訊 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 設為 true 時，會使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫。除非啟用 `TUIST_DATABASE_SSL_VERIFY`，否則不會驗證伺服器憑證 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 設為 true 時，資料庫伺服器憑證必須鏈結至受信任的 CA，並與 `DATABASE_URL` 主機相符。需要 `TUIST_USE_SSL_FOR_DATABASE`。我們建議啟用此選項 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 包含用於驗證資料庫伺服器的 CA 憑證之 PEM 檔案路徑。若未設定，則使用作業系統的信任儲存區 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 在連線池中保持開啟的連線數量 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出的所有連線是否超過佇列間隔的時間間隔（毫秒）[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 佇列中的閾值時間（毫秒），池據此決定是否開始捨棄新連線[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新的時間間隔（毫秒） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新前的最大 ClickHouse 緩衝區大小（位元組） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要執行的 ClickHouse 緩衝區處理程序數量 | 否 | `5` | `5` |

預設情況下，Tuist 會加密資料庫連線，但不會驗證伺服器憑證，因此網路路徑上的攻擊者可以冒充資料庫。請設定 `TUIST_DATABASE_SSL_VERIFY=1` 以進行驗證。如果您的提供者使用其自有 CA 簽署憑證（如 Amazon RDS 和 Google Cloud SQL），請下載其 CA 捆綁包，將其掛載到容器中，並將 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向該檔案。`DATABASE_URL` 中的主機必須與憑證中的名稱或 IP 位址相符。啟用驗證後，無法通過這些檢查的憑證會導致所有資料庫連線失敗，因此啟用後請檢查伺服器記錄中是否有 `Bad Certificate` 或 `Unknown CA`。

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，發布遷移會在執行 Ecto 遷移鏈之前建立結構描述（如果尚不存在）。如果遷移角色無法建立結構描述，請預先建立結構描述並將遷移角色設為其擁有者。

Tuist 透過設定工作階段 `search_path` 將連線指向自訂結構描述。某些池化或 Proxy 化的 Postgres 設定（例如 PgBouncer，或限制啟動參數的託管資料庫）不會套用此設定，工作階段會回退至 `public`，這在遷移期間會顯示為 `permission denied for schema public`。透過此類設定連線時，請將結構描述固定在角色本身，以便每個工作階段無論 Proxy 為何都從該結構描述開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 驗證環境設定 {#authentication-environment-configuration}

我們透過 [身分提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進驗證。若要使用此功能，請確保所選提供者的所有必要環境變數都存在於伺服器環境中。**缺少變數** 將導致 Tuist 略過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登入及自助註冊功能內建且預設啟用。在您需要強制使用身分提供者（例如強制執行 SSO）的實例上，您可以完全關閉它們。這會從登入體驗中移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉所有對應的伺服器端端點，包括 CLI 使用的電子郵件/密碼端點 (`tuist auth`)。

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登入和註冊。設為 `0` 以從登入頁面移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉對應的伺服器端端點 | 否 | `1` | `0` |

#### 停用已設定的身分提供者 {#disabling-a-configured-identity-provider}

預設情況下，只要設定好提供者，它就會顯示為登入選項。若要保留提供者的設定（其憑證仍保持設定），同時將其從登入和註冊頁面中移除，請將對應的開關設為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登入回呼，因此該方法將完全無法使用。

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入（請參閱 [GitHub](#github) 章節，了解為何應用程式會與登入共用其憑證） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登入 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 已設定的 Okta 提供者是否顯示為登入選項 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登入 | 否 | `1` | `0` |

#### GitHub {#github}

我們建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行驗證，但您也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保伺服器環境中包含 GitHub 指定的所有必要環境變數。缺少變數將導致 Tuist 忽略 GitHub 驗證。若要正確設定 GitHub 應用程式：
- 在 GitHub 應用程式的一般設定中：
    - 複製 `Client ID` 並將其設為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 建立並複製新的 `client secret` 並將其設為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以是您伺服器的 IP 位址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀寫
  - 帳戶：
    - 電子郵件地址：唯讀

在 `Permissions and events` 的 `Account permissions` 區段中，將 `Email addresses` 權限設為 `Read-only`。

接著，您需要在 Tuist 伺服器執行的環境中公開下列環境變數：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的用戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的用戶端密碼 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入。您為平台整合（PR 評論等）設定的 GitHub App 會與登入共用其用戶端憑證，因此它會顯示為登入選項。設為 `0` 以保留應用程式，同時從登入頁面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設定 Google 驗證。為此，您需要建立一個類型為 OAuth 用戶端 ID 的新憑證。建立憑證時，請選擇「Web Application」作為應用程式類型，將其命名為 `Tuist`，並將重新導向 URI 設為 `{base_url}/users/auth/google/callback`，其中 `base_url` 是您託管服務運行的 URL。建立應用程式後，複製用戶端 ID 和密碼，並分別將它們設為環境變數 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意畫面範圍**
>
> 您可能需要建立同意畫面。建立時，請務必新增 `userinfo.email` 和 `openid` 範圍，並將應用程式標記為內部使用。


#### Okta {#okta}

您可以透過 [OAuth 2.0](https://oauth.net/2/) 協定啟用 Okta 驗證。您必須依照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些說明</.localized_link> 在 Okta 上 [建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設定 Okta 應用程式期間取得用戶端 ID 和密碼後，您需要設定下列環境變數：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於向 Okta 進行驗證的用戶端 ID。此數字應為您的組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於向 Okta 進行驗證的用戶端密碼 | 是 | | |

數字 `1` 需要替換為您的組織 ID。這通常為 1，但請檢查您的資料庫。

### 儲存環境設定 {#storage-environment-configuration}

 Tuist 需要儲存空間來存放透過 API 上傳的構件。**必須設定其中一種支援的儲存解決方案**，Tuist 才能有效運作。

設定 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇伺服器構件後端：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 伺服器構件儲存後端。對於 S3 相容儲存使用 `s3`，對於 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 相容儲存 {#s3compliant-storages}

您可以使用任何 S3 相容儲存提供者來儲存構件。下列環境變數是驗證及設定與儲存提供者整合所必需的：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於向儲存提供者進行驗證的存取金鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於向儲存提供者進行驗證的秘密存取金鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 儲存貯體所在的區域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 儲存提供者的端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 用於儲存構件的儲存貯體名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | PEM 編碼的 CA 憑證，用於驗證 S3 HTTPS 連線。適用於使用自簽憑證或內部憑證授權單位的隔離環境。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 與儲存提供者建立連線的逾時時間（毫秒） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從儲存提供者接收資料的逾時時間（毫秒） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 與儲存提供者的連線池逾時時間（毫秒）。使用 `infinity` 表示無逾時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 連線池中連線的最大閒置時間（毫秒）。使用 `infinity` 可讓連線永久保持活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個連線池的最大連線數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用的連線池數量 | 否 | 系統排程器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連線至儲存提供者時使用的協定（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將儲存貯體名稱建構為子網域（虛擬主機） | 否 | `false` | `1` |

> [!NOTE]
> **來自環境變數的 AWS Web Identity 驗證**
>
> 如果您的儲存提供者是 AWS，且您希望使用 Web Identity Token 進行驗證，您可以將環境變數 `TUIST_S3_AUTHENTICATION_METHOD` 設定為 `aws_web_identity_token_from_env_vars`，Tuist 將會使用該方法並搭配慣用的 AWS 環境變數。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請依照 [這些文件](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 取得 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設定為 `https://storage.googleapis.com`。其他環境變數與任何其他 S3 相容儲存相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，請設定 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並設定 Azure 儲存帳戶憑證：

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 儲存帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 的儲存帳戶存取金鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 儲存伺服器構件的容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略以使用 `https://<account>.blob.core.windows.net` | 否 | 衍生自帳戶名稱 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 的 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm Chart 時，請設定 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。Chart 的頂層 `objectStorage` 設定仍保持 S3 相容，因為選用的快取和 Registry 鏡像工作負載仍預期使用 S3 相容儲存。若停用這些工作負載且伺服器使用 Azure Blob，請設定 `objectStorage.mode=external` 並將外部物件儲存端點與憑證留空，以避免部署內嵌的 MinIO 服務。

#### 構件保留 {#artifact-retention}

在自託管實例中，構件清理預設為停用。每種支援的構件類型都有專屬的環境變數。將變數設定為正整數的天數，即可啟用該構件類型的清理功能。若未設定變數或將其留白，則僅停用該構件類型的清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm Chart 時，請將相同的視窗設定為映射：

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

所有六個鍵皆為選用。此範例啟用了每種支援的構件類型，並各自擁有獨立的保留視窗。省略某個鍵或將其值留白，即可保持該構件類型的清理處於停用狀態。自託管的保留視窗沒有 30 天的上限。若設定的值不是正整數，伺服器將在啟動時失敗。

變更保留變數後，請重新啟動伺服器。每個排入佇列的自託管清理批次在刪除檔案前都會檢查目前的設定，因此取消設定變數、將其留白，或增加其視窗，也能在重新啟動後保護檔案免受待處理作業的影響。

| 環境變數 | 從物件儲存中移除的構件檔案 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 快取、舊版內容定址儲存快取、模組快取和 Gradle 快取檔案 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App 預覽建置和圖示 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 目前和舊版的建置封存 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 儲存在已過期執行之構件前綴下的所有物件，包括結果捆綁包、叫用記錄和 session 封存 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片捆綁包 |

排程清理僅移除構件 blob。它會保留對應的 PostgreSQL 和 ClickHouse 資料列，因此在下載過期後，建置、測試、執行、預覽和分片中繼資料仍可於儀表板中看見。此設定不會變更 ClickHouse 資料表的保留規則。

### 電子郵件設定 {#email-configuration}

Tuist 需要電子郵件功能來進行使用者驗證和交易通知（例如重設密碼、帳戶通知）。目前，**僅支援 Mailgun** 作為電子郵件提供者。

| 環境變數 | 描述 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於向 Mailgun 進行驗證的 API 金鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件的網域 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 出現在「寄件者」欄位中的電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 供使用者回覆的選用回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新使用者註冊的電子郵件確認。啟用時，使用者會自動獲得確認，並可在註冊後立即登入 | 否 | 若未設定電子郵件則為 `true`，若已設定電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅在您想要發送電子郵件時才需要電子郵件設定變數。若未設定，系統會自動跳過電子郵件確認

> [!NOTE]
> **SMTP 支援**
>
> 目前不支援通用 SMTP。若您需要為內部部署環境提供 SMTP 支援，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 討論您的需求。


> [!NOTE]
> **隔離網路部署**
>
> 對於沒有網際網路存取權限或未設定電子郵件提供者的內部部署安裝，預設會自動跳過電子郵件確認。使用者可在註冊後立即登入。若您已設定電子郵件但仍想跳過確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。若要在已設定電子郵件的情況下要求電子郵件確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額與密碼重設連結**
>
> 設定電子郵件後，邀請電子郵件（新建、大量或重新發送）限制為每位收件人每五分鐘一封，且每個組織和每位邀請者每小時可突發發送 50 封並以此速率補充。取消邀請不會恢復配額，且當配額用盡時，邀請 API 會回應 `429` 和 `Retry-After`。若有多個複本，請設定共用的 Valkey 以實現整個部署範圍的配額；若已設定但無法使用，則會拒絕發送邀請電子郵件。密碼重設連結會在 15 分鐘後過期。


### Git 平台設定 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台整合</.localized_link>，提供額外功能，例如在您的拉取請求中自動張貼評論。

#### GitHub {#platform-github}

自託管的 Tuist 伺服器無法安裝執行於 `https://tuist.dev` 的 GitHub App。GitHub App 綁定於註冊它們的伺服器，因此您的部署需要在 github.com 上擁有自己的 App。

##### 註冊 App {#platform-github-registering-the-app}

[建立一個 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)，並由您的 GitHub 組織擁有。您可以重複使用為驗證建立的 App，除非您建立的是 OAuth App。請使用以下設定進行配置，並將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 的值：

| 設定 | 值 |
| --- | --- |
| 回呼 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設定 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重定向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任意隨機字串。您將把它設定為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予下列儲存庫權限：

| 權限 | 存取權 |
| --- | --- |
| 內容 | 唯讀 |
| 中繼資料 | 唯讀 |
| 議題 | 讀寫 |
| 拉取請求 | 讀寫 |
| 檢查 | 讀寫 |

同時授予 **成員：唯讀** 組織權限。在 github.com 設定期間，Tuist 會檢查連接組織安裝的人員是否為有效的 GitHub 組織擁有者，而不僅僅是擁有其某個儲存庫存取權的人。

讓 App 訂閱 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **安裝期間請求使用者授權 (OAuth)** 為停用狀態，以便 GitHub 將安裝程式發送至設定 URL。Tuist 會使用額外的 `/integrations/github/authorize` 回呼啟動獨立的授權步驟，以驗證安裝擁有權。當在 GitHub 上開始安裝時，安裝者隨後會選擇一個 Tuist 組織。在 GitHub 組織上的安裝始終會顯示此選項；從 Tuist 啟動的安裝則會保留其組織。

##### 設定伺服器 {#platform-github-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公開頁面 URL 的最後一個路徑元件 `https://github.com/apps/<slug>` | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字 App ID，用於驗證安裝擁有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式的 base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，因為後者對平台處理換行符的方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上設定的 Webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **設定所有必要的 App 憑證**
>
> 組織整合頁面上的 **安裝 GitHub App** 按鈕會保持停用狀態，直到 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私鑰都已設定為止。數字 `TUIST_GITHUB_APP_ID` 也用於驗證安裝擁有權。安裝 URL 嵌入了 App slug，因此若缺少 `TUIST_GITHUB_APP_NAME`，特別是會產生 GitHub 回應 404 的連結。

伺服器重新啟動後，組織管理員將依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 安裝 App 並將儲存庫連接至專案。

##### OIDC 驗證依賴此設定 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 會根據連接到您專案的儲存庫來解析 CI 令牌中的儲存庫聲明，且只能透過已安裝的 GitHub App 建立連接。在您的 CI 工作流程使用 OIDC 進行驗證之前，請完成上述設定。

您的 Tuist 伺服器也需要出站存取您的 CI 供應商的 OIDC 發行者，以取得其簽署金鑰：

| CI 供應商 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變數僅設定 Tuist 的 github.com App。若要改為將 Tuist 與 GitHub Enterprise Server (GHES) 執行個體整合，組織管理員需切換至整合頁面上的 **企業伺服器** 分頁並輸入 GHES 基礎 URL — Tuist 會引導他們透過 GitHub 的 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 執行個體上註冊全新的 Tuist App。新 App 的憑證會依安裝加密儲存；不需要額外的 `TUIST_GITHUB_APP_*` 環境變數。

#### Origin {#platform-origin}

自託管的 Tuist 伺服器需要自己的 Origin app，並使用您部署的 URL 和簽署金鑰進行設定。為每個 Tuist 環境註冊單獨的 app，以使安裝和憑證保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽署金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設定](https://cursor.com/codebase/settings/apps) 中建立 app。將 `origin-app-public.pem` 的內容註冊為其公開簽署金鑰。保密 `origin-app-private.pem`；您將把它提供給 Tuist 伺服器，而不是上傳到 Cursor。
3. 設定下列設定，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎 URL：

   | 設定 | 值 |
   | --- | --- |
   | 首頁 URL | `YOUR_APP_URL` |
   | 重新導向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 複製已註冊的 App ID，其開頭為 `app_`。

Tuist 在安裝期間會請求下列權限：

| 範圍 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 尋找拉取請求及其目前的 head commit。 |
| `repository:pull_requests:reviews:write` | 讀取、發布及更新報告評論。Origin 包含對應的 review-read 權限。 |
| `repository:metadata:read` | 探索儲存庫並讀取其預設分支。由 Origin 自動授予。 |

不要選取可選的儲存庫 webhook 事件。安裝生命週期通知已足夠；不需要原始碼存取、合併權限和 check-run 權限。

##### 設定伺服器 {#platform-origin-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設定複製的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符號。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私密金鑰儲存在您部署的密鑰管理器中。保留其多行 PEM 格式；此設定不接受 base64 編碼的替代方案。切勿將金鑰提交至原始碼控制或在日誌中揭露。兩個變數必須屬於同一個已註冊的 app。

您的 Tuist 伺服器需要對 `api.cursor.com` 具有出站 HTTPS 存取權限。Cursor 必須能夠將請求傳送至 webhook URL，且管理員必須能夠在瀏覽器中返回重新導向 URI。兩個已註冊的 URL 必須與您部署的 HTTPS 基礎 URL 相符。

##### 安裝 App {#platform-origin-installing-the-app}

伺服器重新啟動後，管理員開啟 **設定 → 整合**，在 Origin 下方選擇 **連接**，並核准 app 對適當 Origin 帳戶和儲存庫的存取權限。整個流程中都會保留 Tuist 組織。若直接從 Origin 發起安裝，則會提示管理員登入並選擇要連接的 Tuist 組織。接著他們選擇 **新增專案連接**，將 Tuist 專案連結至原生儲存庫。

請參閱 <.localized_link href="/guides/integrations/gitforge/origin">Origin 整合指南</.localized_link> 以了解專案連接和結果上傳需求。安裝 app 不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

#### Entire {#platform-entire}

自託管的 Tuist 伺服器需要自己的 Entire 外掛程式，並使用您部署的 URL 和簽署金鑰進行設定。Entire 外掛程式需要合作夥伴註冊，因此請在開始前聯絡 Entire。為每個 Tuist 環境註冊單獨的外掛程式，或至少註冊單獨的簽署金鑰，以使安裝和憑證保持獨立。

##### 註冊外掛程式 {#platform-entire-registering-the-plugin}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽署金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. 依照 Entire 的 [外掛程式註冊指南](https://docs.entire.com/guides/api/plugins/register) 註冊外掛程式。分享 `entire-plugin-public.pem` 的內容，或發布該內容的 JWKS URL，作為外掛程式的簽署金鑰。保密 `entire-plugin-private.pem`；您將把它提供給 Tuist 伺服器，而不是 Entire。
3. 設定下列 URL，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎 URL：

   | 設定 | 值 |
   | --- | --- |
   | 安裝後 URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL | `YOUR_APP_URL/webhooks/entire` |

4. 記錄 Entire 確認的外掛程式 slug 及其提供的 webhook 簽署金鑰 URL。

請求下列權限：

| 權限 | 用途 |
| --- | --- |
| `contents:read` | 接收 Trail 事件，並找出包含其 head commit 的開啟中和草稿狀態 Trails。 |
| `checks:write` | 發布 Tuist gate。 |
| `findings:write` | 發布並解決失敗和不穩定測試的發現項目。 |
| `discussions:write` | 張貼並更新摘要評論。未授予此權限的安裝仍會收到 gate 和發現項目。 |

不需要儲存庫寫入存取權限。若您將權限新增至現有註冊，請要求 Entire 進行更新，並確認安裝已授予新權限。請參閱 Entire 的 [Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings) 和 [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) 合約。

##### 設定伺服器 {#platform-entire-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認的外掛程式 slug。 | 是 | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符號。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 註冊時由 Entire 提供的 webhook 簽署金鑰 URL。 | 是 | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 當您透過 JWKS 註冊簽署金鑰時的金鑰 ID。 | 否 | | |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core URL。 | 否 | `https://eu.auth.entire.io` | |

將私密金鑰儲存在您部署的秘密管理員中，並保留其多行 PEM 格式。切勿將金鑰提交至原始碼控制或暴露在日誌中。使用 Tuist Helm chart 時，您可以改為將 PEM 儲存在您的 1Password 保險庫中，命名為 `ENTIRE_PLUGIN/private_key`，並同時啟用 `server.config.entirePluginKey.enabled` 和 `server.config.managedSecrets`；項目和欄位名稱可透過 `server.config.entirePluginKey.item` 和 `.field` 進行設定。此對應不會設定 slug 或 webhook 簽署金鑰 URL。

您的 Tuist 伺服器需要對 Entire Core 以及為您儲存庫提供服務的区域性 Entire API 主機具有出站 HTTPS 存取權限，這些主機均位於 `entire.io` 或 `entire.com` 之下。Tuist 會驗證安裝收據和 webhook 簽章，發行短效且限定儲存庫範圍的權杖，且絕不會將權杖嵌入報告連結中。

##### 啟用整合 {#platform-entire-enabling-the-integration}

在推出應用程式之前套用伺服器遷移，然後全域啟用 `entire_trails` 功能旗標，以向所有帳戶或選定帳戶提供此整合。啟用旗標不會改變誰可以在 Entire 中安裝外掛程式；若要在擁有該外掛程式的 Entire 專案之外提供它，請聯絡您的 Entire 聯絡人允許此操作。此整合獨立於 Tuist 的 CI 執行設定。

若您回滾應用程式，請保留 `entire_trail_reports` 資料表，以便後續升級可以恢復進行中的發布。

接著，管理員依照 <.localized_link href="/guides/integrations/gitforge/entire">Entire 整合指南</.localized_link> 安裝外掛程式並將儲存庫連接至專案。安裝外掛程式不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

## 本機測試 {#testing-locally}

我們提供完整的 Docker Compose 設定，其中包含在部署至基礎設施之前，於本機電腦上測試 Tuist 伺服器所需的所有相依元件：

- PostgreSQL 15
- ClickHouse 26.5（用於分析）
- ClickHouse Keeper（用於協調）
- MinIO（用於 S3 相容儲存）
- Kura（用於本機自託管快取測試）
- pgweb（用於資料庫管理）

> [!CAUTION]
> **需要授權**
>
> 執行 Tuist 伺服器（包括本機開發實例）在法律上需要有效的 `TUIST_LICENSE` 環境變數。若您需要授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速入門：**

1. 下載設定檔：
   ```bash
   curl -O https://tuist.dev/server/self-host/docker-compose.yml
   curl -O https://tuist.dev/server/self-host/clickhouse-config.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-level.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-ttl.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-keeper-config.xml
   curl -O https://tuist.dev/server/self-host/.env.example
   ```

2. 設定環境變數：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   內建的 ClickHouse 服務接受下列選用營運日誌控制項：

   | 環境變數 | 說明 | 預設值 | 範例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌資料表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留天數 | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 伺服器記錄器與 `system.text_log` 層級 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 替換系統日誌資料表時，如何處理其留下的 `<name>_N` 資料表。`ignore` 會保留它們，`delete` 則會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 與相依元件映像的 `linux/arm64` 變體。若要在偵錯時強制使用 amd64 模擬，請以 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 執行 Compose。

   內建的 compose 檔案使用具名 Docker 磁碟區來儲存持久化資料。若您將其取代為主機繫結掛載，請先建立主機目錄，並確保容器使用者可寫入這些目錄，尤其是 ClickHouse 與 ClickHouse Keeper 的資料目錄。

4. 透過 http://localhost:8080 存取伺服器

**服務端點：**
- Tuist Server：http://localhost:8080
- Kura 快取（HTTP + REAPI gRPC 共用同一埠）：http://localhost:4000
- MinIO Console：http://localhost:9003（憑證：`tuist` / `tuist_dev_password`）
- MinIO API：http://localhost:9002
- pgweb（PostgreSQL UI）：http://localhost:8081
- Prometheus Metrics：http://localhost:9091/metrics
- ClickHouse HTTP：http://localhost:8124

**常見指令：**

檢查服務狀態：
```bash
docker compose ps
# or: podman compose ps
```

檢視日誌：
```bash
docker compose logs -f tuist
```

停止服務：
```bash
docker compose down
```

重置所有內容（刪除所有資料）：
```bash
docker compose down -v
```

**設定檔：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 設定
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 設定
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 設定
- [.env.example](/server/self-host/.env.example) - 環境變數範例檔

## 使用 Helm 部署至 Kubernetes {#kubernetes-with-helm}

Tuist 提供用於在 Kubernetes 上部署的官方 Helm Chart。該 Chart 封裝了 Tuist 伺服器與快取服務，以及可視需求替換為外部供應商的內建基礎設施相依元件。

### 安裝 Chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

若要鎖定特定 Chart 版本：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### 授權 {#helm-license}

`server.license.key` 值同時接受標準授權金鑰，以及用於隔離環境安裝的 Base64 編碼授權憑證；伺服器會自動偵測其類型。

使用 `--set` 傳遞授權可進行快速安裝。若將您的值納入版本控制，請將授權儲存在由 Helm 外部管理的 Kubernetes Secret 中（例如透過 Vault、Sealed Secrets 或 SOPS），並將 Chart 指向該 Secret：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下方的項目會命名您 Secret 中存放授權值的欄位，該值可以是授權金鑰，或是用於隔離環境安裝的 Base64 編碼授權憑證。`existingSecretKeys` 下方的每個項目預設為 Chart 自身的金鑰名稱，因此請將您的 Secret 中不包含的項目設為空字串，如同上方的 `certificateBase64`。否則，Pod 會參考不存在的金鑰而無法啟動。請在安裝或升級 Chart 之前，於 Release 所在的命名空間中建立該 Secret。

請僅透過單一來源設定授權：`server.license.key` 或 `server.license.existingSecret`。若未設定任何來源或同時合併多個來源，Chart 將無法渲染。透過 `server.extraEnv` 傳遞的授權不被視為來源，因此請改用 `existingSecret`。

### 基礎設施相依元件 {#helm-infrastructure-dependencies}

此 Chart 管理三項基礎設施相依元件：`postgresql`、`clickhouse` 與 `objectStorage`。每項預設皆為 **內建** 模式，表示 Chart 會將其部署於叢集內部。若要改為指向您自己的外部執行個體，請將相依元件的 `mode` 設為 `external`，並在您的 `values.yaml` 中填入連線詳細資訊。例如，若要使用外部 PostgreSQL 資料庫：

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

若您在 Helm 之外管理 PostgreSQL 憑證，請改為將 Chart 指向現有的 Kubernetes Secret：

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

Chart 會從 Secret 讀取主機、使用者名稱與密碼，並透過 Kubernetes 環境變數替換組合出 `DATABASE_URL`，因此密碼不會被渲染至 Helm 清單中。由於密碼會被插值至資料庫 URL，其值應符合 URL 安全規範。

相同模式也適用於 `clickhouse` 與 `objectStorage`。請參閱 Chart 的 `values.yaml` 中各章節下的 `external` 區塊，以取得完整的可設定欄位清單。

### 共用排程與標籤 {#helm-shared-scheduling-and-labels}

Chart 在 `global` 下公開一組共用的 Pod 設定，讓營運人員能調整部署以適應其叢集，而無需為每個工作負載重複相同的值：

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

當您需要以下操作時，請使用這些設定：

- 為每個 Pod 新增叢集專屬標籤
- 從私人註冊表拉取鏡像映像
- 鎖定專用的節點池
- 允許 Pod 调度至保留給 Tuist 工作負載的污點節點

### 工作負載身分與服務帳戶 {#helm-workload-identity}

Chart 會依應用程式工作負載範圍限定服務帳戶，讓您僅在需要的地方授予身分：

- `server.serviceAccount` 適用於 Tuist 伺服器部署與遷移作業
- `cache.serviceAccount` 適用於快取部署

例如，當快取在 EKS 上使用外部 S3 儲存貯體時，您可以為快取工作負載啟用 IRSA，而無需將相同的 IAM 角色附加至內建資料庫：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 相容性覆寫 {#helm-compatibility-overrides}

Chart 將儲存與服務網格專屬的微調設為選擇性啟用，以保持預設值的可移植性：

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      supersededTables: delete
      level: warning
```

僅在您的叢集需要時才使用這些覆寫：

- `cache.podSecurityContext` 預設為空。若您的儲存類別或 CSI 驅動程式需要在掛載的磁碟區上共用群組擁有權，請設定 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 的標準原生服務埠 `9000`，當服務網格或平台保留與該埠衝突時可以變更。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，使 ClickHouse 對內建內部日誌表（例如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 與 `system.part_log`）保持無限制的保留。設定此值會一次性取代這些表格，因此請與 `supersededTables: delete` 搭配採用 — 請參閱 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制營運日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對於內建的 ClickHouse 伺服器記錄器與 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不屬於任何表格定義的一部分，因此變更它永遠不會取代表格。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore`，並決定當 ClickHouse 取代系統日誌表時，`<name>_N` 表格的處理方式。將其設為 `delete` 以便在每次 `helm upgrade` 時刪除它們。
- 對 `ttlDays` 與 `level` 的編輯會在 ClickHouse Pod 下次重新啟動時生效，因為兩者皆為 `subPath` 掛載，且當其 ConfigMap 變更時，Chart 不會滾動更新 StatefulSet。

### 可觀測性 {#helm-observability}

Chart 包含一個選擇性的可觀測性堆疊（OpenTelemetry Collector、Prometheus、Grafana、Loki 與 Tempo）。它預設為 **停用**。若要在您的 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 即可使用，且已預先設定好日誌、追蹤與指標的下鑽功能。若使用外部可觀測性，請保持此項停用，並透過 `server.extraEnv` 設定端點：

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### 值參考 {#helm-values-reference}

如需完整的可設定值清單，請參閱 Chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 映像位於：
```
ghcr.io/tuist/tuist
```

已發布的映像包含用於 `.xcactivitylog` 封存檔的內建 Linux 建置處理功能，因此自託管部署可以在不需執行任何額外服務的情況下處理建置 — `ProcessBuildWorker` Oban 作業會在每個伺服器 Pod 中以程序內方式執行。若您想將建置處理卸載至專用的副本集（例如，為了獨立於網頁層擴展解析吞吐量），請在 Helm Chart 中設定 `processor.enabled: true`：Chart 會將同一映像部署為僅消費佇列的角色（`TUIST_PROCESSOR_MODE=true`）。如需完整的控制參數，請參閱 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

> [!NOTE]
> `.xcresult` 解析依賴 Xcode 中的 `xcresulttool`，因此只能在 macOS 上執行。CLI 會為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 伺服器預設採用 **本機** 處理模式，在開發者機器上解析 xcresult（該機器已具備用於建置本身的 Xcode）並上傳結構化結果。測試結果可在不需任何額外基礎設施的情況下被攝取。

### 拉取 Docker 映像 {#pulling-the-docker-image}

您可以執行以下指令來取得映像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

該映像同時發布了 `linux/amd64` 與 `linux/arm64` 版本，因此 Docker 會自動為主機選取原生的 Linux 架構。

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像 {#deploying-the-docker-image}

Docker 映像的部署流程會因您選擇的雲端供應商與組織的持續部署方式而異。由於大多數雲端解決方案與工具（例如 [Kubernetes](https://kubernetes.io/)）皆以 Docker 映像為基本單位，本節中的範例應能與您現有的設定良好搭配。

> [!WARNING]
> 若您的部署管線需要驗證伺服器已啟動並運作中，您可以向 `/ready` 發送 `GET` HTTP 請求，並確認回應中的狀態碼為 `200`。


#### Fly {#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，您需要一個 `fly.toml` 設定檔。建議在您的持續部署 (CD) 管線中動態產生該檔案。以下提供參考範例供您使用：

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

接著您可以執行 `fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署時，請執行 `fly deploy --local-only` 而非 `fly launch --local-only`。Fly.io 不允許拉取私有 Docker 映像，因此我們需要使用 `--local-only` 旗標。


## Prometheus 指標 {#prometheus-metrics}

Tuist 在 `/metrics` 公開 Prometheus 指標，協助您監控自託管實例。這些指標包括：

### Finch HTTP 用戶端指標 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 用戶端，並公開關於 HTTP 請求的詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求持續時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - 區間：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求例外總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連線池佇列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連線池佇列中等待的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在使用前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 區間：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列例外總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連線指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所花的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`error`
  - 區間：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 連線嘗試總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`

#### 傳送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 傳送請求所花的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連線在傳送前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標都提供 `_bucket`、`_sum` 和 `_count` 變體，以便進行詳細分析。

### 其他指標

除了 Finch 指標外，Tuist 還公開以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳號、專案等）
- 資料庫效能（使用 Tuist 託管基礎設施時）

## 營運 {#operations}

Tuist 在 `/ops/` 下提供一組實用工具，可用於管理您的實例。

> [!WARNING]
> **授權**
>
> 只有電子郵件網域符合 `TUIST_OPERATOR_EMAIL_DOMAIN` 的使用者才能存取 `/ops/` 端點。若未設定此變數，則無人可以存取。請將其設為您控制的郵件網域。
>
> 使用者也必須證明其對位址的控制權：透過點擊確認或重設密碼電子郵件、使用 Google、GitHub 或 Apple 登入，或輸入一次性代碼或出示代理登入的已驗證電子郵件。自動確認的帳號（在未設定郵件提供者時的預設行為）在完成證明前不符合資格。帳號建立後，僅當位址位於 `TUIST_OPERATOR_EMAIL_DOMAIN` 中時才會記錄證明，因此在您設定或變更該變數後，尚未據此證明其位址的管理員必須再次證明。透過其中一個提供者登入或透過代理登入建立的帳號，會從建立時就攜帶證明。若無郵件提供者，以密碼註冊的帳號無法連結這些提供者，因此請透過 Google、GitHub 或 Apple 登入來建立管理員帳號，或設定郵件提供者。
>
> 在此檢查存在之前建立的帳號尚未記錄該證明，因此現有管理員在重設密碼或使用其中一個提供者登入一次後即可重新取得存取權。
>
> 當管理員網域中尚未具備該證明的帳號首次以該方式證明其位址時，Tuist 會移除其密碼、通行金鑰以及與組織單一登入提供者的連結，並將其從瀏覽器及 CLI 登出，因為註冊該位址的人可能並非其擁有者。對此類帳號執行密碼重設也會產生相同效果，差別在於會設定新密碼。帳號上設定的驗證器應用程式會保留；若非擁有者所設，請為其移除。管理員網域外的已確認帳號會保留其憑證。擁有者可繼續透過提供者登入，或透過重設設定新密碼。
>
> 由 SCIM 佈建建立或重新命名的帳號，在其擁有者提供證明前不具備任何證明。


- **錯誤（`/ops/errors`）：** 您可以檢視應用程式中發生的非預期錯誤。這有助於除錯並了解問題所在，若您遇到問題，我們可能會要求您與我們分享這些資訊。
- **儀表板（`/ops/dashboard`）：** 您可以檢視提供應用程式效能與健康狀況洞察的儀表板（例如記憶體消耗、執行中的處理序、請求數量）。此儀表板對於判斷您使用的硬體是否足以負載相當有用。
