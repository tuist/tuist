---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解如何在你的基礎設施上部署 Tuist server。"
}
---
# 伺服器 {#server}

我們提供 Tuist 伺服器的自託管版本，適合需要對基礎設施擁有更多控制權的組織。此版本讓你能在自己的基礎設施上託管 Tuist，確保資料安全且私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要具備法律效力的付費授權。Tuist 的本機部署版本僅適用於 Enterprise 方案的組織。若你有興趣使用此版本，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊有的自託管快取節點技術已不建議用於新安裝。請參閱<.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link>以取得目前的自託管快取基礎設施資訊。
>
> 現有部署仍可於 GitHub 的 Markdown 檢視器中參考舊版原始文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)與[快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔通道發布：**canary**（每次提交至 `main`）、**release candidate**（每週一切割，測試一週）以及 **stable**（隔週一提升）。只有穩定版會移動 `:latest` 並預設解析；canary 與 release candidate 屬於 GitHub 預發布版本，需固定其標籤才能選用。伺服器與 Kura 採相同週期同步發布，與 <.localized_link href="/cli/release/channels">Tuist CLI 的發布時程</.localized_link>保持一致。

我們遵循[語意化版本規範](https://semver.org/)，以確保版本可預測且相容。主版本號用於標示 Tuist 伺服器的重大變更，這類變更需要與自託管使用者協調；你不必預期我們會經常使用主版本號，若確實需要，我們會協助你順利過渡。

請參閱<.localized_link href="/guides/server/self-host/release/channels">發布通道</.localized_link>頁面，了解各通道的切割方式、如何在部署中固定特定版本，以及建議策略：讓生產環境停留在變動較少的穩定線，同時讓暫存環境測試即將推出的版本。

## 瀏覽器工作階段升級 {#browser-session-upgrade}

若七天内沒有經過驗證的頁面請求或 LiveView 互動，瀏覽器工作階段就會過期，且最遲不會超過驗證後的 30 天。「記住我」會還原相同的伺服器端工作階段，但無法延長任一期限。活動狀態每分鐘檢查一次，因此閒置的工作階段可能提前最多 59 秒過期。WebSocket 心跳、自動重新連線與背景更新不會刷新活動狀態。這些期限不會影響機器憑證或 API Token 的有效期限。

在啟動升級後的應用程式程序之前，先執行附加的 `users_tokens` 遷移。現有資料列不會回填：其建立時間會限制閒置與絕對過期時間，且在存取強制 SSO 的組織前必須重新驗證。回呼中的提供者、發行者或已驗證的 Workspace，以及自訂 SSO 連線會儲存在伺服器端，並與組織目前的設定進行比對。已連結的帳號不等於工作階段驗證證明。

在將政策視為強制生效前，請升級所有提供服務的網頁複本。舊版二進位檔仍可能接受原先的 60 天工作階段，且不會強制新的 LiveView 邊界；混合版本在結構描述上相容，但在政策上並不等同。預期使用者需要再次登入。回滾至舊版二進位檔會削弱這些控制；若需要結構描述回滾，請在移除新欄位前停止所有讀取該欄位的二進位檔。切勿延長舊工作階段或推斷來源以避免重新驗證。

## 驗證器應用程式 MFA {#authenticator-app-mfa}

伺服器內建原生驗證器應用程式（TOTP）雙因素驗證。儀表板目前尚未提供入口；後續版本將加入設定入口。它不需要啟用旗標、託管服務相依性或身分提供者憑證：只需 PostgreSQL、下方的遷移、TOTP 驗證器，以及所有服務複本共用的穩定加密金鑰（`TUIST_SECRET_KEY_ENCRYPTION`，備用為 `TUIST_SECRET_KEY_BASE`）。請保持伺服器與驗證器的時鐘同步。MFA 驗證及其每五分鐘最多五次失敗碼的共用額度使用 PostgreSQL 資料列鎖定，而非 Redis。

設定需要在最近五分鐘內登入、將設定金鑰輸入 TOTP 驗證器應用程式，並確認應用程式產生的代碼。系統僅顯示一次十組單次使用的復原碼；請妥善儲存。停用該因素也需要近期登入以及未使用的驗證器或復原碼。變更因素會撤銷其他瀏覽器工作階段。重設密碼不會移除 MFA，且此實作不提供僅限電子郵件或管理員繞過遺失因素的機制。

註冊後，每次新的瀏覽器登入（包含聯合登入）在取得工作階段或完成基於瀏覽器的 CLI/裝置授權前，都需要通過原生第二因素驗證。直接密碼與 Apple API 登入會拒絕已註冊使用者，並指示其使用瀏覽器登入。已註冊使用者的新電子郵件代理權限聲明需要經過 MFA 驗證的瀏覽器工作階段；僅限信箱的舊版權限聲明會被拒絕。現有的 API Token、機器憑證、工作負載身分及其續約規則維持不變。這是選擇性的每使用者支援，並非組織範圍的 MFA 強制要求，也不代表驗證身分提供者自身的 MFA 政策。組織 SSO 除了原生因素外，仍需正確設定的提供者/發行者。

註冊、登入、使用復原碼或停用 MFA 都不需要提供電子郵件。因素變更通知為尽力而為；傳送失敗不會撤銷已完成的變更。

在部署新二進位檔之前，先執行獨立的附加遷移 `user_mfa`/`users_tokens.mfa_verified_at`。TOTP 密鑰使用現有的 Vault 加密金鑰；請保留該金鑰及其備份。在允許 MFA 註冊之前，請完成**所有認證服務複本的升級**。舊版二進位檔可以繞過原生 MFA，因此在註冊後它們不是符合政策要求的回滾目標。刪除 MFA 結構描述會破壞註冊和復原狀態；請先停止讀取器並保留加密備份。混合版本結構描述相容性並不代表強制執行了 MFA 或瀏覽器工作階段控制。

## OAuth 升級與回滾邊界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 實體快取需要對現有安裝進行分階段升級。在部署停止 OAuth 快取失效的版本之前，請先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 的權威讀取相容版本部署到**每個 OAuth 讀取器和寫入器**。此相容階段首次出現在 **1.355** 發行系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升為穩定版，生產環境部署應使用穩定的 `1.355.x` 版本。安裝在 1.354 或更早版本的系統必須在完成此階段後，才能升級到包含移除功能的後續版本。保持 1.355 系列僅用於相容性：不要將失效移除功能回溯移植到其中。

原始相容性提交也可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 取得。另一個映像檔僅在保留權威讀取**並保留舊版失效機制**（同時仍有舊版消費者存在）的情況下，才適合作為相容階段。在提供服務流量之前，請執行該階段的常規資料庫遷移，包括刷新令牌查找索引。

檢查每個環境中的所有 Web 複本、背景工作器、排程作業以及單獨固定的處理器映像檔。等待相容性推出完成，並在移除失效機制之前驗證沒有剩餘的快取讀取二進位檔。不要在自動升級期間讓浮動映像標籤跳過此階段。沒有舊版消費者的全新安裝不需要中間部署。

> [!WARNING]
> **保留權威讀取的回滾目標**
>
> 移除失效機制後，常規的滾動回滾必須針對 #14040 或其他權威讀取版本。即使所有無失效機制的處理程序都已停止，保留的 OAuth 快取條目仍可能過時，且重新啟動的快取讀取複本可能會從對等節點匯入它們。
>
> 進一步回滾需要停止並排空**所有**無失效機制的 OAuth 消費者，然後在啟動任何快取讀取消費者之前清除或替換**每個**保留的 Boruta 快取參與者。防止保留的參與者重新加入。僅排空入口或僅重新啟動 Web 複本是不夠的；請與您的 Tuist 支援聯絡人協調此恢復過程，而不是自動清除快取或回滾資料庫遷移。

## 多複本叢集 {#multi-replica-clustering}

支援的多複本 Web 部署需要 Erlang 叢集來進行跨複本的 Phoenix PubSub 和 Oban PG 通知，而非作為認證授權機構。當 `server.cluster.enabled` 為 false 時，Chart 會拒絕多個複本，包括可以擴展到超過一個複本的自動縮放器。先前接受的非叢集部署必須規劃此升級，而不是繞過保護機制。在變更成員資格之前，請完成<.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括移除失效機制。

使用您的密鑰管理器在 release 命名空間中建立私人 Cookie Secret，然後設定其名稱和金鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵值，並由所有參與的 Web 複本共用。切勿使用嵌入在已發布映像檔中的 Cookie：擁有分發 Cookie 即授予在其節點上遠端執行的權限。分散式發布啟動現在會拒絕缺少的私人 `RELEASE_COOKIE` 或無效的連接埠，包括明確設定的 `RELEASE_DISTRIBUTION=name` 或 `sname` 但沒有 DNS 發現的情況。非 Chart 部署也必須一致地設定 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 以及 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

使用常規伺服器連接的 `helm upgrade` 時，將 `cookieExistingSecret` 留空會建立 Cookie Secret，並在後續升級中重複使用其當前值。離線 `helm template`、Argo CD 和其他沒有即時 Secret 查找功能的 GitOps 渲染器無法保留該生成的值；它們必須使用由單獨管理的穩定 Secret 支援的 `cookieExistingSecret`。不要透過變更 Cookie 金鑰來隱式輪換運行中的叢集。Cookie 輪換需要協調每個參與者的遷移/重新啟動；僅更新 Secret 不會更新現有處理程序。

從映像檔內建 Cookie 進行的首次推出會形成單獨的新舊成員資格島嶼，直到所有 Web 複本都使用私人 Secret。請為即時更新規劃遷移視窗。後續的滾動部署會形成混合版本叢集，因此請根據實際的新舊版本評估 PubSub、Oban 通知和對等節點替換。這些通知不是持久的交付保證。在回滾相容版本時，請保留權威讀取的回滾映像檔並保持相同的私人 Cookie。

僅允許受信任的伺服器對等節點之間使用 EPMD（TCP 4369）和設定的分發連接埠，絕不允許來自租戶工作負載或公共網路的連線。驗證您環境中的實際入口/出口隔離；渲染 NetworkPolicy 並不能證明強制執行或後端可達性。兩複本金絲雀部署在持續負載下必須通過加入、滾動替換和故障/恢復測試才能提升。DNS 用於發現對等節點，而不是在暫時失敗或部分回應時斷開健康節點的連線；實際節點丟失和 OTP 分割預防仍然適用。libcluster 可能仍會記錄保留回呼的成功「斷開」操作而不斷開連線；請從節點上線/下線事件或 `Node.list()` 確定實際成員資格，而不僅依賴該日誌行。

## 持續部署 {#continuous-deployment}

我們建議將生產環境固定於穩定的次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），以便日常升級僅交付回溯移植的修正。穩定版本線會在候選發布通道進行一週的浸泡測試後，於每週一 UTC 06:00 提升；在 canary 或當前候選發布標籤上的暫存環境可在問題影響使用者之前攔截回歸。請參閱<.localized_link href="/guides/server/self-host/release/channels">發布通道</.localized_link>以了解建議的固定策略。

若您希望在不更動設定檔的情況下，隨著新功能穩定而直接採用，請固定使用 `:latest`。該標籤每週一早上更新一次，請據此安排您的部署視窗。以下是一個 GitHub Actions 工作流程範例，會依此頻率檢查並部署最新的穩定映像檔：

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

自行託管的安裝可允許受信任網路上的開發者在無需登入的情況下提交洞察報告、使用快取，或兩者兼用。儀表板和管理功能仍需要驗證。

僅啟用您需要的功能：

| 伺服器環境變數 | 允許無需登入 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交建置與測試洞察報告 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀取和寫入快取的二進位輸出 |

這兩項設定預設均為**關閉**，彼此獨立，並適用於執行個體中的所有帳號與專案，包括私人專案。它們在 Tuist 託管服務上不可用，且不能取代自行託管授權。

當未設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 時，舊有的 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍作為相容性備援。

> [!WARNING]
> 僅在強制實施的辦公室網路或 VPN 邊界後方啟用這些設定。任何能存取已啟用端點的人都可以提交報告，或在啟用快取存取時讀取並覆寫快取輸出。這可能導致偽造的遙測資料、快取污染以及容量耗盡。報告回應也可能洩露私人專案代號和建置系統。Tuist 不會驗證 VPN 成員資格，也不會將轉發的 IP 標頭視為成員資格的證明。

### 設定執行個體 {#network-trusted-instance-configuration}

1. 使用防火牆或私人入口，將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器以及任何 Bazel BES 入口限制在您的受信任網路內。
2. 在升級用戶端之前，先升級每個伺服器和 Kura 複本。保持 Kura 驗證啟用狀態，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑證；停用該功能會繞過這些限制。請參照<.localized_link href="/guides/features/cache/self-hosting">自行託管快取指南</.localized_link>來設定您的快取端點。
3. 在每個相關的 Tuist 伺服器複本上設定上述所需的變數，然後重新啟動或重新部署它們。只有確切的值 `true` 才能啟用設定。儀表板上沒有切換開關，Kura 也沒有獨立的旗標。

### 設定用戶端 {#network-trusted-client-configuration}

在每個相容的用戶端上設定最終的自行託管伺服器 URL 和專案。當缺少憑證時，用戶端會自動偵測哪些功能已啟用；無需用戶端選擇加入。偵測不會遵循重新導向。現有憑證會繼續使用，無效或刷新失敗的憑證會導致錯誤，而不會退回到匿名模式。請重新登入或明確登出以恢復。

在啟用洞察存取之前，請將所有共用憑證的工具升級至能保留損壞或被拒絕的憑證、拒絕無法讀取的憑證目錄，並在未簽署報告中省略 Git 來源的版本。較舊的工具可能會刪除憑證並意外允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏偵測支援或回滾至較舊版本，用戶端必須進行驗證。舊有的 `TUIST_NETWORK_TRUSTED_PUBLISHING` 用戶端設定已不再適用。

- **洞察：** 僅提交已完成的 Xcode、Gradle、Elixir/Mix 和 Bazel 報告，不包含封存、附件、涵蓋率、分片規劃或現有報告存取。行為者聲明未經驗證；未簽署的遙測資料不會驅動受信任的測試證據或自動化。請參閱<.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link>和<.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link>指南以了解用戶端設定和隱私權詳細資訊。
- **快取：** 支援 CLI 編譯/模組快取、Bazel 快取和 Gradle 工作快取。快取清除和遠端資產下載仍需要憑證。不支援的用戶端必須繼續進行驗證。
- **Bazel：** 報告需要明確的 `TUIST_BAZEL_BES_BACKEND` 和相容的 Kura。快取和報告選項是獨立啟用的。在變更憑證或任一設定後，請重新執行 `tuist bazel setup`；若變更編譯快取設定，請重新執行 `tuist cache config`。

報告請求限制為每個專案每次 8 MB、每分鐘 60 次請求以及每天 10,000 次請求。對於具有多個複本的部署範圍配額，請設定共用的 Valkey；否則限制將針對每個處理程序。如果設定的共用配額後端不可用，未簽署的報告將被拒絕。也請新增入口連線、主體和速率限制。

### 停用網路信任存取 {#disable-network-trusted-publishing}

將相關變數設定為 `false`，然後重新啟動**每個相關的伺服器複本**。舊複本在被替換前可以繼續接受無需憑證的請求。最後一個複本切換後 60 秒內，新請求的快取存取將停止；進行中的傳輸不會被取消。若需要立即撤銷，請先在入口處封鎖流量。現有報告保留其通常的可見性和保留期，已驗證的用戶端繼續正常運作。

## 執行階段需求 {#runtime-requirements}

本節概述了在您的基礎設施上託管 Tuist 伺服器的需求。

### 相容性矩陣 {#compatibility-matrix}

Tuist 伺服器已通過測試，並與下列最低版本相容：

| 元件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能所需 |

### 執行 Docker 虛擬化映像檔 {#running-dockervirtualized-images}

我們透過[GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)以[Docker](https://www.docker.com/)映像檔形式分發伺服器。

若要執行它，您的基礎設施必須支援執行 Docker 映像檔。請注意，大多數基礎設施供應商都支援它，因為它已成為在生產環境中分發和執行軟體的標準容器。

### Postgres 資料庫 {#postgres-database}

除了執行 Docker 映像檔外，您還需要一個[Postgres 資料庫](https://www.postgresql.org/)來儲存關聯式資料。大多數基礎設施供應商在其產品中都包含 Postgres 資料庫（例如[AWS](https://aws.amazon.com/rds/postgresql/)和[Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的結構描述遷移。


### ClickHouse 資料庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來儲存和查詢大量分析資料。像建置見解等功能**需要** ClickHouse。您可以選擇自行託管 ClickHouse，或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的 ClickHouse 結構描述遷移。

隨附的 Docker Compose 和 Helm 內嵌 ClickHouse 設定會將 ClickHouse 文字記錄層級從映像檔預設的 `trace` 降低為 `information`，這也是 `system.text_log` 容量的主要來源。兩者也能限制 ClickHouse 自身的 `system.*` 作業記錄表（否則這些記錄表大小無上限），但此功能預設為關閉—請參閱下文。外部 ClickHouse 部署應在其 ClickHouse 服務中直接設定這些作業記錄。

#### ClickHouse 複寫拓撲 {#clickhouse-replication-topology}

Tuist 後方的多複本 ClickHouse 僅在 ClickHouse Cloud 上支援。自行管理的 ClickHouse 為單一複本。

擷取遷移會產生普通的 `MergeTree` 引擎。在 Cloud 上，這會透明地變更為 `SharedMergeTree`，因此寫入會進入共用的物件儲存空間，且任何複本數量皆可運作。在自行管理的 ClickHouse 上，`MergeTree` 只會寫入單一複本的本地磁碟；多複本設定會依據連接使用者的 `database_replicated_allow_only_replicated_engine` 設定，要麼靜默地在各複本間分割擷取，要麼以 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒絕 CREATE。

在自行管理的 ClickHouse 上執行一個分片搭配一個複本，並定期備份 ClickHouse 資料目錄。若節點遺失，沒有第二個複本可供故障轉移。

#### 限制作業記錄保留期 {#capping-operational-log-retention}

保留期可套用至 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 和 `system.part_log`。

在已有資料的實例上啟用此功能是單向且一次性的步驟，這就是為什麼兩個套件都不會為您自動執行。只要設定任何保留視窗，都會導致這些資料表定義與設定不符，因此 ClickHouse 會將每個資料表重新命名並建立新的資料表，如[被取代的記錄表](#superseded-log-tables)所述。留下的世代會保留迄今累積的所有內容，且本身不帶有任何保留規則，因此除非您在同一步驟中回收它，否則它將永久留在磁碟上，而新視窗僅限制從那時起寫入的資料列。請同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

該單一 `helm upgrade` 是自包含的，因為將 `ttlDays` 從空白改為設定值會新增掛載點並輪替 ClickHouse Pod：它會重新啟動、取代資料表，然後升級後的工作（Job）會刪除它們。請使用 `helm upgrade --wait` 進行部署，以便在工作執行前先輪替 Pod；否則世代會在工作檢查後才出現，而下一次 `helm upgrade` 才會回收它們。

使用 Docker Compose 時，請取消註解 `docker-compose.yml` 中 `clickhouse` 服務上的 `clickhouse-log-ttl.xml` 掛載區，並在 `.env` 中設定這兩個變數：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，您可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，這樣後續的 ClickHouse 升級就不會自行丟棄歷史記錄。

#### 被取代的記錄表 {#superseded-log-tables}

ClickHouse 在啟動時會檢查每個系統記錄表是否仍符合其設定。若不符合，它會將現有資料表重新命名為 `system.<name>_0`，接著是 `_1`、`_2` 等，並建立新的資料表。當您變更保留視窗，或在任何變更系統記錄結構描述的 ClickHouse 升級時，就會發生這種情況。

重新命名資料表不會複製其資料，因此不會消耗額外磁碟空間。被取代的資料表後續會發生什麼情況，取決於其來源資料表，因為它會保留在被取代那一刻即時資料表所擁有的任何保留規則。首次啟用保留時，被取代的資料表沒有任何保留規則，因此它會保留迄今累積的所有歷史記錄並無限期保存。後續對視窗的變更會取代已帶有 TTL 的資料表，因此這些資料會自行過期並留下空的資料表。ClickHouse 永遠不會刪除資料表本身，因此在長期運行的實例上，無論如何它們都會累積。

預設會保留被取代的資料表，因此升級永遠不會自行丟棄作業歷史記錄。將政策設定為 `delete` 以改為刪除它們，這會在 `docker compose up` 和每次 `helm upgrade` 時發生：

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

刪除被取代的資料表會回收其磁碟空間。即時資料表絕不會受到影響，自被取代以來寫入的資料列也不會受到影響。

若要在不變更政策的情況下一次性回收空間，請手動刪除資料表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 資料庫使用 `Atomic` 引擎，這會將普通的 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（預設為八分鐘）。`SYNC` 會立即移除資料，當您因磁碟已滿而刪除這些資料表時，這正是您想要的行為。


### 儲存空間 {#storage}

您還需要一種解決方案來儲存檔案（例如框架和函式庫的二進位檔）。Tuist 伺服器支援 S3 相容儲存空間和 Azure Blob Storage，用於儲存伺服器拥有的工件。

> [!TIP]
> **最佳化快取**
>
> 如果您的主要目標是降低快取延遲，您可能不需要自行託管整個伺服器。您可以在靠近 CI 或開發者網路的位置部署自行託管的 Kura 節點，並將它們連接到託管的 Tuist 伺服器或您的自行託管伺服器。
>
> 請參閱<.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link>。


### 自行託管的 Kura 節點 {#self-hosted-cache-nodes}

若要在自行託管的 Tuist 伺服器上使用自行託管的 Kura 節點：

1. 在 Tuist 伺服器上設定 `KURA_CONTROL_PLANE_CLIENT_ID` 和 `KURA_CONTROL_PLANE_CLIENT_SECRET`。用戶端 ID **必須是 UUID**。使用<.localized_link href="/guides/cache/self-host#control-plane-client">自行託管快取指南</.localized_link>中的命令產生 UUID 和隨機密鑰，並將它們儲存在您的部署密鑰中。
2. 依照<.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link>部署 Kura 節點，使用相同的控制平面憑證。
3. 使用 `KURA_REGISTRATION_URL` 和 `KURA_ADVERTISED_HTTP_URL` 設定每個 Kura 節點。註冊心跳會告訴伺服器哪些就緒且面向用戶端的 Kura 端點可以廣告給 CLI。

## 設定 {#configuration}

服務的設定在執行階段透過環境變數完成。鑑於這些變數的敏感性，我們建議將其加密並儲存在安全的密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變數，確保它們絕不會顯示在日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要的變數會在啟動時進行驗證。如果缺少任何變數，啟動將會失敗，且錯誤訊息將詳細說明缺少的變數。


### 授權設定 {#license-configuration}

作為內部部署使用者，您將收到一個授權，需要將其公開為環境變數。該授權用於驗證部署，並確保服務在協議條款範圍內運行。

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務等級協議後提供的授權。接受標準授權金鑰或用於隔離網路環境（伺服器無法聯絡外部服務）的 base64 編碼憑證。 | 是 | | `******` |

> [!WARNING]
> **到期日**
>
> 授權具有到期日。如果授權在 30 天內到期，使用者在使用與伺服器互動的 Tuist 命令時會收到警告。如果您有興趣續訂授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境設定 {#base-environment-configuration}

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從網際網路存取執行個體的基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密資訊的金鑰（例如 Cookie 中的工作階段） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於產生雜湊密碼的鹽值 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於產生隨機權杖的密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於 AES-GCM 加密敏感資料的 32 位元組金鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | 當為 `1` 時，它會設定應用程式使用 IPv6 位址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程式使用的日誌層級 | 否 | `info` | [日誌層級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 您的 GitHub 應用程式的 slug，取自 `https://github.com/apps/<slug>`。安裝應用程式時需要。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式的 base64 編碼私鑰，以解鎖額外功能，例如發布自動 PR 評論 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程式的私鑰，以解鎖額外功能，例如發布自動 PR 評論。**我們建議改用 base64 編碼版本，以避免特殊字元問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件位址以 `@<this-domain>` 結尾且已證明擁有該網域控制權的使用者，可以存取營運 URL（`/ops/*`）。若未設定，則無人可以存取。請參閱[營運](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 在儀表板導覽列中顯示為徽章的標籤，用於識別伺服器執行個體（例如版本號或分支名稱） | 否 | 開發環境中的 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用網頁伺服器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許在未登入的情況下提交建置與測試洞察。請參閱[網路信任存取](#network-trusted-access)以了解設定與安全性需求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許在未登入的情況下讀取與寫入快取。請參閱[網路信任存取](#network-trusted-access)以了解設定與安全性需求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 用於傳送追蹤資料的 OpenTelemetry Collector gRPC 端點 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 用於推送日誌的 Loki 相容端點基礎 URL（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **透過 HTTPS 提供應用程式**
>
> 工作階段 Cookie 標記為 `Secure`，因此瀏覽器會在純文字 `http://` 連線中捨棄它們，導致使用者無法登入。請在伺服器前方終止 TLS（使用內部 CA 簽發憑證的反向代理伺服器即可），並將 `TUIST_APP_URL` 設定為 `https://` URL，即使是內部或僅限 VPN 的部署亦然。

### 資料庫設定 {#database-configuration}

下列環境變數用於設定資料庫連線：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 存取 Postgres 資料庫的 URL。請注意，URL 應包含驗證資訊 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程式資料表使用的 PostgreSQL 結構描述。當您的資料庫政策不允許使用 `public` 結構描述時，請設定此變數。結構描述名稱必須是未加引號的 PostgreSQL 識別子。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用的選用 Postgres URL。當 `DATABASE_URL` 指向權限較窄的執行階段角色時，請將其設定為擁有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程式資料表權限的執行階段 Postgres 角色。當網頁伺服器不應以結構描述擁有者身分連線時，請搭配 `TUIST_MIGRATION_DATABASE_URL` 使用此變數。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 存取 ClickHouse 資料庫的 URL。請注意，URL 應包含驗證資訊 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 當為 true 時，它會使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫。除非啟用 `TUIST_DATABASE_SSL_VERIFY`，否則不會驗證伺服器憑證 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 當為 true 時，資料庫伺服器憑證必須鏈結至受信任的 CA，並符合 `DATABASE_URL` 主機。需要 `TUIST_USE_SSL_FOR_DATABASE`。我們建議啟用此選項 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 用於驗證資料庫伺服器的 CA 憑證 PEM 檔案路徑。若未設定，則使用作業系統的信任儲存區 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 連線池中保持開啟的連線數量 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出的所有連線是否耗時超過佇列間隔的時間（以毫秒為單位）[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 佇列中的閾值時間（以毫秒為單位），池使用此時間來決定是否應開始捨棄新連線[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新之間的時間間隔（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新前的最大 ClickHouse 緩衝區大小（以位元組為單位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要執行的 ClickHouse 緩衝區處理程序數量 | 否 | `5` | `5` |

預設情況下，Tuist 會加密資料庫連線，但不會驗證伺服器憑證，因此網路路徑上的攻擊者可以冒充資料庫。請設定 `TUIST_DATABASE_SSL_VERIFY=1` 以進行驗證。如果您的提供者使用自己的 CA 簽署憑證（如 Amazon RDS 和 Google Cloud SQL），請下載其 CA 捆綁包，將其掛載到容器中，並將 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向該檔案。`DATABASE_URL` 中的主機必須與憑證中的名稱或 IP 位址相符。啟用驗證後，未通過這些檢查的憑證會導致所有資料庫連線失敗，因此啟用後請檢查伺服器日誌中是否有 `Bad Certificate` 或 `Unknown CA`。

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，發布遷移會在執行 Ecto 遷移鏈之前建立結構描述（如果尚不存在）。如果遷移角色無法建立結構描述，請預先建立結構描述並使遷移角色成為其擁有者。

Tuist 透過設定工作階段 `search_path` 將連線指向自訂結構描述。某些池化或代理的 Postgres 設定（例如 PgBouncer，或限制啟動參數的受管資料庫）不會套用此設定，工作階段會回退到 `public`，這在遷移期間會顯示為 `permission denied for schema public`。透過此類設定連線時，請將結構描述固定在角色本身上，以便每個工作階段無論代理如何都從該結構描述開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 驗證環境設定 {#authentication-environment-configuration}

我們透過 [身分識別提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進驗證。若要使用此功能，請確保所選提供者的所有必要環境變數都存在於伺服器環境中。**缺少變數** 將導致 Tuist 略過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登入以及自助註冊是內建功能，預設已啟用。在需要要求身分識別提供者的實例上（例如強制使用 SSO 時），您可以完全關閉它們。這會從登入體驗中移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉每個對應的伺服器端端點，包括 CLI 使用的電子郵件/密碼端點 (`tuist auth`)。

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登入和註冊。設定為 `0` 以從登入頁面移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉對應的伺服器端端點 | 否 | `1` | `0` |

#### 停用已設定的身分識別提供者 {#disabling-a-configured-identity-provider}

預設情況下，只要設定了提供者，它就會顯示為登入選項。若要保留提供者的設定（其憑證保持設定狀態）同時將其從登入和註冊頁面中移除，請將對應的開關設定為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登入回呼，因此該方法將完全無法使用。

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入（有關應用程式為何與登入共用其憑證的原因，請參閱 [GitHub](#github) 章節） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登入 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 是否將已設定的 Okta 提供者顯示為登入選項 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登入 | 否 | `1` | `0` |

#### GitHub {#github}

我們建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行驗證，但您也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保在伺服器環境中包含 GitHub 指定的所有必要環境變數。缺少變數將導致 Tuist 略過 GitHub 驗證。若要正確設定 GitHub 應用程式：
- 在 GitHub 應用程式的一般設定中：
    - 複製 `Client ID` 並將其設定為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 建立並複製新的 `client secret`，然後將其設定為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設定為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以是伺服器的 IP 位址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀寫
  - 帳戶：
    - 電子郵件地址：唯讀

在 `Permissions and events` 的 `Account permissions` 區段中，將 `Email addresses` 權限設定為 `Read-only`。

接著，您需要在 Tuist 伺服器執行的環境中公開下列環境變數：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的用戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的用戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入。您為平台整合（PR 留言等）設定的 GitHub App 會與登入共用其用戶端憑證，因此它會顯示為登入選項。設定為 `0` 以保留應用程式，同時從登入頁面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設定 Google 驗證。為此，您需要建立一個類型為 OAuth 用戶端 ID 的新憑證。建立憑證時，選擇「Web 應用程式」作為應用程式類型，將其命名為 `Tuist`，並將重新導向 URI 設定為 `{base_url}/users/auth/google/callback`，其中 `base_url` 是您託管服務運行的 URL。建立應用程式後，複製用戶端 ID 和密鑰，並分別將它們設定為環境變數 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意畫面範圍**
>
> 您可能需要建立同意畫面。建立時，請務必新增 `userinfo.email` 和 `openid` 範圍，並將應用程式標記為內部。


#### Okta {#okta}

您可以透過 [OAuth 2.0](https://oauth.net/2/) 協定啟用 Okta 驗證。您必須按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些指示</.localized_link> 在 Okta 上 [建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設定 Okta 應用程式期間取得用戶端 ID 和密鑰後，您需要設定下列環境變數：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於向 Okta 進行驗證的用戶端 ID。此數字應為您的組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於向 Okta 進行驗證的用戶端密鑰 | 是 | | |

數字 `1` 需要替換為您的組織 ID。這通常為 1，但請在資料庫中確認。

### 儲存環境設定 {#storage-environment-configuration}

 Tuist 需要儲存空間來存放透過 API 上傳的構件。**必須設定其中一個支援的儲存解決方案**，Tuist 才能有效運作。

設定 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇伺服器構件後端：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 伺服器構件儲存後端。使用 `s3` 代表與 S3 相容的儲存，或使用 `azure_blob` 代表 Azure Blob Storage | 否 | `s3` | `azure_blob` |

#### 與 S3 相容的儲存 {#s3compliant-storages}

您可以使用任何與 S3 相容的儲存供應商來儲存構件。下列環境變數為驗證及設定與儲存供應商整合所需：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於向儲存供應商進行驗證的存取金鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於向儲存供應商進行驗證的秘密存取金鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 儲存貯體所在的地區 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 儲存供應商的端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 將用來儲存構件的貯體名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | PEM 編碼的 CA 憑證，用於驗證 S3 HTTPS 連線。適用於使用自簽憑證或內部憑證授權單位的隔離環境。 | 否 | 系統 CA 憑證束 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立與儲存供應商連線的逾時時間（毫秒） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從儲存供應商接收資料的逾時時間（毫秒） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 與儲存供應商連線池的逾時時間（毫秒）。使用 `infinity` 表示無逾時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連線的最大閒置時間（毫秒）。使用 `infinity` 可讓連線永久保持活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個連線池的最大連線數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用的連線池數量 | 否 | 系統排程器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連線至儲存供應商時使用的協定（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | 是否應將貯體名稱作為子網域（虛擬主機）來建構 URL | 否 | `false` | `1` |

> [!NOTE]
> **來自環境變數的 AWS Web Identity 驗證**
>
> 如果您的儲存供應商是 AWS，且您希望使用 Web Identity Token 進行驗證，您可以將環境變數 `TUIST_S3_AUTHENTICATION_METHOD` 設定為 `aws_web_identity_token_from_env_vars`，Tuist 將會使用傳統的 AWS 環境變數來採用此方法。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請參閱 [這些文件](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 以取得 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設定為 `https://storage.googleapis.com`。其他環境變數與任何其他與 S3 相容的儲存相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，請設定 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並設定 Azure 儲存帳戶憑證：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 儲存帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 的儲存帳戶存取金鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 儲存伺服器構件的容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略則使用 `https://<account>.blob.core.windows.net` | 否 | 從帳戶名稱衍生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 的 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm Chart 時，請設定 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。Chart 的頂層 `objectStorage` 設定仍與 S3 相容，因為選用的快取和 Registry Mirror 工作負載仍預期使用與 S3 相容的儲存。如果停用這些工作負載且伺服器使用 Azure Blob，請設定 `objectStorage.mode=external` 並將外部物件儲存端點和憑證留空，以避免部署內嵌的 MinIO 服務。

#### 構件保留 {#artifact-retention}

在自託管執行個體上，構件清理預設為停用。每種支援的構件類型都有專屬的環境變數。將變數設定為正整數的天數，即可啟用該構件類型的清理。讓變數保持未設定或空白，只會停用該構件類型的清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm Chart 時，請以映射形式設定相同的保留期間：

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

所有六個鍵皆為選用。此範例會啟用每種支援的構件類型，並各自擁有獨立的保留期間。省略某個鍵或將其值留空，即可保持該構件類型的清理為停用狀態。自託管的保留期間沒有 30 天的上限。若設定的值不是正整數，伺服器將在啟動時失敗。

變更保留變數後，請重新啟動伺服器。每個排入佇列的自託管清理批次在刪除檔案前都會檢查目前的設定，因此取消設定或清空變數，或是延長其保留期間，也能在重新啟動後保護檔案免受待處理作業影響。

| 環境變數 | 從物件儲存中移除的構件檔案 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 快取、舊版內容定址儲存快取、模組快取，以及 Gradle 快取檔案 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App Preview 建置與圖示 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 目前與舊版的建置封存 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 儲存在已過期執行之構件前綴下的所有物件，包括結果套件、叫用記錄，以及工作階段封存 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片套件 |

排程清理僅移除構件 Blob。它會保留對應的 PostgreSQL 和 ClickHouse 資料列，因此在下載過期後，建置、測試、執行、預覽和分片中繼資料仍可在儀表板中可見。此設定不會變更 ClickHouse 資料表的保留規則。

### 電子郵件設定 {#email-configuration}

Tuist 需要電子郵件功能來進行使用者驗證和交易通知（例如密碼重設、帳戶通知）。目前，**僅支援 Mailgun** 作為電子郵件供應商。

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於向 Mailgun 驗證的 API 金鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件的網域 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將出現在「寄件者」欄位中的電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 供使用者回覆的選用回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新使用者註冊的電子郵件確認。啟用時，使用者會自動獲得確認，並可在註冊後立即登入 | 否 | 若未設定電子郵件則為 `true`，若已設定電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅在您想要發送電子郵件時才需要電子郵件設定變數。若未設定，系統會自動跳過電子郵件確認

> [!NOTE]
> **SMTP 支援**
>
> 目前不提供通用 SMTP 支援。如果您需要在內部部署中使用 SMTP 支援，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 以討論您的需求。


> [!NOTE]
> **隔離網路部署**
>
> 對於沒有網際網路存取權限或未設定電子郵件供應商的內部部署安裝，預設會自動跳過電子郵件確認。使用者可在註冊後立即登入。如果您已設定電子郵件但仍想跳過確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。若要在已設定電子郵件的情況下要求電子郵件確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額與密碼重設連結**
>
> 設定電子郵件後，邀請電子郵件（建立、大量或重新發送）限制為每位收件人每五分鐘一封，且每個組織和每位邀請者每小時可突發發送 50 封並以每小時 50 封的速度補充。取消邀請不會恢復配額，且當配額用盡時，邀請 API 會回應 `429` 和 `Retry-After`。若有多个複本，請設定共用的 Valkey 以實現整個部署範圍的配額；若已設定但無法使用，則會拒絕發送邀請電子郵件。密碼重設連結會在 15 分鐘後過期。


### Git 平台設定 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台整合</.localized_link>，提供額外功能，例如自動在您的拉取請求中發布評論。

#### GitHub {#platform-github}

自行託管的 Tuist 伺服器無法安裝在 `https://tuist.dev` 上執行的 GitHub App。GitHub App 會綁定至註冊它們的伺服器，因此您的部署需要在 github.com 上擁有自己的 App。

##### 註冊 App {#platform-github-registering-the-app}

[建立一個由您的 GitHub 組織擁有的 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。您可以重複使用為驗證所建立的 App，除非您建立的是 OAuth App。請使用以下設定進行配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 的值：

| 設定 | 值 |
| --- | --- |
| 回呼網址 | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設定網址 | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重新導向 | 已啟用 |
| Webhook 網址 | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任意隨機字串。您將把它設定為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予下列儲存庫權限：

| 權限 | 存取權 |
| --- | --- |
| 內容 | 唯讀 |
| 中繼資料 | 唯讀 |
| 議題 | 讀寫 |
| 拉取請求 | 讀寫 |
| 檢查 | 讀寫 |

同時授予 **成員：唯讀** 組織權限。在 github.com 設定期間，Tuist 會檢查連接組織安裝的人員是否為有效的 GitHub 組織擁有者，而不僅僅是擁有其某個儲存庫存取權的人員。

讓 App 訂閱 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **安裝期間要求使用者授權 (OAuth)** 為停用狀態，以便 GitHub 將安裝程式發送至設定網址。Tuist 會使用額外的 `/integrations/github/authorize` 回呼啟動獨立的授權步驟，以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝程式隨後會選擇一個 Tuist 組織；在 Tuist 中啟動的安裝會保留其組織。

##### 設定伺服器 {#platform-github-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公開頁面網址的最後路徑元件 `https://github.com/apps/<slug>` | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字格式的 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式的 Base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，因為後者對平台處理換行符的方式較為敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上設定的 Webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **設定所有必要的 App 憑證**
>
> 組織整合頁面上的 **安裝 GitHub App** 按鈕會保持停用狀態，直到設定了 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 以及私鑰為止。數字格式的 `TUIST_GITHUB_APP_ID` 也用於驗證安裝所有權。安裝網址內嵌了 App slug，因此若缺少 `TUIST_GITHUB_APP_NAME`，特別是會導致 GitHub 回應 404 錯誤的連結。

伺服器重新啟動後，組織管理員可依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 安裝 App 並將儲存庫連接至專案。

##### OIDC 驗證依賴此設定 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 會根據連接到您專案的儲存庫來解析 CI 令牌中的儲存庫聲明，且只能透過已安裝的 GitHub App 建立連接。請在完成上述設定後，再讓您的 CI 工作流程使用 OIDC 進行驗證。

您的 Tuist 伺服器也需要出站存取權以連接到 CI 提供者的 OIDC 發行者，以便取得其簽章金鑰：

| CI 提供者 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變數僅配置 Tuist 的 github.com App。若要將 Tuist 與 GitHub Enterprise Server (GHES) 執行個體整合，組織管理員需切換至整合頁面上的 **企業伺服器** 分頁並輸入 GHES 基礎網址 — Tuist 會引導他們透過 GitHub 的 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 執行個體上註冊全新的 Tuist App。新 App 的憑證會以加密方式按安裝儲存；無需額外的 `TUIST_GITHUB_APP_*` 環境變數。

#### Origin {#platform-origin}

自行託管的 Tuist 伺服器需要自己的 Origin app，並使用您部署的網址和簽章金鑰進行配置。請為每個 Tuist 環境註冊獨立的 app，以確保安裝和憑證保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽章金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設定](https://cursor.com/codebase/settings/apps) 中建立一個 app。將 `origin-app-public.pem` 的內容註冊為其公開簽章金鑰。請保密 `origin-app-private.pem`；您需要將其提供給 Tuist 伺服器，而非上傳至 Cursor。
3. 設定下列設定，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎網址：

   | 設定 | 值 |
   | --- | --- |
   | 首頁網址 | `YOUR_APP_URL` |
   | 重新導向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook 網址 | `YOUR_APP_URL/webhooks/origin` |

4. 複製已註冊的 App ID，其開頭為 `app_`。

Tuist 在安裝期間會請求下列權限：

| 範圍 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 尋找拉取請求及其目前的 head commit。 |
| `repository:pull_requests:reviews:write` | 讀取、發布及更新報告評論。Origin 包含相應的審查讀取權限。 |
| `repository:metadata:read` | 探索儲存庫並讀取其預設分支。由 Origin 自動授予。 |

不要勾選可選的儲存庫 webhook 事件。安裝生命週期通知已足夠；不需要原始碼存取、合併權限和檢查執行權限。

##### 設定伺服器 {#platform-origin-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設定複製的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符號。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私密金鑰儲存在您部署的秘密管理器中。保留其多行 PEM 格式；此設定不接受 base64 編碼的替代方案。切勿將金鑰提交至原始碼控制或在日誌中公開。這兩個變數必須屬於同一個已註冊的 app。

您的 Tuist 伺服器需要對 `api.cursor.com` 的出站 HTTPS 存取權。Cursor 必須能夠將請求傳送至 webhook 網址，且管理員必須能夠在瀏覽器中返回重新導向 URI。兩個已註冊的網址都必須與您部署的 HTTPS 基礎網址相符。

##### 安裝 App {#platform-origin-installing-the-app}

伺服器重新啟動後，管理員開啟 **設定 → 整合**，選擇 Origin 下方的 **連接**，並核准 app 對適當的 Origin 帳戶和儲存庫的存取權限。整個流程都會保留 Tuist 組織。直接從 Origin 發起的安裝則會提示管理員登入並選擇要連接的 Tuist 組織。接著他們選擇 **新增專案連接** 以將 Tuist 專案連結至原生儲存庫。

請參閱 <.localized_link href="/guides/integrations/gitforge/origin">Origin 整合指南</.localized_link> 了解專案連接和結果上傳需求。安裝 app 不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

#### Entire {#platform-entire}

自行託管的 Tuist 伺服器需要自己的 Entire 外掛程式，並使用您部署的網址和簽章金鑰進行配置。Entire 外掛程式需要合作夥伴註冊，因此請在開始前聯繫 Entire。請為每個 Tuist 環境註冊獨立的外掛程式，或至少獨立的簽章金鑰，以確保安裝和憑證保持獨立。

##### 註冊外掛程式 {#platform-entire-registering-the-plugin}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽章金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. 依照 Entire 的 [外掛程式註冊指南](https://docs.entire.com/guides/api/plugins/register) 註冊外掛程式。分享 `entire-plugin-public.pem` 的內容，或發布該內容的 JWKS 網址，作為外掛程式的簽章金鑰。請保密 `entire-plugin-private.pem`；您需要將其提供給 Tuist 伺服器，而非 Entire。
3. 設定下列網址，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎網址：

   | 設定 | 值 |
   | --- | --- |
   | 安裝後網址 | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook 網址 | `YOUR_APP_URL/webhooks/entire` |

4. 記下 Entire 確認的外掛程式 slug 及其提供的 webhook 簽章金鑰網址。

請求下列權限：

| 權限 | 用途 |
| --- | --- |
| `contents:read` | 接收 Trail 事件，並尋找具有 head commits 的開啟中和草稿 Trails。 |
| `checks:write` | 發布 Tuist 閘道。 |
| `findings:write` | 發布並解決失敗和不穩定測試的發現項目。 |
| `discussions:write` | 發布並更新摘要評論。未授予此權限的安裝仍會收到閘道和發現項目。 |

不需要儲存庫寫入存取權。如果您為現有註冊新增權限，請要求 Entire 更新它，並確認安裝會授予新權限。請參閱 Entire 的 [Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings) 和 [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) 合約。

##### 設定伺服器 {#platform-entire-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entire 確認的外掛程式 slug。 | 是 | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` 的完整內容，包含 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Entire 在註冊時提供的 webhook 簽章金鑰網址。 | 是 | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 透過 JWKS 註冊簽章金鑰時的金鑰 ID。 | 否 | | |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core 網址。 | 否 | `https://eu.auth.entire.io` | |

將私鑰儲存在您部署的機密管理器中，並保留其多行 PEM 格式。切勿將金鑰提交至原始碼控制或在記錄檔中公開。使用 Tuist Helm chart 時，您可以改為將 PEM 儲存在 1Password 保險庫中作為 `ENTIRE_PLUGIN/private_key`，並與 `server.config.managedSecrets` 一起啟用 `server.config.entirePluginKey.enabled`；項目和欄位名稱可透過 `server.config.entirePluginKey.item` 和 `.field` 進行配置。此對應不會設定 slug 或 webhook 簽章金鑰網址。

您的 Tuist 伺服器需要對 Entire Core 以及服務您儲存庫的區域性 Entire API 主機具有出站 HTTPS 存取權，這些主機皆位於 `entire.io` 或 `entire.com` 之下。Tuist 會驗證安裝收據和 webhook 簽章，核發短效且限於儲存庫範圍的權杖，且絕不會將權杖嵌入報告連結中。

##### 啟用整合 {#platform-entire-enabling-the-integration}

在推出應用程式之前套用伺服器遷移，然後全域啟用 `entire_trails` 功能旗標，以向所有帳戶或選定帳戶提供此整合。啟用旗標不會改變誰可以在 Entire 中安裝外掛程式；若要在擁有該外掛程式的 Entire 專案之外提供它，請聯絡您的 Entire 聯絡人並請求允許。此整合獨立於 Tuist 的 CI 執行配置。

如果您復原應用程式，請保留 `entire_trail_reports` 資料表，以便後續升級可以恢復進行中的發布。

管理員隨後依照 <.localized_link href="/guides/integrations/gitforge/entire">Entire 整合指南</.localized_link> 安裝外掛程式並將儲存庫連接至專案。安裝外掛程式不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

## 本機測試 {#testing-locally}

我們提供完整的 Docker Compose 配置，其中包含在部署至基礎設施之前，於本機電腦上測試 Tuist 伺服器所需的所有相依元件：

- PostgreSQL 15
- ClickHouse 26.5（用於分析）
- ClickHouse Keeper（用於協調）
- MinIO（用於相容 S3 的儲存）
- Kura（用於本機自行託管快取測試）
- pgweb（用於資料庫管理）

> [!CAUTION]
> **需要授權**
>
> 執行 Tuist 伺服器（包括本機開發實體）在法律上需要有效的 `TUIST_LICENSE` 環境變數。如果您需要授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速入門：**

1. 下載配置檔案：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 設定環境變數：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   內建的 ClickHouse 服務接受下列選擇性的操作記錄控制：

   | 環境變數 | 說明 | 預設值 | 範例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 記錄資料表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留期限（天） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 伺服器記錄器和 `system.text_log` 層級 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 取代系統記錄資料表時，如何處理其留下的 `<name>_N` 資料表。`ignore` 會保留它們，`delete` 會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 和相依映像的 `linux/arm64` 變體。若要強制使用 amd64 模擬進行除錯，請以 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 執行 Compose。

   內建的 compose 檔案使用具名 Docker 卷冊來儲存持久化資料。若您將其替換為主機綁定掛載，請先建立主機目錄，並確保容器使用者可以寫入這些目錄，特別是 ClickHouse 和 ClickHouse Keeper 的資料目錄。

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

檢視記錄：
```bash
docker compose logs -f tuist
```

停止服務：
```bash
docker compose down
```

重置一切（刪除所有資料）：
```bash
docker compose down -v
```

**配置檔案：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變數範例檔案

## 使用 Helm 部署至 Kubernetes {#kubernetes-with-helm}

Tuist 提供用於在 Kubernetes 上部署的官方 Helm Chart。該 Chart 封裝了 Tuist 伺服器和快取服務，以及可視需要替換為外部供應商的內建基礎設施相依元件。

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

`server.license.key` 值同時接受標準授權金鑰，以及針對隔離環境安裝的 Base64 編碼授權憑證；伺服器會自動偵測是哪一種。

使用 `--set` 傳遞授權適合快速安裝。若將您的值存放在版本控制中，請將授權儲存在 Helm 之外管理的 Kubernetes Secret 中（例如使用 Vault、Sealed Secrets 或 SOPS），並將 Chart 指向該 Secret：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下方的項目指定您的 Secret 中持有授權值的欄位名稱，該值可以是授權金鑰，或是針對隔離環境安裝的 Base64 編碼授權憑證。`existingSecretKeys` 下方的每個項目預設為 Chart 自身的金鑰名稱，因此請將您的 Secret 不包含的項目設為空字串，如上方的 `certificateBase64` 所示。否則，Pod 會參考不存在的金鑰而無法啟動。請在安裝或升級 Chart 之前，在發布命名空間中建立該 Secret。

僅透過一個來源配置授權：`server.license.key` 或 `server.license.existingSecret`。若未設定任何來源或混合使用多個來源，Chart 將無法渲染。透過 `server.extraEnv` 傳遞的授權不算作來源，因此請改用 `existingSecret`。

### 基礎設施相依元件 {#helm-infrastructure-dependencies}

Chart 管理三個基礎設施相依元件：`postgresql`、`clickhouse` 和 `objectStorage`。每個元件預設為 **內建** 模式，表示 Chart 會在叢集內部部署它們。若要改為指向您自己的外部實體，請將相依元件的 `mode` 設為 `external`，並在您的 `values.yaml` 中填寫連線詳細資訊。例如，若要使用外部 PostgreSQL 資料庫：

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

Chart 會從 Secret 讀取主機、使用者名稱和密碼，並透過 Kubernetes 環境變數替換組成 `DATABASE_URL`，因此密碼不會呈現在 Helm manifest 中。Secret 中的密碼值應符合 URL 安全規範，因為它會被插值到資料庫 URL 中。

相同模式也適用於 `clickhouse` 和 `objectStorage`。請參閱 Chart 的 `values.yaml` 中各章節下的 `external` 區塊，以取得完整的可配置欄位清單。

### 共用排程與標籤 {#helm-shared-scheduling-and-labels}

Chart 在 `global` 下公開一組共用的 Pod 設定，讓營運人員可以調整部署以適應其叢集，而無需為每個工作負載重複相同的值：

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

在以下情況使用這些設定：

- 為每個 Pod 新增叢集專屬標籤
- 從私人註冊表拉取鏡像
- 指定專屬節點池
- 允許 Pod 排程至保留給 Tuist 工作負載的 tainted 節點

### 工作負載身分與服務帳戶 {#helm-workload-identity}

Chart 會針對每個應用程式工作負載限定服務帳戶範圍，讓您僅在需要的地方授予身分：

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

Chart 將儲存與服務網格特定的調整設為選擇性啟用，以保持預設值的可攜性：

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

僅在您的叢集需要時使用這些覆寫：

- `cache.podSecurityContext` 預設為空。若您的儲存類別或 CSI 驅動程式需要在掛載的磁碟區上共用群組擁有權，請設定 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 標準的 `9000` 原生服務連接埠，當服務網格或平台保留與該連接埠衝突時可以變更。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，讓 ClickHouse 對內建內部日誌表（如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 和 `system.part_log`）保持無限制的保留。設定此值會取代這些表一次，因此請搭配 `supersededTables: delete` 使用 — 請參閱 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制營運日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 針對內建 ClickHouse 伺服器記錄器和 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不屬於任何表定義的一部分，因此變更它永遠不會取代表。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore`，並決定 ClickHouse 在取代系統日誌表時留下的 `<name>_N` 表的處理方式。將其設為 `delete` 可在每次 `helm upgrade` 時刪除它們。
- 對 `ttlDays` 和 `level` 的編輯會在 ClickHouse Pod 下次重新啟動時生效，因為兩者都是 `subPath` 掛載，且 Chart 在其 ConfigMap 變更時不會滾動更新 StatefulSet。

### 可觀測性 {#helm-observability}

Chart 包含一個可選的可觀測性堆疊（OpenTelemetry Collector、Prometheus、Grafana、Loki 和 Tempo）。它預設為 **停用**。若要在您的 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 即可使用，並已預先配置日誌、追蹤和指標的下鑽功能。對於外部可觀測性，請保持此項停用，並透過 `server.extraEnv` 配置端點：

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### 數值參考 {#helm-values-reference}

如需完整的可配置數值清單，請參閱 Chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 映像位於：
```
ghcr.io/tuist/tuist
```

發布的映像包含用於 `.xcactivitylog` 封存檔的內建 Linux 建置處理功能，因此自託管部署可以在不執行任何額外服務的情況下處理建置 — `ProcessBuildWorker` Oban 作業會在每個伺服器 Pod 中以進程內方式執行。若您想將建置處理卸載到專屬的副本集（例如，獨立於 Web 層擴展解析吞吐量），請在 Helm Chart 中設定 `processor.enabled: true`：Chart 會將相同映像部署為僅消費佇列的角色（`TUIST_PROCESSOR_MODE=true`）。請參閱 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) 以取得完整的控制項清單。

> [!NOTE]
> `.xcresult` 解析依賴 Xcode 中的 `xcresulttool`，因此只能在 macOS 上執行。CLI 會為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 伺服器預設為 **本機** 處理模式，在開發者機器上解析 xcresult（該機器已具備用於建置本身的 Xcode）並上傳結構化結果。測試結果無需任何額外基礎設施即可擷取。

### 拉取 Docker 映像 {#pulling-the-docker-image}

您可以執行以下命令來取得映像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

該映像同時發布了 `linux/amd64` 和 `linux/arm64` 架構，因此 Docker 會自動為主機選擇原生的 Linux 架構。

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像 {#deploying-the-docker-image}

Docker 映像的部署流程會因您選擇的雲端供應商和您組織的持續部署方法而異。由於大多數雲端解決方案和工具（如 [Kubernetes](https://kubernetes.io/)）都使用 Docker 映像作為基本單位，因此本節中的範例應能與您現有的設定良好配合。

> [!WARNING]
> 若您的部署管道需要驗證伺服器是否已啟動並運行，您可以向 `/ready` 發送 `GET` HTTP 請求，並斷言回應中的狀態碼為 `200`。


#### Fly {#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，您需要一個 `fly.toml` 設定檔。建議在您的持續部署 (CD) 管道中動態產生它。以下是供您參考的範例：

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

接著您可以執行 `fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署中，您不需要執行 `fly launch --local-only`，而是需要執行 `fly deploy --local-only`。Fly.io 不允許拉取私人 Docker 映像，這就是為什麼我們需要使用 `--local-only` 旗標。


## Prometheus 指標 {#prometheus-metrics}

Tuist 在 `/metrics` 公開 Prometheus 指標，協助您監控自託管實例。這些指標包括：

### Finch HTTP 用戶端指標 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 用戶端，並公開有關 HTTP 請求的詳細指標：

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
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在使用前閒置的時間（直方圖）
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
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連線在傳送前閒置的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標都提供 `_bucket`、`_sum` 和 `_count` 變體，以便進行詳細分析。

### 其他指標

除了 Finch 指標外，Tuist 還公開以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳號、專案等）
- 資料庫效能（使用 Tuist 託管基礎設施時）

## 營運作業 {#operations}

Tuist 在 `/ops/` 下提供一組公用程式，可用於管理您的實例。

> [!WARNING]
> **授權**
>
> 只有電子郵件網域符合 `TUIST_OPERATOR_EMAIL_DOMAIN` 的使用者才能存取 `/ops/` 端點。若未設定該變數，則無人可以存取。請將其設定為您控制信箱的網域。
>
> 使用者也必須證明其地址的控制權：方法是點選確認或重設密碼的電子郵件、使用 Google、GitHub 或 Apple 登入，或是輸入一次性代碼或出示代理程式登入時已驗證的電子郵件。在沒有郵件供應者的情況下，系統會自動確認帳號，但這些帳號在完成上述證明前並不具備資格。建立帳號後，僅當地址位於 `TUIST_OPERATOR_EMAIL_DOMAIN` 中時才會記錄證明；因此，在您設定或變更該變數後，尚未在其下證明地址的管理員必須再次進行證明。透過其中一個供應者登入或透過代理程式登入所建立的帳號，從建立時起即攜帶該證明。若沒有郵件供應者，以密碼註冊的帳號無法連結這些供應者，因此請透過 Google、GitHub 或 Apple 登入來建立管理員帳號，或設定郵件供應者。
>
> 在此檢查機制存在之前建立的帳號尚未記錄該證明，因此現有的管理員在重設密碼或使用其中一個供應者登入一次後，即可重新取得存取權限。
>
> 當管理員網域中未具備該證明的帳號首次以該方式證明其地址時，Tuist 會移除其密碼、通行金鑰以及與組織單一登入供應者的連結，並將其從瀏覽器與 CLI 登出，因為註冊該地址的人可能並非其擁有者。對此類帳號執行重設密碼也會產生相同效果，差別在於會設定新密碼。帳號上設定的驗證器應用程式會保留；若非擁有者所有，請為其移除。管理員網域外已確認的帳號會保留其憑證。擁有者可繼續透過供應者登入，或透過重設程序設定新密碼。
>
> 由 SCIM 佈建建立或重新命名的帳號，在擁有者提供證明前不具備任何證明。


- **錯誤 (`/ops/errors`)：** 您可以檢視應用程式中發生的非預期錯誤。這對於除錯及了解問題原因相當有用，若您遇到問題，我們可能會要求您與我們分享此資訊。
- **儀表板 (`/ops/dashboard`)：** 您可以檢視提供應用程式效能與健康狀態洞察的儀表板（例如記憶體用量、執行中的處理序、請求數量）。此儀表板有助於了解您使用的硬體是否足以處理負載。
