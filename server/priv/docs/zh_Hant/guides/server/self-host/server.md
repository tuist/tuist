---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解如何在你的基礎設施上部署 Tuist server。"
}
---
# 伺服器 {#server}

我們提供 Tuist 伺服器的自託管版本，適合需要對基礎設施擁有更多控制權的組織。此版本允許你在自己的基礎設施上託管 Tuist，確保你的資料保持安全與私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要具有法律效力的付費授權。Tuist 的本地部署版本僅提供給採用 Enterprise 方案的組織。如果你對此版本有興趣，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊有的自託管快取節點技術已不建議用於新安裝。請參閱<.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link>以了解目前的自託管快取基礎設施。
>
> 現有的部署仍可參考 GitHub Markdown 檢視器中的舊版原始文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)與[快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔頻道發布：**canary**（每次提交至 `main`）、**release candidate**（每週一釋出，觀察一週）與**stable**（隔週一升級）。只有穩定版會推進 `:latest` 並預設解析；canary 與 release candidate 屬於 GitHub 預釋出版本，需固定其標籤才能選用。伺服器與 Kura 每週同步發布，與<.localized_link href="/cli/release/channels">Tuist CLI 的發布時程</.localized_link>保持一致。

我們遵循[語意化版本規範](https://semver.org/)，以確保版本可預測且相容。主要版本號用於標示 Tuist 伺服器中需要與自託管使用者協調的重大變更；我們預期不會頻繁使用此機制，若確有需要，我們會協助你順利過渡。

請參閱<.localized_link href="/guides/server/self-host/release/channels">發布頻道</.localized_link>頁面，了解各頻道的釋出方式、如何在部署中固定特定版本，以及建議策略：讓生產環境停留在變動較少的穩定線，同時讓預備環境觀察即將推出的版本。

## 瀏覽器工作階段升級 {#browser-session-upgrade}

若七天內沒有經過驗證的頁面請求或 LiveView 互動，瀏覽器工作階段將會過期，且最遲不會超過驗證後的 30 天。「記住我」會恢復相同的伺服器端工作階段，但無法延長上述任一期限。活動每分鐘記錄一次檢查點，因此閒置的工作階段可能提前最多 59 秒過期。WebSocket 心跳、自動重新連線與背景更新不會 renew 活動狀態。這些期限不會影響機器憑證或 API 權杖的有效期。

在啟動升級後的應用程式程序之前，先執行累加式的 `users_tokens` 遷移。現有資料列不會回填：其建立時間會限制閒置與絕對過期時間，且在存取強制 SSO 的組織之前必須重新驗證。回呼的提供者、簽發者或已驗證的 Workspace，以及自訂 SSO 連線會儲存在伺服器端，並與組織的目前設定進行比對。已連結的帳號不等於工作階段驗證證明。

在將政策視為強制生效之前，請升級所有提供服務的網頁複本。舊版二進位檔仍可能接受原先的 60 天工作階段，且不會強制新的 LiveView 邊界；混合版本在結構描述上相容，但在政策層面並不等同。預期使用者需要再次登入。回滾到舊版二進位檔會削弱這些控制；若需要結構描述回滾，請在移除新欄位之前停止所有讀取該欄位的二進位檔。切勿延長舊工作階段或推斷來源以避免重新驗證。

## 驗證器應用程式 MFA {#authenticator-app-mfa}

伺服器內建原生驗證器應用程式（TOTP）雙因素驗證。儀表板尚未提供入口；後續版本將加入設定進入點。它不需要啟用旗標、託管服務相依性或身分提供者憑證：只需要 PostgreSQL、下方的遷移、TOTP 驗證器，以及所有服務複本共用的穩定加密金鑰（`TUIST_SECRET_KEY_ENCRYPTION`，若未設定則退回使用 `TUIST_SECRET_KEY_BASE`）。請保持伺服器與驗證器的時鐘同步。MFA 驗證及其每五分鐘五次失敗碼的共用配額使用 PostgreSQL 資料列鎖定，而非 Redis。

設定需要在最近五分鐘內登入，將設定金鑰輸入 TOTP 驗證器應用程式，並確認應用程式產生的代碼。系統會一次性顯示十個單次使用的復原碼；請安全儲存。停用該因素也需要近期登入，以及未使用的驗證器或復原碼。變更因素會撤銷其他瀏覽器工作階段。重設密碼不會移除 MFA，且此實作不提供僅限電子郵件或管理員繞過遺失因素的機制。

一旦註冊，每次新的瀏覽器登入（包含聯合登入）在取得工作階段或完成基於瀏覽器的 CLI/裝置授權之前，都需要通過原生第二因素。直接使用密碼與 Apple API 登入會拒絕已註冊的使用者，並指示他們使用瀏覽器登入。已註冊使用者的新電子郵件代理聲明需要經過 MFA 驗證的瀏覽器工作階段；僅限信箱的舊式聲明會被拒絕。現有的 API 權杖、機器憑證、工作負載身分及其更新規則維持不變。這是針對個別使用者的選擇性支援，並非組織範圍的 MFA 強制要求，也不代表驗證身分提供者自身的 MFA 政策。組織 SSO 除了原生因素外，仍需正確設定的提供者/簽發者。

註冊、登入、使用復原碼或停用 MFA 都不需要提供電子郵件。因素變更通知採尽力而為；傳遞失敗不會撤銷已完成的變更。

在部署新二進位檔之前，先執行獨立的附加遷移 `user_mfa`/`users_tokens.mfa_verified_at`。TOTP 金鑰使用現有的 Vault 加密金鑰；請保留該金鑰及其備份。在允許 MFA 註冊之前，請完成**所有提供驗證服務的複本的升級**。舊版二進位檔可以繞過原生 MFA，因此在註冊後，它們不是符合政策要求的回滾目標。刪除 MFA 結構描述會銷毀註冊和復原狀態；請先停止讀取器並保留加密備份。混合版本結構描述的相容性並不表示已強制執行 MFA 或瀏覽器工作階段控制。

## OAuth 升級與回滾邊界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 實體快取需要對現有安裝進行分階段升級。在部署停止 OAuth 快取失效的版本之前，請先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 的權威讀取相容版本部署到**每個 OAuth 讀取器和寫入器**。此相容階段首次出現在 **1.355** 發行系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升為穩定版，生產環境部署應使用穩定的 `1.355.x` 版本。安裝在 1.354 或更早版本的系統必須在完成此階段後，才能升級到包含移除功能的後續版本。保持 1.355 系列僅用於相容性：不要將失效移除功能回溯移植到其中。

原始相容性提交也可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 取得。另一個映像檔僅在保留權威讀取**並保留舊式失效**且舊版使用者仍在使用時，才適合作為相容階段。在提供服務流量之前，請執行該階段的常規資料庫遷移，包括重新整理權杖查詢索引。

檢查每個環境中的所有 Web 複本、背景工作器、排程工作以及單獨固定的處理器映像檔。等待相容性推出完成，並在移除失效之前驗證沒有剩餘的快取讀取二進位檔。不要在自動升級期間讓浮動映像標籤跳過此階段。沒有舊版使用者的全新安裝不需要中間部署。

> [!WARNING]
> **保留權威讀取的回滾目標**
>
> 移除失效後，常規的滾動回滾必須針對 #14040 或其他權威讀取版本。即使所有無失效程序都已停止，保留的 OAuth 快取項目可能已過時，且重新啟動的快取讀取複本可能會從對等節點匯入它們。
>
> 進一步回滾需要停止並排空**所有**無失效 OAuth 使用者，然後在啟動任何快取讀取使用者之前清除或替換**每個**保留的 Boruta 快取參與者。防止保留的參與者重新加入。僅排空入口或僅重新啟動 Web 複本是不夠的；請與您的 Tuist 支援聯絡人協調此恢復過程，而不是自動清除快取或回滾資料庫遷移。

## 多複本叢集 {#multi-replica-clustering}

支援的多複本 Web 部署需要 Erlang 叢集來進行跨複本 Phoenix PubSub 和 Oban PG 通知，而非作為驗證授權機構。當 `server.cluster.enabled` 為 false 時，Chart 會拒絕多個複本，包括可以擴展到超過一個複本的自動縮放器。先前接受的未叢集部署必須規劃此升級，而不是繞過防護。在變更成員資格之前，請完成<.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括移除失效。

使用您的密鑰管理器在 release 命名空間中建立私有的 Cookie Secret，然後設定其名稱和金鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵值，並由所有參與的 Web 複本共用。切勿使用嵌入在已發布映像檔中的 Cookie：擁有分發 Cookie 即授予在其節點上遠端執行的權限。分散式發布啟動現在會拒絕缺少的私有 `RELEASE_COOKIE` 或無效的連接埠，包括明確設定的 `RELEASE_DISTRIBUTION=name` 或 `sname` 而沒有 DNS 發現。非 Chart 部署也必須一致地設定 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 以及 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

使用常規伺服器連接的 `helm upgrade` 時，將 `cookieExistingSecret` 留空會建立 Cookie Secret，並在後續升級中重用其當前值。離線 `helm template`、Argo CD 和其他沒有即時 Secret 查詢的 GitOps 渲染器無法保留該生成的值；它們必須使用由單獨管理的穩定 Secret 支援的 `cookieExistingSecret`。不要更改 Cookie 金鑰以隱式輪換活躍叢集。Cookie 輪換需要協調每個參與者的遷移/重新啟動；僅更新 Secret 不會更新現有程序。

從映像檔內建 Cookie 進行的第一次推出會形成單獨的新舊成員島嶼，直到所有 Web 複本都使用私有 Secret。為即時更新規劃遷移視窗。後續的滾動部署會形成混合版本叢集，因此請根據實際的新舊版本限定 PubSub、Oban 通知和對等節點替換。這些通知不是持久的交付保證。在回滾相容版本時，請保留權威讀取的回滾映像檔並保持相同的私有 Cookie。

僅允許受信任的伺服器對等節點之間使用 EPMD（TCP 4369）和設定的分發連接埠，絕不允許來自租戶工作負載或公共網路的連線。驗證您環境中的實際入口/出口隔離；渲染 NetworkPolicy 並不能證明強制執行或後端可達性。在連續負載下的雙複本金絲雀部署必須通過加入、滾動替換和故障/恢復測試後才能提升。DNS 用於發現對等節點，而不是在短暫失敗或部分回應時斷開健康節點的連線；實際節點丟失和 OTP 分割預防仍然適用。libcluster 可能仍會為保留回調記錄成功的「斷開」操作而不關閉連線；請從節點上線/下線事件或 `Node.list()` 確定實際成員資格，而不僅依賴該日誌行。

## 持續部署 {#continuous-deployment}

我們建議將生產環境固定在穩定的次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），以便日常升級僅交付向後移植的修復程式。穩定版本線在候選發布通道上經過一週的浸泡測試後，於每週一 UTC 06:00 提升；在金絲雀或當前候選發布標籤上的暫存環境會在問題影響您的使用者之前捕捉到回歸問題。請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布通道</.localized_link> 以了解建議的固定策略。

如果您希望在不修改清單檔案的情況下吸收新功能的穩定版本，請固定 `:latest`。該標籤每週一早上更新一次，因此請相應安排您的部署視窗。以下是一個 GitHub Actions 工作流程範例，它會按照此頻率檢查並部署最新的穩定映像檔：

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

自託管安裝可以允許受信任網路上的開發人員在不登入的情況下提交洞察報告、使用快取，或兩者兼備。儀表板和管理功能仍然需要身分驗證。

僅啟用您需要的功能：

| 伺服器環境變數 | 允許無需登入 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交建置和測試洞察報告 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀寫快取建置輸出 |

這兩個設定預設均為 **關閉**，彼此獨立，並適用於所有帳戶和專案（包括私有專案）的整個實例。它們在託管版 Tuist 上不可用，也不能替代自託管授權。

當未設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 時，舊名稱 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 仍作為相容性後備保留。

> [!WARNING]
> 僅在強制執行的辦公室網路或 VPN 邊界後面啟用這些設定。任何能夠存取已啟用端點的人都可以提交報告，或者在啟用快取存取時讀取和覆寫快取輸出。這可能導致偽造的遙測資料、快取投毒和容量耗盡。報告回應也可能洩露私有專案句柄和建置系統。Tuist 不會驗證 VPN 成員資格，也不會將轉發的 IP 標頭視為成員資格的證明。

### 設定實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口，將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器以及任何 Bazel BES 入口限制在您的受信任網路內。
2. 在升級用戶端之前，先升級每個伺服器和 Kura 複本。保持 Kura 身分驗證啟用狀態，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑證；停用它会繞過這些限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 設定您的快取端點。
3. 在每個相關的 Tuist 伺服器複本上設定上述所需的變數，然後重新啟動或重新部署它們。只有確切的值 `true` 才能啟用設定。儀表板上沒有切換開關，也沒有單獨的 Kura 旗標。

### 設定用戶端 {#network-trusted-client-configuration}

在每個相容的用戶端上設定最終的自託管伺服器 URL 和專案。當缺少憑證時，用戶端會自動發現哪些功能已啟用；無需用戶端選擇加入。發現過程不會跟隨重新導向。現有憑證繼續有效，無效或刷新失敗的憑證會導致錯誤，而不是退回到匿名模式。請重新登入或明確登出以恢復。

在啟用洞察存取之前，將所有共用憑證的工具升級到能夠保留損壞或被拒絕的憑證、拒絕無法讀取的憑證目錄，並在未簽名報告中省略 Git 來源的版本。較舊的工具可能會刪除憑證並無意中允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏發現支援或回滾到較舊版本，用戶端必須進行身分驗證。舊的 `TUIST_NETWORK_TRUSTED_PUBLISHING` 用戶端設定不再適用。

- **洞察：** 僅提交已完成的 Xcode、Gradle、Elixir/Mix 和 Bazel 報告，不包含封存、附件、覆蓋率、分片規劃或現有報告存取。參與者聲明未經驗證；未簽名的遙測資料不會驅動受信任的測試證據或自動化。請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 和 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南以了解用戶端設定和隱私詳細資訊。
- **快取：** 支援 CLI 編譯/模組快取、Bazel 快取和 Gradle 任務快取。快取清除和遠端資產下載仍然需要憑證。不支援的用戶端必須繼續進行身分驗證。
- **Bazel：** 報告需要明確的 `TUIST_BAZEL_BES_BACKEND` 和相容的 Kura。快取和報告選項是獨立啟用的。更改憑證或任一設定後，請重新執行 `tuist bazel setup`；更改編譯快取設定後，請重新執行 `tuist cache config`。

報告請求限制為每個專案 8 MB、每分鐘 60 個請求和每天 10,000 個請求。為具有多個複本的部署範圍配額設定共用的 Valkey；否則限制是按程序計算的。如果設定的共用配額後端不可用，則拒絕未簽名的報告。同時添加入口連線、主體和速率限制。

### 停用網路信任存取 {#disable-network-trusted-publishing}

將相關變數設定為 `false`，然後重新啟動 **每個相關的伺服器複本**。舊複本在被替換之前可以繼續接受無需憑證的請求。最後一個複本切換後 60 秒內，新請求的快取存取將停止；傳輸中的傳輸不會被取消。如果需要立即撤銷，請先在入口處封鎖流量。現有報告保留其通常的可見性和保留期，經過身分驗證的用戶端繼續正常工作。

## 執行時要求 {#runtime-requirements}

本節概述了在您的基礎設施上託管 Tuist 伺服器的要求。

### 相容性矩陣 {#compatibility-matrix}

Tuist 伺服器已通過測試，並與以下最低版本相容：

| 元件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能所需 |

### 執行 Docker 虛擬化映像檔 {#running-dockervirtualized-images}

我們透過 [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像檔的形式分發伺服器。

要執行它，您的基礎設施必須支援執行 Docker 映像檔。請注意，大多數基礎設施提供者都支援它，因為它已成為在生產環境中分發和執行軟體的標準容器。

### Postgres 資料庫 {#postgres-database}

除了執行 Docker 映像檔外，您還需要一個 [Postgres 資料庫](https://www.postgresql.org/) 來儲存關係資料。大多數基礎設施提供者在其產品中都包含 Postgres 資料庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的結構描述遷移。


### ClickHouse 資料庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來儲存和查詢大量的分析資料。像建置洞察等功能**需要** ClickHouse。您可以選擇自行託管 ClickHouse 或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像檔的進入點會在啟動服務前，自動執行任何待處理的 ClickHouse 結構描述遷移。

隨附的 Docker Compose 和 Helm 內嵌 ClickHouse 設定會將 ClickHouse 文字記錄層級從映像檔預設的 `trace` 降低為 `information`，這是 `system.text_log` 量的主要來源。兩者也可以限制 ClickHouse 自身的 `system.*` 運作記錄表（否則這些表是無限制的），但此功能預設為關閉——請參閱下文。外部 ClickHouse 部署應在其 ClickHouse 服務中直接設定這些運作記錄。

#### ClickHouse 複寫拓撲 {#clickhouse-replication-topology}

Tuist 後方的多複本 ClickHouse 僅在 ClickHouse Cloud 上支援。自行管理的 ClickHouse 為單複本。

匯入遷移會產生普通的 `MergeTree` 引擎。在 Cloud 上，這會透明地變為 `SharedMergeTree`，因此寫入會進入共用的物件儲存空間，且任何複本數量皆可運作。在自行管理的 ClickHouse 上，`MergeTree` 僅寫入單一複本的本地磁碟；多複本設定會根據連接使用者的 `database_replicated_allow_only_replicated_engine` 設定方式，要麼靜默地在複本間分割匯入，要麼以 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒絕 CREATE。

在自行管理的 ClickHouse 上執行一個具有一個複本的分片，並定期備份 ClickHouse 資料目錄。如果節點遺失，沒有第二個複本可以回退。

#### 限制運作記錄保留期 {#capping-operational-log-retention}

保留期可套用至 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 和 `system.part_log`。

在已有資料的實例上啟用此功能是一次性且不可逆的步驟，這就是為什麼兩個套件都不會為您執行此操作。任何保留期視窗都會導致這些表定義不再符合其設定，因此 ClickHouse 會將每個表重新命名並啟動一個新表，如 [已取代的記錄表](#superseded-log-tables) 所述。留下的世代包含迄今為止累積的所有內容，且本身不帶有任何保留期，因此除非您在同一步驟中回收它，否則它將永久留在磁碟上，而新視窗僅限制從那時起寫入的資料列。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

該單一 `helm upgrade` 是自包含的，因為將 `ttlDays` 從空白改為設定值會新增 drop-in 掛載並滾動更新 ClickHouse Pod：它會重新啟動、取代表格，然後升級後作業會刪除它們。使用 `helm upgrade --wait` 進行部署，以便在作業執行前先滾動更新 Pod；否則，世代會在作業檢查後才出現，而下一次 `helm upgrade` 則會回收它們。

使用 Docker Compose 時，取消註解 `docker-compose.yml` 中 `clickhouse` 服務上的 `clickhouse-log-ttl.xml` 卷宗，並在 `.env` 中設定這兩個變數：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，您可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，這樣後續的 ClickHouse 升級就不會自行丟棄歷史記錄。

#### 已取代的記錄表 {#superseded-log-tables}

ClickHouse 在啟動時會檢查每個系統記錄表是否仍符合其設定。如果不符合，它會將現有表重新命名為 `system.<name>_0`，然後是 `_1`、`_2` 等，並啟動一個新表。當您更改保留期視窗，或在任何更改系統記錄結構描述的 ClickHouse 升級時，就會發生這種情況。

重新命名表不會複製其資料，因此這不會消耗額外的磁碟空間。已取代的表後續會發生什麼情況取決於其來源表，因為它會保留在被取代那一刻活動表所擁有的任何保留期。首次啟用保留期時，被取代的表沒有任何保留期，因此它會持有迄今為止累積的所有歷史記錄並無限期保留。後續對視窗的更改會取代已帶有 TTL 的表，因此這些表會自行過期並留下一個空表。ClickHouse 永遠不會刪除表本身，因此在長期運行的實例上，它們無論如何都會累積。

預設情況下會保留已取代的表，這樣升級就不會自行丟棄運作歷史記錄。將政策設定為 `delete` 以改為刪除它們，這會在 `docker compose up` 和每次 `helm upgrade` 時發生：

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

使用 Helm chart 時，將相同的政策設定為值：

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

刪除已取代的表會回收其磁碟空間。活動表絕不會受到影響，自被取代以來寫入的資料列也不會受到影響。

若要在不更改政策的情況下一次性回收空間，請手動刪除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 資料庫使用 `Atomic` 引擎，這會將普通的 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（預設為八分鐘）。`SYNC` 會立即刪除資料，這正是在磁碟已滿時刪除這些表所需要的。


### 儲存空間 {#storage}

您還需要一個解決方案來儲存檔案（例如框架和函式庫的二進位檔）。Tuist 伺服器支援與 S3 相容的儲存空間和 Azure Blob Storage，用於儲存伺服器拥有的工件。

> [!TIP]
> **最佳化快取**
>
> 如果您的主要目標是減少快取延遲，您可能不需要自行託管整個伺服器。您可以在靠近您的 CI 或開發者網路的地方部署自行託管的 Kura 節點，並將它們連接到託管的 Tuist 伺服器或您的自行託管伺服器。
>
> 請參閱 <.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link>。


### 自行託管的 Kura 節點 {#self-hosted-cache-nodes}

若要將自行託管的 Kura 節點與自行託管的 Tuist 伺服器搭配使用：

1. 在 Tuist 伺服器上設定 `KURA_CONTROL_PLANE_CLIENT_ID` 和 `KURA_CONTROL_PLANE_CLIENT_SECRET`。用戶端 ID **必須是 UUID**。使用 <.localized_link href="/guides/cache/self-host#control-plane-client">自行託管快取指南</.localized_link> 中的命令產生 UUID 和隨機密鑰，並將它們儲存在您的部署密鑰中。
2. 遵循 <.localized_link href="/guides/cache/self-host">自行託管快取指南</.localized_link> 部署 Kura 節點，使用相同的控制平面憑證。
3. 使用 `KURA_REGISTRATION_URL` 和 `KURA_ADVERTISED_HTTP_URL` 設定每個 Kura 節點。註冊心跳會告訴伺服器它可以向 CLI 宣傳哪些就緒且面向用戶端的 Kura 端點。

## 設定 {#configuration}

服務的設定在執行階段透過環境變數完成。鑑於這些變數的敏感性，我們建議將其加密並儲存在安全的密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變數，確保它們絕不會顯示在日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要的變數會在啟動時進行驗證。如果缺少任何變數，啟動將會失敗，且錯誤訊息將詳細說明缺少的變數。


### 授權設定 {#license-configuration}

作為內部部署使用者，您將收到一個授權，需要將其公開為環境變數。該授權用於驗證部署，並確保服務在協議條款範圍內運行。

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務等級協議後提供的授權。接受標準授權金鑰，或用於伺服器無法聯繫外部服務的隔離環境中的 base64 編碼憑證。 | 是 | | `******` |

> [!WARNING]
> **到期日**
>
> 授權具有到期日。如果授權在 30 天內到期，使用者在使用與伺服器互動的 Tuist 命令時會收到警告。如果您有興趣續訂授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境設定 {#base-environment-configuration}

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從網際網路存取執行個體的基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密資訊的金鑰（例如 cookie 中的工作階段） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於產生雜湊密碼的 Pepper | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於產生隨機權杖的密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於對敏感資料進行 AES-GCM 加密的金鑰。超過 32 位元組的值會被截斷為前 32 位元組；建議使用 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 逗號分隔的 `id:base64` 加密金鑰，每個 32 位元組（`openssl rand -base64 32`）。第一個金鑰用於加密新資料；其他金鑰和 `TUIST_SECRET_KEY_ENCRYPTION`（ID `V1`）仍可用於解密現有資料。使用 `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` 將現有資料移至目前金鑰 | 否 | | `k2:3q2+7w...` |
| `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` | 當不應為 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` 的第一個金鑰時，用於加密新資料的金鑰 ID | 否 | | `V1` |
| `TUIST_USE_IPV6` | 當為 `1` 時，它會設定應用程式使用 IPv6 位址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程式使用的日誌層級 | 否 | `info` | [日誌層級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 您的 GitHub 應用程式的 slug，取自 `https://github.com/apps/<slug>`。安裝應用程式時需要此值。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式的 base64 編碼私鑰，以解鎖額外功能，例如自動發布 PR 評論 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程式的私鑰，以解鎖額外功能，例如自動發布 PR 評論。**我們建議改用 base64 編碼版本，以避免特殊字元造成的問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件地址以 `@<this-domain>` 結尾且已證明擁有該地址控制權的使用者，可以存取營運 URL（`/ops/*`）。若未設定，則無人可以存取。請參閱 [營運](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 在儀表板導覽列中顯示為徽章的標籤，用於識別伺服器執行個體（例如版本號或分支名稱） | 否 | 開發環境中的 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用網頁伺服器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許在未登入的情況下提交建置和測試洞察。請參閱 [網路信任存取](#network-trusted-access) 以了解設定和安全需求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許在未登入的情況下讀取和寫入快取。請參閱 [網路信任存取](#network-trusted-access) 以了解設定和安全需求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端點，用於傳送追蹤資料 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | Loki 相容端點的基礎 URL，用於推送日誌（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **透過 HTTPS 提供應用程式服務**
>
> 工作階段 Cookie 標記為 `Secure`，因此瀏覽器會在純 `http://` 連線中捨棄它們，導致使用者無法登入。請在伺服器前方終止 TLS（使用內部 CA 簽發憑證的反向代理即可），並將 `TUIST_APP_URL` 設為 `https://` URL，即使是內部或僅限 VPN 的部署也是如此。

### 資料庫設定 {#database-configuration}

下列環境變數用於設定資料庫連線：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 存取 Postgres 資料庫的 URL。請注意，URL 應包含驗證資訊 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程式資料表使用的 PostgreSQL 結構描述。當您的資料庫政策不允許使用 `public` 結構描述時，請設定此值。結構描述名稱必須是未加引號的 PostgreSQL 識別子。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用的選用 Postgres URL。當 `DATABASE_URL` 指向權限較窄的執行階段角色時，請將其設為擁有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程式資料表權限的執行階段 Postgres 角色。當網頁伺服器不應以結構描述擁有者身分連線時，請與 `TUIST_MIGRATION_DATABASE_URL` 搭配使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 存取 ClickHouse 資料庫的 URL。請注意，URL 應包含驗證資訊 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 設為 true 時，會使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫。除非啟用 `TUIST_DATABASE_SSL_VERIFY`，否則不會驗證伺服器憑證 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 設為 true 時，資料庫伺服器憑證必須鏈結至受信任的 CA，並與 `DATABASE_URL` 主機相符。需要 `TUIST_USE_SSL_FOR_DATABASE`。我們建議啟用此功能 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 包含用於驗證資料庫伺服器的 CA 憑證之 PEM 檔案路徑。若未設定，則使用作業系統的信任儲存區 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 在連線池中保持開啟的連線數量 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出的所有連線是否超過佇列間隔的時間間隔（毫秒）[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 佇列中的閾值時間（毫秒），池使用此時間來決定是否應開始捨棄新連線[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新之間的時間間隔（毫秒） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新前的最大 ClickHouse 緩衝區大小（位元組） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要執行的 ClickHouse 緩衝區處理程序數量 | 否 | `5` | `5` |

預設情況下，Tuist 會加密資料庫連線，但不會驗證伺服器憑證，因此網路路徑上的攻擊者可以冒充資料庫。請設定 `TUIST_DATABASE_SSL_VERIFY=1` 以進行驗證。如果您的提供者使用自己的 CA 簽署憑證（如 Amazon RDS 和 Google Cloud SQL），請下載其 CA 捆綁包，將其掛載到容器中，並將 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向該檔案。`DATABASE_URL` 中的主機必須與憑證中的名稱或 IP 位址相符。啟用驗證後，無法通過這些檢查的憑證會導致所有資料庫連線失敗，因此啟用後請檢查伺服器日誌中是否有 `Bad Certificate` 或 `Unknown CA`。

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，版本遷移會在執行 Ecto 遷移鏈之前建立結構描述（如果尚不存在）。如果遷移角色無法建立結構描述，請預先建立結構描述並將遷移角色設為其擁有者。

Tuist 透過設定工作階段 `search_path` 將連線指向自訂結構描述。某些池化或代理的 Postgres 設定（例如 PgBouncer，或限制啟動參數的受管資料庫）不會應用此設定，工作階段會回退到 `public`，這在遷移期間會顯示為 `permission denied for schema public`。透過此类設定連線時，請將結構描述固定在角色本身，以便每個工作階段無論代理為何都從該結構描述開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 驗證環境設定 {#authentication-environment-configuration}

我們透過 [身分識別提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進驗證。若要使用此功能，請確保所選提供者的所有必要環境變數都存在於伺服器環境中。**缺少變數** 將導致 Tuist 略過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登入以及自助註冊是內建功能，預設啟用。在需要要求身分識別提供者的執行個體上（例如強制使用 SSO 時），您可以完全關閉它們。這會從登入體驗中移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉每個對應的伺服器端端點，包括 CLI 使用的電子郵件/密碼端點 (`tuist auth`)。

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登入和註冊。設為 `0` 以從登入頁面移除電子郵件/密碼表單、註冊連結和密碼重設流程，並關閉對應的伺服器端端點 | 否 | `1` | `0` |

#### 停用已設定的身分識別提供者 {#disabling-a-configured-identity-provider}

預設情況下，只要設定了提供者，它就會顯示為登入選項。若要保留提供者的設定（其憑證保持設定狀態）同時將其從登入和註冊頁面中移除，請將對應的開關設為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登入回呼，因此該方法將完全無法使用。

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
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

接著，您需要在執行 Tuist 伺服器的環境中公開下列環境變數：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的用戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的用戶端金鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入。您為平台整合（PR 評論等）設定的 GitHub App 會與登入共用其用戶端憑證，因此它會顯示為登入選項。設為 `0` 以保留應用程式，同時從登入頁面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設定 Google 驗證。為此，您需要建立類型為 OAuth 用戶端 ID 的新憑證。建立憑證時，選擇「Web Application」作為應用程式類型，將其命名為 `Tuist`，並將重新導向 URI 設為 `{base_url}/users/auth/google/callback`，其中 `base_url` 是您託管服務運行的 URL。建立應用程式後，複製用戶端 ID 和金鑰，並分別將它們設為環境變數 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意畫面範圍**
>
> 您可能需要建立同意畫面。建立時，請務必新增 `userinfo.email` 和 `openid` 範圍，並將應用程式標記為內部使用。


#### Okta {#okta}

您可以透過 [OAuth 2.0](https://oauth.net/2/) 協定啟用 Okta 驗證。您需要按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些指示</.localized_link> 在 Okta 上 [建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設定 Okta 應用程式期間取得用戶端 ID 和金鑰後，您需要設定下列環境變數：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於向 Okta 驗證的用戶端 ID。此數字應為您的組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於向 Okta 驗證的用戶端金鑰 | 是 | | |

數字 `1` 需要替換為您的組織 ID。這通常為 1，但請檢查您的資料庫。

### 儲存環境設定 {#storage-environment-configuration}

 Tuist 需要儲存空間來存放透過 API 上傳的成品。為了讓 Tuist 有效運作，**必須設定其中一種支援的儲存解決方案**。

設定 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇伺服器成品後端：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 伺服器成品儲存後端。使用 `s3` 搭配 S3 相容儲存，或使用 `azure_blob` 搭配 Azure Blob Storage | 否 | `s3` | `azure_blob` |

#### S3 相容儲存 {#s3compliant-storages}

您可以使用任何 S3 相容的儲存提供者來儲存成品。下列環境變數是驗證並設定與儲存提供者整合所需的：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於向儲存提供者驗證的存取金鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於向儲存提供者驗證的秘密存取金鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 儲存桶所在的區域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 儲存提供者的端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 將儲存成品的儲存桶名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | 用於驗證 S3 HTTPS 連線的 PEM 編碼 CA 憑證。適用於使用自簽憑證或內部憑證授權單位的隔離環境。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 與儲存提供者建立連線的逾時時間（毫秒） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從儲存提供者接收資料的逾時時間（毫秒） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 與儲存提供者的連線池逾時時間（毫秒）。使用 `infinity` 表示無逾時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連線的最大閒置時間（毫秒）。使用 `infinity` 可讓連線永久保持活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個連線池的最大連線數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用的連線池數量 | 否 | 系統排程器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連線至儲存提供者時使用的協定（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將儲存桶名稱建構為子網域（虛擬主機） | 否 | `false` | `1` |

> [!NOTE]
> **來自環境變數的 AWS Web Identity 驗證**
>
> 如果您的儲存提供者是 AWS，且您希望使用 Web Identity Token 進行驗證，您可以將環境變數 `TUIST_S3_AUTHENTICATION_METHOD` 設定為 `aws_web_identity_token_from_env_vars`，Tuist 將會使用慣用的 AWS 環境變數來採用此方法。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請依照 [這些文件](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 取得 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設定為 `https://storage.googleapis.com`。其他環境變數與任何其他 S3 相容儲存相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，請設定 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並設定 Azure 儲存帳戶憑證：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 儲存帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 的儲存帳戶存取金鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 儲存伺服器成品的容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略則使用 `https://<account>.blob.core.windows.net` | 否 | 衍生自帳戶名稱 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 的 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm Chart 時，請設定 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。Chart 的頂層 `objectStorage` 設定仍保持 S3 相容，因為選用的快取和 Registry Mirror 工作負載仍預期使用 S3 相容儲存。若停用這些工作負載且伺服器使用 Azure Blob，請設定 `objectStorage.mode=external` 並將外部物件儲存端點與憑證留空，以避免部署內嵌的 MinIO 服務。

#### 成品保留 {#artifact-retention}

在自託管實例中，成品清理預設為停用。每種支援的成品類型都有各自的環境變數。將變數設定為正整數的天數，即可啟用該成品類型的清理。將變數留空或不設定，僅會停用該成品類型的清理。

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

所有六個鍵皆為選用。此範例為每種支援的成品類型啟用獨立的保留視窗。省略某個鍵或將其值留空，即可保持該成品類型的清理為停用狀態。自託管的保留視窗沒有 30 天的上限。若設定的值不是正整數，伺服器將在啟動時失敗。

變更保留變數後，請重新啟動伺服器。每個排入佇列的自託管清理批次在刪除檔案前都會檢查目前的設定，因此取消設定或清空變數，或增加其視窗，也能在重新啟動後保護檔案免受待處理作業的影響。

| 環境變數 | 從物件儲存中移除的成品檔案 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 快取、舊版內容定址儲存快取、模組快取，以及 Gradle 快取檔案 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App Preview 建置與圖示 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 目前與舊版的建置封存 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 儲存在已過期執行之成品前綴下的所有物件，包括結果套件、叫用記錄和工作階段封存 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片套件 |

排程清理僅移除成品 Blob。它會保留對應的 PostgreSQL 和 ClickHouse 資料列，因此在下載過期後，建置、測試、執行、Preview 和分片中繼資料仍可於儀表板中可見。此設定不會變更 ClickHouse 資料表的保留規則。

### 電子郵件設定 {#email-configuration}

Tuist 需要電子郵件功能來進行使用者驗證和交易通知（例如重設密碼、帳戶通知）。目前，**僅支援 Mailgun** 作為電子郵件提供者。

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於向 Mailgun 驗證的 API 金鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件的網域 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將出現在「寄件者」欄位的電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 供使用者回覆的選用回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新使用者註冊的電子郵件確認。啟用後，使用者將自動獲得確認，並可在註冊後立即登入 | 否 | 若未設定電子郵件則為 `true`，若已設定電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅在您想要發送電子郵件時才需要電子郵件設定變數。若未設定，電子郵件確認將自動跳過

> [!NOTE]
> **SMTP 支援**
>
> 目前不提供通用 SMTP 支援。若您的內部部署需要 SMTP 支援，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 以討論您的需求。


> [!NOTE]
> **隔離環境部署**
>
> 對於沒有網際網路存取權限或未設定電子郵件提供者的內部部署安裝，預設會自動跳過電子郵件確認。使用者可在註冊後立即登入。若您已設定電子郵件但仍想跳過確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。若要在設定電子郵件時要求電子郵件確認，請設定 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額與密碼重設連結**
>
> 設定電子郵件後，邀請郵件（建立、大量或重新發送）限制為每五位分鐘每位收件人一封，且每個組織與每位邀請者每小時可突發 50 封並以每小時 50 封的速度補充。取消邀請不會恢復配額，而邀請 API 會在配額耗盡時以 `429` 和 `Retry-After` 回應。若有多個複本，請設定共用的 Valkey 以實現全部署範圍的配額；若已設定但無法使用，則會拒絕邀請郵件。密碼重設連結在 15 分鐘後過期。


### Git 平台設定 {#git-platform-configuration}

Tuist 可以<.localized_link href="/guides/server/authentication">與 Git 平台整合</.localized_link>，提供額外功能，例如自動在您的 Pull Request 中張貼評論。

#### GitHub {#platform-github}

自行託管的 Tuist 伺服器無法安裝在 `https://tuist.dev` 上執行的 GitHub App。GitHub App 會綁定註冊它們的伺服器，因此您的部署需要在 github.com 上擁有自己的 App。

##### 註冊 App {#platform-github-registering-the-app}

[建立由您的 GitHub 組織擁有的 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非您建立的是 OAuth App，否則您可以重複使用為驗證建立的 App。使用以下設定進行配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 的值：

| 設定 | 值 |
| --- | --- |
| 回呼 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設定 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重新導向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任意隨機字串。您將把它設定為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予下列儲存庫權限：

| 權限 | 存取權 |
| --- | --- |
| 內容 | 唯讀 |
| 中繼資料 | 唯讀 |
| Issues | 讀寫 |
| Pull requests | 讀寫 |
| Checks | 讀寫 |

同時授予 **成員：唯讀** 組織權限。在 github.com 設定期間，Tuist 會檢查連接組織安裝的人員是否為有效的 GitHub 組織擁有者，而不僅僅是擁有其某個儲存庫存取權的人。

讓 App 訂閱 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持**安裝期間要求使用者授權 (OAuth)** 為停用狀態，以便 GitHub 將安裝程式發送至設定 URL。Tuist 會使用額外的 `/integrations/github/authorize` 回呼啟動單獨的授權步驟，以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝程式隨後會選擇一個 Tuist 組織。在 GitHub 組織上的安裝始終顯示此選擇；在 Tuist 中開始的安裝會保留其組織。

##### 設定伺服器 {#platform-github-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 描述 | 必填 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公開頁面 URL `https://github.com/apps/<slug>` 的最後一個路徑元件 | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數值 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式的 Base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，因為後者對平台處理換行符的方式較為敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上設定的 Webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **設定所有必要的 App 憑證**
>
> 組織整合頁面上的 **安裝 GitHub App** 按鈕會保持停用狀態，直到設定了 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私鑰為止。數值 `TUIST_GITHUB_APP_ID` 也需用於驗證安裝所有權。安裝 URL 內嵌了 App slug，因此若缺少 `TUIST_GITHUB_APP_NAME`，特別是會產生一個 GitHub 回應 404 的連結。

伺服器重新啟動後，組織管理員將依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 安裝 App 並將儲存庫連接至專案。

##### OIDC 驗證依賴此設定 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link> 會根據連接到您專案的儲存庫來解析 CI 令牌中的儲存庫聲明，而連接只能透過已安裝的 GitHub App 建立。在您的 CI 工作流程使用 OIDC 進行驗證之前，請先完成上述設定。

您的 Tuist 伺服器也需要出站存取您的 CI 提供者的 OIDC 發行者，以獲取其簽章金鑰：

| CI 提供者 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變數僅配置 Tuist 的 github.com App。若要改為將 Tuist 與 GitHub Enterprise Server (GHES) 執行個體整合，組織管理員需切換至整合頁面上的 **企業伺服器** 分頁並輸入 GHES 基礎 URL — Tuist 會引導他們透過 GitHub 的 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 執行個體上註冊全新的 Tuist App。新 App 的憑證會按安裝加密儲存；不需要額外的 `TUIST_GITHUB_APP_*` 環境變數。

#### Origin {#platform-origin}

自行託管的 Tuist 伺服器需要自己的 Origin app，並使用您部署的 URL 和簽章金鑰進行配置。為每個 Tuist 環境註冊單獨的 app，以使安裝和憑證保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽章金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設定](https://cursor.com/codebase/settings/apps) 中建立 app。將 `origin-app-public.pem` 的內容註冊為其公開簽章金鑰。妥善保管 `origin-app-private.pem`；您需要將其提供給 Tuist 伺服器，而不是上傳到 Cursor。
3. 配置下列設定，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎 URL：

   | 設定 | 值 |
   | --- | --- |
   | 首頁 URL | `YOUR_APP_URL` |
   | 重新導向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 複製註冊的 App ID，它以 `app_` 開頭。

Tuist 在安裝期間請求下列權限：

| 範圍 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 尋找拉取請求及其目前的 head 提交。 |
| `repository:pull_requests:reviews:write` | 讀取、發布和更新報告評論。Origin 包含對應的 review-read 權限。 |
| `repository:metadata:read` | 探索儲存庫並讀取其預設分支。由 Origin 自動授予。 |

不要選取可選的儲存庫 webhook 事件。安裝生命週期通知已足夠；不需要原始碼存取、合併權限和 check-run 權限。

##### 配置伺服器 {#platform-origin-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設定複製的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私鑰儲存在您部署的密鑰管理器中。保留其多行 PEM 格式；此設定不接受 base64 編碼的替代方案。切勿將金鑰提交至原始碼控制或在日誌中揭露。兩個變數必須屬於同一個註冊的 app。

您的 Tuist 伺服器需要對 `api.cursor.com` 的出站 HTTPS 存取。Cursor 必須能夠將請求傳遞至 webhook URL，且管理員必須能夠在瀏覽器中返回重新導向 URI。兩個註冊的 URL 都必須與您部署的 HTTPS 基礎 URL 相符。

##### 安裝 App {#platform-origin-installing-the-app}

伺服器重新啟動後，管理員開啟 **設定 → 整合**，在 Origin 下方選擇 **連接**，並核准 app 對適當 Origin 帳戶和儲存庫的存取權限。整個流程中都會保留 Tuist 組織。直接從 Origin 發起的安裝則會提示管理員登入並選擇要連接的 Tuist 組織。然後他們選擇 **新增專案連接** 以將 Tuist 專案連結至原生儲存庫。

請遵循 <.localized_link href="/guides/integrations/gitforge/origin">Origin 整合指南</.localized_link> 了解專案連接和結果上傳需求。安裝 app 不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

#### Entire {#platform-entire}

自行託管的 Tuist 伺服器需要自己的 Entire 外掛程式，並使用您部署的 URL 和簽章金鑰進行配置。Entire 外掛程式需要合作夥伴註冊，因此在開始之前請聯絡 Entire。為每個 Tuist 環境註冊單獨的外掛程式，或至少註冊單獨的簽章金鑰，以使安裝和憑證保持獨立。

##### 註冊外掛程式 {#platform-entire-registering-the-plugin}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽章金鑰組：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. 依照 Entire 的 [外掛程式註冊指南](https://docs.entire.com/guides/api/plugins/register) 註冊外掛程式。分享 `entire-plugin-public.pem` 的內容，或發布它的 JWKS URL，作為外掛程式的簽章金鑰。妥善保管 `entire-plugin-private.pem`；您需要將其提供給 Tuist 伺服器，而不是 Entire。
3. 配置下列 URL，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎 URL：

   | 設定 | 值 |
   | --- | --- |
   | 安裝後 URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL | `YOUR_APP_URL/webhooks/entire` |

4. 記下 Entire 確認的外掛程式 slug 及其提供的 webhook 簽章金鑰 URL。

請求下列權限：

| 權限 | 用途 |
| --- | --- |
| `contents:read` | 接收 Trail 事件並尋找具有其 head 提交的開啟和草稿 Trail。 |
| `checks:write` | 發布 Tuist gate。 |
| `findings:write` | 發布並解決失敗和不穩定測試的發現。 |
| `discussions:write` | 發布和更新摘要評論。未授予此權限的安裝仍會收到 gate 和發現。 |

不需要儲存庫寫入存取權。如果您將權限新增至現有的註冊，請要求 Entire 更新它，並確認安裝已授予新權限。請參閱 Entire 的 [Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings) 和 [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) 合約。

##### 配置伺服器 {#platform-entire-configuring-the-server}

設定下列環境變數，然後重新啟動伺服器：

| 環境變數 | 說明 | 必要 | 預設值 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認的外掛程式 slug。 | 是 | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符號。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Entire 在註冊時提供的 webhook 簽章金鑰 URL。 | 是 | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 當您透過 JWKS 註冊簽章金鑰時的金鑰 ID。 | 否 | | |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core URL。 | 否 | `https://eu.auth.entire.io` | |

將私鑰儲存在您部署的秘密管理員中，並保留其多行 PEM 格式。切勿將金鑰提交至原始碼控管或在日誌中公開。使用 Tuist Helm chart 時，您可以改為將 PEM 儲存在您的 1Password 保險庫中作為 `ENTIRE_PLUGIN/private_key`，並與 `server.config.managedSecrets` 一起啟用 `server.config.entirePluginKey.enabled`；項目和欄位名稱可透過 `server.config.entirePluginKey.item` 和 `.field` 進行配置。此對應不會設定 slug 或 webhook 簽章金鑰 URL。

您的 Tuist 伺服器需要對 Entire Core 以及為您的儲存庫提供服務的区域性 Entire API 主機具有出站 HTTPS 存取權，這些主機均位於 `entire.io` 或 `entire.com` 之下。Tuist 會驗證安裝收據和 webhook 簽章，產生短期且限於儲存庫範圍的權杖，且絕不會將權杖嵌入報告連結中。

##### 啟用整合 {#platform-entire-enabling-the-integration}

在推出應用程式之前套用伺服器遷移，然後全域啟用 `entire_trails` 功能旗標，以向所有帳戶或選定帳戶提供整合。啟用旗標不會改變誰可以在 Entire 中安裝外掛程式；若要在擁有該外掛程式的 Entire 專案之外提供它，請聯絡您的 Entire 聯絡人以獲得允許。此整合獨立於 Tuist 的 CI 執行配置。

如果您回滾應用程式，請保留 `entire_trail_reports` 資料表，以便後續升級可以恢復正在進行的發布。

管理員隨後依照 <.localized_link href="/guides/integrations/gitforge/entire">Entire 整合指南</.localized_link> 安裝外掛程式並將儲存庫連接至專案。安裝外掛程式不會啟動建置或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器回報結果。

## 本機測試 {#testing-locally}

我們提供一個全面的 Docker Compose 配置，其中包含在部署至基礎設施之前，在本機電腦上測試 Tuist 伺服器所需的所有相依性：

- PostgreSQL 15
- ClickHouse 26.5（用於分析）
- ClickHouse Keeper（用於協調）
- MinIO（用於 S3 相容儲存）
- Kura（用於本機自行託管快取測試）
- pgweb（用於資料庫管理）

> [!CAUTION]
> **需要授權**
>
> 法律規定必須提供有效的 `TUIST_LICENSE` 環境變數才能執行 Tuist 伺服器，包括本機開發實體。如果您需要授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速入門：**

1. 下載配置文件：
   ```bash
   curl -O https://tuist.dev/server/self-host/docker-compose.yml
   curl -O https://tuist.dev/server/self-host/clickhouse-config.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-level.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-ttl.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-keeper-config.xml
   curl -O https://tuist.dev/server/self-host/.env.example
   ```

2. 配置環境變數：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   捆綁的 ClickHouse 服務接受下列選用操作日誌控制：

   | 環境變數 | 說明 | 預設值 | 範例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌資料表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留天數 | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 伺服器記錄器和 `system.text_log` 層級 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 取代系統日誌資料表時，如何處理其留下的 `<name>_N` 資料表。`ignore` 會保留它們，`delete` 則會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 和相依性映像的 `linux/arm64` 變體。若要強制使用 amd64 模擬進行偵錯，請使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 執行 Compose。

   捆綁的 compose 檔案使用具名 Docker 磁碟區來儲存持久化資料。若您將其替換為主機綁定掛載，請先建立主機目錄，並確保容器使用者（尤其是 ClickHouse 和 ClickHouse Keeper 資料目錄）可寫入這些目錄。

4. 在 http://localhost:8080 存取伺服器

**服務端點：**
- Tuist 伺服器：http://localhost:8080
- Kura 快取（HTTP + REAPI gRPC 共用同一埠）：http://localhost:4000
- MinIO 控制台：http://localhost:9003（憑證：`tuist` / `tuist_dev_password`）
- MinIO API：http://localhost:9002
- pgweb（PostgreSQL UI）：http://localhost:8081
- Prometheus 指標：http://localhost:9091/metrics
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

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變數範例檔案

## 使用 Helm 部署 Kubernetes {#kubernetes-with-helm}

Tuist 提供官方的 Helm Chart 以部署至 Kubernetes。該 Chart 封裝了 Tuist 伺服器和快取服務，以及內建的基礎設施相依性，您可視需要將其替換為外部提供者。

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

使用 `--set` 傳遞授權適合快速安裝。若將您的值存放在版本控制中，請將授權儲存在由 Helm 外部管理的 Kubernetes Secret 中（例如使用 Vault、Sealed Secrets 或 SOPS），並將 Chart 指向該 Secret：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下的項目命名了您 Secret 中持有授權值的欄位，該值可以是授權金鑰，或是針對隔離環境安裝的 Base64 編碼授權憑證。`existingSecretKeys` 下的每個項目預設為 Chart 自身的金鑰名稱，因此請將您的 Secret 中不包含的項目設為空字串，如上方的 `certificateBase64` 所示。否則 Pod 會參考不存在的金鑰而無法啟動。請在安装或升級 Chart 之前，在發行版命名空間中建立該 Secret。

僅透過單一來源配置授權：`server.license.key` 或 `server.license.existingSecret`。若未設定任何來源或混合使用來源，Chart 將無法渲染。透過 `server.extraEnv` 傳遞的授權不算作來源，因此請改用 `existingSecret`。

### 基礎設施相依性 {#helm-infrastructure-dependencies}

該 Chart 管理三個基礎設施相依性：`postgresql`、`clickhouse` 和 `objectStorage`。每個相依性預設為 **內建** 模式，表示 Chart 會將它們部署在叢集內部。若要改為指向您自己的外部實體，請將相依性的 `mode` 設為 `external`，並在您的 `values.yaml` 中填寫連線詳細資訊。例如，若要使用外部 PostgreSQL 資料庫：

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

Chart 會從 Secret 讀取主機、使用者名稱和密碼，並透過 Kubernetes 環境變數替換組成 `DATABASE_URL`，因此密碼不會呈現在 Helm manifest 中。Secret 中的密碼值應符合 URL 安全規範，因為它會被插入至資料庫 URL 中。

相同模式也適用於 `clickhouse` 和 `objectStorage`。請參閱 Chart 的 `values.yaml` 中各章節下的 `external` 區塊，以取得完整的可配置欄位清單。

### 共用排程與標籤 {#helm-shared-scheduling-and-labels}

Chart 在 `global` 下公開一組共用的 Pod 設定，讓營運人員能調整部署以符合其叢集需求，無需在每個工作負載上重複相同的值：

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
- 從私有 Registry 提取鏡像映像檔
- 指定專用的節點池
- 允許 Pod 调度到保留給 Tuist 工作負載的 tainted 節點

### 工作負載身分與服務帳戶 {#helm-workload-identity}

Chart 會依應用程式工作負載範圍化服務帳戶，讓您僅在需要的地方授予身分：

- `server.serviceAccount` 適用於 Tuist Server 部署與遷移作業
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

Chart 將儲存與服務網格專屬的微調設為選用，以保持預設值的可移植性：

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

- `cache.podSecurityContext` 預設為空。若您的儲存類別或 CSI 驅動程式需要在掛載的卷冊上共用群組擁有權，請設定 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 標準的 `9000` 原生服務連接埠，當服務網格或平台保留與該連接埠衝突時可以變更。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，使 ClickHouse 對內建內部日誌表（如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 和 `system.part_log`）保持無限制的保留。設定此值會取代這些表格一次，因此請搭配 `supersededTables: delete` 一起採用 — 請參閱 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制營運日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對內建 ClickHouse 伺服器記錄器和 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不屬於任何表格定義的一部分，因此變更它永遠不會取代表格。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore`，並決定 ClickHouse 在取代系統日誌表時留下的 `<name>_N` 表格的處理方式。將其設為 `delete` 可在每次 `helm upgrade` 時刪除它們。
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

### 值參考 {#helm-values-reference}

如需完整的可配置值清單，請參閱 Chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 映像檔位於：
```
ghcr.io/tuist/tuist
```

發布的映像檔包含用於 `.xcactivitylog` 封存檔的內建 Linux 建置處理，因此自託管部署可以在不執行任何額外服務的情況下處理建置 — `ProcessBuildWorker` Oban 作業在每個伺服器 Pod 上以程序內方式執行。若您想將建置處理卸載到專用的副本集（例如，獨立於網頁層擴展解析吞吐量），請在 Helm Chart 中設定 `processor.enabled: true`：Chart 會將相同映像檔部署為僅消費佇列的消費者（`TUIST_PROCESSOR_MODE=true`）。請參閱 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) 以取得完整的控制參數。

> [!NOTE]
> `.xcresult` 解析依賴 Xcode 的 `xcresulttool`，因此只能在 macOS 上執行。CLI 會為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 伺服器預設為 **本機** 處理模式，在開發者機器上解析 xcresult（該機器已具備用於建置本身的 Xcode）並上傳結構化結果。測試結果無需任何額外基礎設施即可匯入。

### 提取 Docker 映像檔 {#pulling-the-docker-image}

您可以執行以下命令來取得映像檔：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

該映像檔同時發布了 `linux/amd64` 和 `linux/arm64` 架構，因此 Docker 會自動為主機選擇原生的 Linux 架構。

或提取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像檔 {#deploying-the-docker-image}

Docker 映像檔的部署流程會因您選擇的雲端供應商和您組織的持續部署方法而異。由於大多數雲端解決方案和工具（如 [Kubernetes](https://kubernetes.io/)）都將 Docker 映像檔作為基本單位，本節中的範例應能與您現有的設定良好配合。

> [!WARNING]
> 若您的部署管線需要驗證伺服器是否已啟動並運行，您可以向 `/ready` 發送 `GET` HTTP 請求，並斷言回應中的狀態碼為 `200`。


#### Fly {#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，您需要一個 `fly.toml` 配置檔案。建議在您的持續部署 (CD) 管線中動態產生該檔案。以下是供您參考的範例：

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

接著您可以執行 `fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署中，請勿執行 `fly launch --local-only`，而是需要執行 `fly deploy --local-only`。Fly.io 不允許提取私有 Docker 映像檔，這就是我們需要使用 `--local-only` 標誌的原因。


## Prometheus 指標 {#prometheus-metrics}

Tuist 在 `/metrics` 公開 Prometheus 指標，協助您監控自託管執行個體。這些指標包括：

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
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在使用前的閒置時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 區間：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列例外總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連線指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所花費的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`error`
  - 區間：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 連線嘗試總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`

#### 傳送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 傳送請求所花費的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連線在傳送前的閒置時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標皆提供 `_bucket`、`_sum` 和 `_count` 變體，以供詳細分析。

### 其他指標

除了 Finch 指標外，Tuist 還公開以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳號、專案等）
- 資料庫效能（使用 Tuist 託管基礎設施時）

## 營運 {#operations}

Tuist 在 `/ops/` 下提供一組工具程式，可用於管理你的執行個體。

> [!WARNING]
> **授權**
>
> 只有電子郵件網域符合 `TUIST_OPERATOR_EMAIL_DOMAIN` 的使用者才能存取 `/ops/` 端點。若未設定該變數，則無人能存取。請將其設為你擁有信箱控制權的網域。
>
> 使用者也必須證明其地址的控制權：透過點擊確認或重設密碼郵件、使用 Google、GitHub 或 Apple 登入，或輸入一次性代碼或出示代理登入的已驗證電子郵件。自動確認的帳號（在未設定郵件提供者時為預設行為）在完成此步驟前不符合資格。帳號建立後，僅當地址位於 `TUIST_OPERATOR_EMAIL_DOMAIN` 時才會記錄證明；因此在你設定或變更該變數後，尚未在此變數下證明其地址的營運人員需再次進行證明。透過其中一個提供者登入或透過代理登入建立的帳號，會從建立時就攜帶證明。若無郵件提供者，以密碼註冊的帳號無法連結這些提供者，因此請透過 Google、GitHub 或 Apple 登入來建立營運人員帳號，或設定郵件提供者。
>
> 在此檢查存在之前建立的帳號尚未記錄該證明，因此現有營運人員在重設密碼或使用其中一個提供者登入一次後，即可重新取得存取權。
>
> 當營運網域中缺乏該證明的帳號首次以該方式證明其地址時，Tuist 會移除其密碼、通行金鑰以及與組織單一登入提供者的連結，並將其從瀏覽器與 CLI 登出，因為註冊該地址的人未必擁有該地址。對此類帳號執行密碼重設也會產生相同效果，差別在於會設定新密碼。帳號上設定的驗證器應用程式會保留；若非所有者所設，請代為移除。營運網域外的已確認帳號會保留其憑證。所有者可繼續透過提供者登入，或透過重設設定新密碼。
>
> 由 SCIM 佈建建立或重新命名的帳號，在其所有者提供證明前沒有任何證明。


- **錯誤 (`/ops/errors`)：** 你可以檢視應用程式中發生的非預期錯誤。這有助於除錯並了解問題所在，若你遇到問題，我們可能會要求你與我們分享此資訊。
- **儀表板 (`/ops/dashboard`)：** 你可以檢視提供應用程式效能與健康狀況洞察的儀表板（例如記憶體用量、執行中的程序、請求數量）。此儀表板對於判斷你所使用的硬體是否足以處理負載相當有用。
