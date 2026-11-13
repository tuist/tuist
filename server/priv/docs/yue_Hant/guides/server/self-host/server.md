---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解如何將 Tuist server 部署到你嘅基礎設施。"
}
---
# 伺服器 {#server}

我哋為需要更多基礎設施控制權嘅組織提供 Tuist 伺服器嘅自託管版本。此版本允許你喺自己嘅基礎設施上託管 Tuist，確保你嘅數據保持安全同私隱。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要合法有效嘅付費授權。Tuist 嘅本地部署版本僅適用於 Enterprise 計劃嘅組織。如果你對此版本感興趣，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊式自託管快取節點技術已唔適用於新安裝。請使用 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 了解當前嘅自託管快取基礎設施。
>
> 現有部署仍可參考 GitHub Markdown 檢視器中嘅舊版源文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) 同 [快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像頻道發布：**canary**（每次提交到 `main`）、**release candidate**（每週一切割，測試一週）同 **stable**（下週一提升）。只有穩定版本會移動 `:latest` 並默認解析；canary 同 release candidate 係 GitHub 預發布版本，你需要通過固定標籤來選擇加入。伺服器同 Kura 遵循相同嘅每週發布列車，與 <.localized_link href="/cli/release/channels">Tuist CLI 嘅發布時間表</.localized_link> 同步。

我哋遵循 [語義化版本](https://semver.org/) 以確保可預測嘅版本管理同兼容性。主要版本用於標記 Tuist 伺服器中需要與自託管用戶協調嘅破壞性變更；你唔應該預期我哋會經常使用它，如果真係需要，请放心，我哋會協助你順利過渡。

請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布頻道</.localized_link> 頁面，了解每個頻道嘅切割方式、如何喺你嘅部署中固定一個頻道，以及建議嘅策略：讓生產環境停留喺變動緩慢嘅穩定線路，同時讓預發環境測試即將到來嘅發布。

## 瀏覽器會話升級 {#browser-session-upgrade}

瀏覽器會話喺七日内無認證頁面請求或 LiveView 互動後過期，且最遲唔超過認證後 30 日。「記住我」會恢復相同嘅伺服器端會話，但無法延長任何一個截止日期。活動每分鐘檢查一次，因此閒置會話可能提前最多 59 秒過期。WebSocket 心跳、自動重新連接同背景更新唔會刷新活動。這些截止日期唔會改變機器憑證或 API 令牌嘅有效期。

喺啟動升級後嘅應用程序進程之前，運行附加嘅 `users_tokens` 遷移。現有記錄唔會回填：它們嘅創建時間限制了不活動同絕對過期時間，並且喺訪問強制 SSO 嘅組織之前必須重新認證。回調嘅提供者、頒發者或已驗證嘅 Workspace，以及自定義 SSO 連接存儲喺伺服器端，並與組織嘅當前設置進行比較。關聯賬戶唔係會話認證證明。

喺將策略視為強制執行之前，升級每個提供服務嘅 Web 副本。舊版二進制文件仍然可以接受其以前嘅 60 日會話，並且唔會強制執行新嘅 LiveView 邊界；混合版本喺模式上兼容，但策略上唔等效。預計用戶需要重新登錄。回滾到舊版二進制文件會削弱這些控制；如果必須進行模式回滾，請喺刪除新字段之前停止所有讀取它們嘅二進制文件。切勿延長舊會話或推斷來源以避免重新認證。

## 認證器應用程式 MFA {#authenticator-app-mfa}

伺服器包含原生認證器應用程式（TOTP）雙因素認證。儀表板尚未鏈接到它；後續版本會添加設置入口點。它唔需要激活標誌、託管服務依賴性或身份提供者憑證：只需要 PostgreSQL、下面嘅遷移、TOTP 認證器，以及由所有服務副本共享嘅穩定加密密鑰（`TUIST_SECRET_KEY_ENCRYPTION`，回退到 `TUIST_SECRET_KEY_BASE`）。保持伺服器同認證器時鐘同步。MFA 驗證及其每五分鐘五次失敗代碼嘅共享配額使用 PostgreSQL 行鎖，而唔係 Redis。

設置需要喺最近五分鐘内登錄，將設置密鑰輸入 TOTP 認證器應用程式，並確認應用程式生成嘅代碼。十個單次使用嘅恢復代碼僅顯示一次；請安全存儲它們。禁用該因素也需要最近嘅登錄以及未使用嘅認證器或恢復代碼。更改因素會撤銷其他瀏覽器會話。重置密碼唔會移除 MFA，並且此實現唔提供僅電子郵件或管理員繞過丟失因素嘅方法。

一旦註冊，每次新嘅瀏覽器登錄——包括聯合登錄——都需要原生第二因素，然後才能接收會話或完成基於瀏覽器嘅 CLI/設備授權。直接密碼同 Apple API 登錄會拒絕已註冊用戶，並指示他們使用瀏覽器登錄。已註冊用戶嘅新電子郵件代理聲明需要經過 MFA 驗證嘅瀏覽器會話；僅郵箱嘅舊版聲明會被拒絕。現有 API 令牌、機器憑證、工作負載身份及其續訂規則保持不變。這是可選嘅每用戶支持，唔係組織範圍嘅 MFA 強制要求，亦唔係對身份提供者自身 MFA 策略嘅驗證。組織 SSO 仍然需要正確配置嘅提供者/頒發者，加上原生因素。

註冊、登錄、使用恢復代碼或禁用 MFA 都唔需要電子郵件。因素變更通知係盡力而為；交付失敗唔會撤銷已完成嘅變更。

喺使用新二進制文件之前，先運行獨立嘅附加 `user_mfa`/`users_tokens.mfa_verified_at` 遷移。TOTP 密鑰使用現有嘅 Vault 加密密鑰；請保留該密鑰及其備份。喺允許 MFA 註冊之前，完成 **所有認證服務副本** 嘅升級。舊版二進制文件可以繞過原生 MFA，因此喺註冊之後，它們唔係符合策略嘅回滾目標。刪除 MFA 架構會破壞註冊同恢復狀態；請先停止讀取器並保留加密備份。混合版本架構兼容性並唔證明 MFA 或瀏覽器會話控制已強制執行。

## OAuth 升級同回滾邊界 {#oauth-upgrade-and-rollback-boundary}

OAuth 實體緩存移除需要對現有安裝進行分階段升級。喺部署停止 OAuth 緩存失效嘅版本之前，首先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 嘅權威讀取兼容版本部署到 **每個 OAuth 讀取器同寫入器**。此兼容階段首次出現喺 **1.355** 發布線中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升，生產部署應使用穩定嘅 `1.355.x` 版本。1.354 或更早版本嘅安裝必須喺升級到包含移除功能嘅後續版本之前完成此階段。保持 1.355 線僅用於兼容：唔好將失效移除反向移植到其中。

原始兼容提交亦可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 使用。另一個映像僅喺保留權威讀取 **並保留舊版失效** 同時舊消費者仍然存在時，才適合作為兼容階段。喺提供流量之前，運行該階段嘅常規數據庫遷移，包括刷新令牌查找索引。

檢查每個環境中嘅所有 Web 副本、後台工作器、計劃任務同單獨固定嘅處理器映像。等待兼容推出完成，並喺移除失效之前驗證沒有剩餘嘅緩存讀取二進制文件。唔好讓浮動映像標籤喺自動升級期間跳過此階段。沒有舊消費者嘅全新安裝唔需要中間部署。

> [!WARNING]
> **保留權威讀取回滾目標**
>
> 移除失效後，普通滾動回滾必須針對 #14040 或另一個權威讀取版本。即使每個無失效進程都已停止，保留嘅 OAuth 緩存條目仍可能過時，並且重新啟動嘅緩存讀取副本可以從對等節點導入它們。
>
> 進一步回滾需要停止並排空 **所有** 無失效 OAuth 消費者，然後喺啟動任何緩存讀取消費者之前清除或替換 **每個** 保留嘅 Boruta 緩存參與者。防止保留嘅參與者重新加入。僅排空入口或僅重新啟動 Web 副本係唔足夠嘅；請與您嘅 Tuist 支持聯繫人協調此恢復，而唔係自動清除緩存或回滾數據庫遷移。

## 多副本集群 {#multi-replica-clustering}

支持嘅多副本 Web 部署需要 Erlang 集群來實現跨副本 Phoenix PubSub 同 Oban PG 通知，而唔係作為認證權威。當 `server.cluster.enabled` 為 false 時，圖表會拒絕多個副本，包括可以增長超過一個副本嘅自動縮放器。以前接受嘅非集群部署必須計劃此升級，而唔係繞過保護措施。喺更改成員資格之前，完成 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括失效移除。

使用您嘅密鑰管理器喺發布命名空間中創建私有 Cookie Secret，然後配置其名稱同密鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵並由所有參與嘅 Web 副本共享。切勿使用嵌入喺發布映像中嘅 Cookie：擁有分發 Cookie 授予喺其節點上遠程執行嘅權限。分佈式發布啟動現在拒絕缺少私有 `RELEASE_COOKIE` 或無效端口，包括明確配置嘅 `RELEASE_DISTRIBUTION=name` 或 `sname` 而沒有 DNS 發現。非圖表部署還必須一致地配置 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 同 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

使用普通嘅伺服器連接 `helm upgrade`，將 `cookieExistingSecret` 留空會創建一個 Cookie Secret，並喺後續升級中重用其當前值。離線 `helm template`、Argo CD 同其他沒有實時 Secret 查找嘅 GitOps 渲染器無法保留該生成值；它們必須使用由單獨管理嘅穩定 Secret 支持嘅 `cookieExistingSecret`。唔好更改 Cookie 密鑰來隱式輪換活動集群。Cookie 輪換需要協調每個參與者嘅遷移/重新啟動；僅更新 Secret 唔會更新現有進程。

從映像烘焙 Cookie 進行嘅第一次推出會形成單獨嘅新舊成員島嶼，直到所有 Web 副本都使用私有 Secret。為實時更新規劃遷移窗口。後續滾動部署會形成混合版本集群，因此請喺實際新舊版本之間限定 PubSub、Oban 通知同對等替換。這些通知唔係持久交付保證。喺回滾兼容版本時，保留權威讀取回滾映像並保留相同嘅私有 Cookie。

僅允許喺受信任嘅伺服器對等節點之間使用 EPMD（TCP 4369）同配置嘅分發端口，切勿來自租戶工作負載或公共網絡。驗證您環境中嘅實際入口/出口隔離；渲染 NetworkPolicy 並唔證明強制執行或後端可達性。喺連續負載下嘅雙副本金絲雀必須通過加入、滾動替換同故障/恢復才能提升。DNS 用於發現對等節點，而唔係喺瞬態失敗或部分響應時斷開健康節點；真實節點丟失同 OTP 分區預防仍然適用。libcluster 可能仍會為保留回調記錄成功嘅「斷開」操作而唔關閉連接；從節點上線/下線事件或 `Node.list()` 建立實際成員資格，而唔係僅依賴該日誌行。

## 持續部署 {#continuous-deployment}

我哋建議將生產環境固定喺一個穩定嘅次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），咁樣日常升級只會包含回溯修復。穩定版本線會喺每個星期一 UTC 時間 06:00，經過為期一週嘅候選發布渠道浸泡測試後推出；喺金絲雀或當前候選發布標籤上嘅預演環境可以喺問題影響到你嘅用戶之前捕獲回歸。有關推薦嘅固定策略，請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布渠道</.localized_link>。

如果你希望喺唔觸及清單文件嘅情況下吸收新推出嘅穩定功能，請固定 `:latest`。該標籤會喺每個星期一早上更新一次，因此請相應安排你嘅部署窗口。以下係一個 GitHub Actions 工作流程示例，會按照該頻率檢查並部署最新嘅穩定映像：

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

## 受信任網絡訪問 {#network-trusted-access}

自託管安裝可以允許受信任網絡上嘅開發人員無需登錄即可提交見解、使用緩存，或兩者兼備。儀表板同管理仍然需要身份驗證。

僅啟用你需要嘅功能：

| 伺服器環境變量 | 允許無需登錄 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交構建同測試見解 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀取同寫入緩存嘅構建輸出 |

這兩個設置默認都係 **關閉**，彼此獨立，並適用於實例範圍內嘅所有帳戶同項目，包括私有項目。它們喺託管版 Tuist 上不可用，亦唔能取代自託管許可證。

當 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 未設置時，先前嘅 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍作為兼容性回退保留。

> [!WARNING]
> 僅喺強制執行嘅辦公網絡或 VPN 邊界後面啟用這些設置。任何能夠訪問已啟用端點嘅人都可以提交報告，或者喺啟用緩存訪問時讀取同覆蓋緩存輸出。這可能導致偽造遙測數據、緩存投毒同容量耗盡。報告響應亦可能洩露私有項目句柄同構建系統。Tuist 唔會驗證 VPN 成員資格，亦唔會將轉發嘅 IP 頭部視為成員資格證明。

### 配置實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口，將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器同任何 Bazel BES 入口限制喺你嘅受信任網絡內。
2. 喺升級客戶端之前，先升級每個伺服器同 Kura 副本。保持 Kura 身份驗證啟用狀態，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑據；禁用它會繞過這些限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管緩存指南</.localized_link> 配置你嘅緩存端點。
3. 喺每個相關嘅 Tuist 伺服器副本上設置上述所需變量，然後重新啟動或重新部署它們。只有確切值 `true` 才能啟用設置。儀表板上沒有切換開關，Kura 亦沒有單獨標誌。

### 配置客戶端 {#network-trusted-client-configuration}

喺每個兼容嘅客戶端上配置最終嘅自託管伺服器 URL 同項目。當缺少憑據時，客戶端會自動發現哪些功能已啟用；無需客戶端選擇加入。發現過程唔會跟隨重定向。現有憑據會繼續使用，無效或刷新失敗嘅憑據會導致錯誤，而唔會回退到匿名模式。請重新登錄或明確登出以恢復。

喺啟用見解訪問之前，將所有共享憑據嘅工具升級到能夠保留損壞或被拒絕憑據、拒絕無法讀取嘅憑據目錄，並從未經簽名嘅報告中省略 Git 來源嘅版本。舊版工具可能會刪除憑據並無意中允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏發現支持或回滾到較舊版本，客戶端必須進行身份驗證。先前嘅 `TUIST_NETWORK_TRUSTED_PUBLISHING` 客戶端設置不再適用。

- **見解：** 僅提交已完成嘅 Xcode、Gradle、Elixir/Mix 同 Bazel 報告，唔包括歸檔、附件、覆蓋率、分片規劃或現有報告訪問權限。參與者聲明未經驗證；未經簽名嘅遙測數據唔會驅動可信測試證據或自動化。有關客戶端設置同隱私詳情，請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 同 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南。
- **緩存：** 支持 CLI 編譯/模塊緩存、Bazel 緩存同 Gradle 任務緩存。緩存清除同遠程資產下載仍然需要憑據。不支持嘅客戶端必須繼續進行身份驗證。
- **Bazel：** 報告需要明確指定 `TUIST_BAZEL_BES_BACKEND` 同兼容嘅 Kura。緩存同報告選項係獨立啟用嘅。更改憑據或任一設置後，請重新運行 `tuist bazel setup`；更改編譯緩存配置後，請重新運行 `tuist cache config`。

報告請求限制為每個項目 8 MB、每分鐘 60 個請求同每日 10,000 個請求。對於具有多個副本嘅部署範圍配額，請配置共享 Valkey；否則限制係按進程計算。如果配置嘅共享配額後端不可用，未經簽名嘅報告將被拒絕。亦請添加入口連接、正文同速率限制。

### 禁用受信任網絡訪問 {#disable-network-trusted-publishing}

將相關變量設置為 `false`，然後重新啟動 **每個相關嘅伺服器副本**。舊副本喺被替換之前可以繼續接受無需憑據嘅請求。喺最後一個副本切換後 60 秒內，新請求嘅緩存訪問將停止；進行中嘅傳輸唔會被取消。如果需要立即撤銷，請先喺入口處阻止流量。現有報告保留其通常嘅可見性同保留策略，經過身份驗證嘅客戶端繼續正常工作。

## 運行時要求 {#runtime-requirements}

本節概述喺你嘅基礎設施上託管 Tuist 伺服器嘅要求。

### 兼容性矩陣 {#compatibility-matrix}

Tuist 伺服器已經過測試，並與以下最低版本兼容：

| 組件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能必需 |

### 運行 Docker 虛擬化映像 {#running-dockervirtualized-images}

我哋通過 [GitHub 容器註冊表](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像形式分發伺服器。

要運行它，你嘅基礎設施必須支持運行 Docker 映像。請注意，大多數基礎設施提供商都支持它，因為它已成為喺生產環境中分發同運行軟件嘅標準容器。

### Postgres 數據庫 {#postgres-database}

除咗運行 Docker 映像外，你還需要一個 [Postgres 數據庫](https://www.postgresql.org/) 來存儲關係數據。大多數基礎設施提供商都喺其產品中包含 Postgres 數據庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 同 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅架構遷移。


### ClickHouse 數據庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來存儲同查詢大量分析數據。對於構建見解等功能，**必須**使用 ClickHouse。你可以選擇自行託管 ClickHouse 或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅 ClickHouse 架構遷移。

捆綁嘅 Docker Compose 同 Helm 嵌入式 ClickHouse 配置將 ClickHouse 文本日誌級別從映像嘅 `trace` 默認值降低到 `information`，這係 `system.text_log` 體積嘅主要來源。兩者亦可以限制 ClickHouse 自身嘅 `system.*` 運營日誌表，否則這些表係無邊界嘅，但此功能默認為關閉 — 請參閱下文。外部 ClickHouse 部署應直接喺其 ClickHouse 服務中配置這些運營日誌。

#### ClickHouse 複製拓撲 {#clickhouse-replication-topology}

Tuist 背後嘅多副本 ClickHouse 僅喺 ClickHouse Cloud 上受支持。自行管理嘅 ClickHouse 為單副本。

攝取遷移會生成一個普通嘅 `MergeTree` 引擎。喺 Cloud 上，這會透明地變為 `SharedMergeTree`，因此寫入會進入共享對象存儲，且任何副本數量均可工作。喺自行管理嘅 ClickHouse 上，`MergeTree` 僅寫入一個副本嘅本地磁盤；多副本設置要么靜默地喺副本之間拆分攝取，要么拒絕 CREATE 並顯示 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.`，具體取決於連接用戶如何設置 `database_replicated_allow_only_replicated_engine`。

喺自行管理嘅 ClickHouse 上運行一個帶有一個副本嘅分片，並定期備份 ClickHouse 數據目錄。如果節點丟失，則沒有第二個副本可以回退。

#### 限制運營日誌保留 {#capping-operational-log-retention}

保留策略可應用於 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 同 `system.part_log`。

喺已有數據嘅實例上啟用此功能係一次性且不可逆嘅步驟，這就是為什麼兩個捆綁包都沒有為你執行此操作。任何保留窗口都會導致這些表定義不再匹配其配置，因此 ClickHouse 會將每個表重命名並啟動一個新表，如 [被取代嘅日誌表](#superseded-log-tables) 中所述。留下嘅世代保存迄今為止累積嘅所有內容，且本身不帶有任何保留策略，因此除非你喺同一步驟中回收它，否則它將永久保留喺磁盤上，而新窗口僅限制從那時起寫入嘅行。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

該單一 `helm upgrade` 係自包含嘅，因為將 `ttlDays` 從空白設置為特定值會添加掛載並滾動 ClickHouse pod：它會重新啟動，取代表，然後升級後作業會刪除它們。使用 `helm upgrade --wait` 進行部署，以便喺作業運行之前滾動 pod；否則，世代會喺作業檢查之後出現，而下一次 `helm upgrade` 會改為回收它們。

使用 Docker Compose 時，取消註釋 `docker-compose.yml` 中 `clickhouse` 服務上嘅 `clickhouse-log-ttl.xml` 卷，並喺 `.env` 中設置這兩個變量：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，你可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，以便後續嘅 ClickHouse 升級不會自行丟棄歷史記錄。

#### 被取代嘅日誌表 {#superseded-log-tables}

ClickHouse 喺啟動時檢查每個系統日誌表是否仍然匹配其配置。如果不匹配，它會將現有表重命名為 `system.<name>_0`，然後係 `_1`、`_2` 等，並啟動一個新表。當你更改保留窗口或進行更改系統日誌架構嘅 ClickHouse 升級時，就會發生這種情況。

重命名表不會複製其數據，因此不會消耗額外嘅磁盤空間。被取代嘅表之後嘅情況取決於它所來自嘅表，因為它會保留被取代時刻活動表所具有嘅任何保留策略。第一次啟用保留時，被取代嘅表沒有任何保留策略，因此它會保存迄今為止累積嘅所有歷史記錄並無限期保留。隨後對窗口嘅更改會取代已帶有 TTL 嘅表，因此這些表會自行過期並留下一個空表。ClickHouse 永遠不會刪除表本身，因此喺長期運行嘅實例上，它們會以任一方式累積。

默認情況下會保留被取代嘅表，以便升級永遠不會自行丟棄運營歷史記錄。將策略設置為 `delete` 以改為刪除它們，這會喺 `docker compose up` 同每次 `helm upgrade` 時發生：

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

使用 Helm chart 時，將相同策略配置為一個值：

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

刪除被取代嘅表會回收其磁盤空間。活動表永遠不會被觸及，自被取代以來寫入嘅行也不會被觸及。

要喺不更改策略嘅情況下一次性回收空間，請手動刪除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 數據庫使用 `Atomic` 引擎，這會將普通 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（默認為八分鐘）。`SYNC` 會立即刪除數據，這正是你喺因磁盤滿而刪除這些表時所需要嘅。


### 存儲 {#storage}

你還需要一個解決方案來存儲文件（例如框架同庫二進制文件）。Tuist 伺服器支持 S3 兼容存儲同 Azure Blob Storage 用於伺服器擁有嘅工件。

> [!TIP]
> **優化緩存**
>
> 如果你嘅目標主要係減少緩存延遲，你可能不需要自行託管整個伺服器。你可以喺靠近你嘅 CI 或開發者網絡嘅地方部署自行託管嘅 Kura 節點，並將它們連接到託管嘅 Tuist 伺服器或你自行託管嘅伺服器。
>
> 請參閱 <.localized_link href="/guides/cache/self-host">自行託管緩存指南</.localized_link>。


### 自行託管嘅 Kura 節點 {#self-hosted-cache-nodes}

要喺自行託管嘅 Tuist 伺服器上使用自行託管嘅 Kura 節點：

1. 喺 Tuist 伺服器上配置 `KURA_CONTROL_PLANE_CLIENT_ID` 同 `KURA_CONTROL_PLANE_CLIENT_SECRET`。客戶端 ID **必須係 UUID**。使用 <.localized_link href="/guides/cache/self-host#control-plane-client">自行託管緩存指南</.localized_link> 中嘅命令生成 UUID 同隨機密鑰，並將它們存儲喺你嘅部署密鑰中。
2. 按照 <.localized_link href="/guides/cache/self-host">自行託管緩存指南</.localized_link> 部署 Kura 節點，使用相同嘅控制平面憑據。
3. 使用 `KURA_REGISTRATION_URL` 同 `KURA_ADVERTISED_HTTP_URL` 配置每個 Kura 節點。註冊心跳會告訴伺服器它可以向 CLI 宣傳哪些就緒且面向客戶嘅 Kura 端點。

## 配置 {#configuration}

服務嘅配置係透過環境變數喺運行時完成。鑑於這些變數嘅敏感性，我哋建議加密並將它們存儲喺安全嘅密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變數，確保它們永遠不會顯示喺日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要嘅變數會喺啟動時進行驗證。如果缺少任何變數，啟動將會失敗，錯誤訊息將詳細說明缺失嘅變數。


### 許可證配置 {#license-configuration}

作為本地部署用戶，你會收到一個需要作為環境變數公開嘅許可證。該許可證用於驗證部署並確保服務喺協議條款範圍內運行。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務級別協議後提供嘅許可證。接受標準許可證密鑰或用於隔離網絡環境（伺服器無法聯繫外部服務）嘅 base64 編碼證書。 | 是 | | `******` |

> [!WARNING]
> **到期日期**
>
> 許可證有到期日期。如果許可證喺少於 30 天內到期，用戶喺使用與伺服器交互嘅 Tuist 命令時會收到警告。如果你有興趣續訂許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境配置 {#base-environment-configuration}

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從互聯網訪問實例嘅基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密信息嘅密鑰（例如 cookie 中嘅會話） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於生成哈希密碼嘅 Pepper | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於生成隨機令牌嘅密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於敏感數據 AES-GCM 加密嘅 32 字節密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | 當為 `1` 時，它會配置應用程序使用 IPv6 地址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程序使用嘅日誌級別 | 否 | `info` | [日誌級別](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 你嘅 GitHub 應用嘅 slug，取自 `https://github.com/apps/<slug>`。安裝應用所需。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用解鎖額外功能（例如發布自動 PR 評論）嘅 base64 編碼私鑰 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用解鎖額外功能（例如發布自動 PR 評論）嘅私鑰。**我哋建議改用 base64 編碼版本，以避免特殊字符帶來嘅問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電郵地址以 `@<this-domain>` 結尾並證明擁有該地址控制權嘅用戶，可以訪問運營 URL（`/ops/*`）。如果未設置，任何人都無法訪問。請參閱 [運營](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 喺儀表板導航欄中顯示為徽章嘅標籤，用於識別伺服器實例（例如版本號或分支名稱） | 否 | 開發環境中嘅 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用 Web 伺服器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許無需登入即可提交構建和測試洞察。請參閱 [網絡可信訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許無需登入即可讀取和寫入緩存。請參閱 [網絡可信訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 用於發送追蹤數據嘅 OpenTelemetry Collector gRPC 端點 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 用於推送日誌嘅 Loki 兼容端點嘅基礎 URL（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **透過 HTTPS 提供應用程序服務**
>
> 會話 Cookie 被標記為 `Secure`，因此瀏覽器會喺普通 `http://` 上丟棄它們，導致用戶無法登入。請喺伺服器前端終止 TLS（使用內部 CA 證書嘅反向代理即可），並將 `TUIST_APP_URL` 設置為 `https://` URL，即使係內部或僅限 VPN 嘅部署亦然。

### 數據庫配置 {#database-configuration}

以下環境變數用於配置數據庫連接：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 訪問 Postgres 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程序表使用嘅 PostgreSQL 模式。當你的數據庫策略不允許使用 `public` 模式時設置此項。模式名稱必須係未加引號嘅 PostgreSQL 標識符。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用嘅可選 Postgres URL。當 `DATABASE_URL` 指向權限較窄嘅運行時角色時，將其設置為所有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程序表權限嘅運行時 Postgres 角色。當 Web 伺服器不應以模式所有者身份連接時，請將此項與 `TUIST_MIGRATION_DATABASE_URL` 配合使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 訪問 ClickHouse 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 當為 true 時，它使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連接數據庫。除非啟用 `TUIST_DATABASE_SSL_VERIFY`，否則不會驗證伺服器證書 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 當為 true 時，數據庫伺服器證書必須鏈接到受信任嘅 CA 並匹配 `DATABASE_URL` 主機。需要 `TUIST_USE_SSL_FOR_DATABASE`。我哋建議啟用此項 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 包含用於驗證數據庫伺服器嘅 CA 證書嘅 PEM 文件路徑。如果未設置，則使用操作系統嘅信任存儲 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 連接池中保持打開嘅連接數 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出嘅所有連接是否超過隊列間隔嘅時間間隔（以毫秒為單位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 隊列中嘅閾值時間（以毫秒為單位），池使用該時間來確定是否應開始丟棄新連接[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩存刷新之間嘅時間間隔（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新之前嘅最大 ClickHouse 緩存大小（以字節為單位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要運行嘅 ClickHouse 緩存進程數 | 否 | `5` | `5` |

默認情況下，Tuist 會加密數據庫連接但不驗證伺服器證書，因此網絡路徑上嘅攻擊者可以冒充數據庫。設置 `TUIST_DATABASE_SSL_VERIFY=1` 以進行驗證。如果你嘅提供商使用自己嘅 CA 簽署證書（如 Amazon RDS 和 Google Cloud SQL），請下載其 CA 捆綁包，將其掛載到容器中，並將 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向它。`DATABASE_URL` 中嘅主機必須與證書中嘅名稱或 IP 地址匹配。啟用驗證後，未能通過這些檢查嘅證書會導致每個數據庫連接失敗，因此啟用後請檢查伺服器日誌中是否有 `Bad Certificate` 或 `Unknown CA`。

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，如果模式尚不存在，發布遷移會在運行 Ecto 遷移鏈之前創建該模式。如果遷移角色無法創建模式，請預先創建模式並使遷移角色成為其所有者。

Tuist 通過設置會話 `search_path` 將連接指向自定義模式。一些池化或代理嘅 Postgres 設置（例如 PgBouncer，或限制啟動參數嘅托管數據庫）不應用此設置，會話會回退到 `public`，這在遷移期間會顯示為 `permission denied for schema public`。當通過此類設置連接時，請將模式固定在角色本身，以便無論代理如何，每個會話都從該模式開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 身份驗證環境配置 {#authentication-environment-configuration}

我哋透過 [身份提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進身份驗證。要利用此功能，請確保所選提供者所需嘅所有環境變數都存在於伺服器環境中。**缺少變數** 將導致 Tuist 跳過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登入以及自助註冊係內置並默認啟用嘅。在你需要要求使用身份提供者嘅實例上（例如，強制執行 SSO 時），你可以完全關閉它們。這會從登入體驗中刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉每個匹配嘅伺服器端端點，包括 CLI 使用嘅電子郵件/密碼端點（`tuist auth`）。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登入和註冊。設置為 `0` 以從登入頁面刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉匹配嘅伺服器端端點 | 否 | `1` | `0` |

#### 禁用已配置嘅身份提供者 {#disabling-a-configured-identity-provider}

默認情況下，只要配置了提供者，它就會作為登入選項出現。要保持提供者配置（其憑據保持設置）同時從登入和註冊頁面中刪除它，請將匹配嘅開關設置為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登入回調，因此該方法完全不可用。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入（請參閱 [GitHub](#github) 部分了解為什麼 App 共享其憑據以進行登入） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登入 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 已配置嘅 Okta 提供者是否顯示為登入選項 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登入 | 否 | `1` | `0` |

#### GitHub {#github}

我哋建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行身份驗證，但你也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保伺服器環境中包含 GitHub 指定嘅所有必要環境變數。缺少變數會導致 Tuist 忽略 GitHub 身份驗證。要正確設置 GitHub app：
- 在 GitHub app 嘅一般設置中：
    - 複製 `Client ID` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 創建並複製一個新嘅 `client secret` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設置為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以係你伺服器嘅 IP 地址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀寫
  - 帳戶：
    - 電子郵件地址：只讀

在 `Permissions and events` 嘅 `Account permissions` 部分中，將 `Email addresses` 權限設置為 `Read-only`。

然後你需要在運行 Tuist 伺服器嘅環境中公開以下環境變數：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式嘅客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式嘅客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登入。你為平台集成（PR 評論等）配置嘅 GitHub App 會共享其客戶端憑據以進行登入，因此它否則會作為登入選項出現。設置為 `0` 以保留 App 同時從登入頁面刪除 GitHub | 否 | `1` | `0` |

#### Google {#google}

你可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設置與 Google 嘅身份驗證。為此，你需要創建一個類型為 OAuth 客戶端 ID 嘅新憑據。創建憑據時，選擇「Web Application」作為應用程式類型，將其命名為 `Tuist`，並將重定向 URI 設置為 `{base_url}/users/auth/google/callback`，其中 `base_url` 係你託管服務運行嘅 URL。創建 app 後，複製客戶端 ID 和密鑰，並將它們分別設置為環境變數 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意屏幕範圍**
>
> 你可能需要創建一個同意屏幕。當你這樣做時，請確保添加 `userinfo.email` 和 `openid` 範圍並將 app 標記為內部。


#### Okta {#okta}

你可以通過 [OAuth 2.0](https://oauth.net/2/) 協議啟用與 Okta 嘅身份驗證。你必須按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些說明</.localized_link> 在 Okta 上 [創建一個 app](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設置 Okta 應用程式期間獲得客戶端 ID 和密鑰後，你需要設置以下環境變數：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於向 Okta 進行身份驗證嘅客戶端 ID。該數字應該係你嘅組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於向 Okta 進行身份驗證嘅客戶端密鑰 | 是 | | |

數字 `1` 需要替換為你嘅組織 ID。這通常係 1，但請檢查你嘅數據庫。

### 存儲環境配置 {#storage-environment-configuration}

 Tuist 需要存儲空間來存放通過 API 上傳嘅構件。**必須配置其中一種受支持嘅存儲解決方案**，Tuist 才能有效運行。

設置 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇伺服器構件後端：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 伺服器構件存儲後端。對於 S3 兼容存儲使用 `s3`，對於 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 兼容存儲 {#s3compliant-storages}

你可以使用任何 S3 兼容存儲提供商來存儲構件。以下環境變數係對存儲提供商進行身份驗證和配置集成所必需嘅：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於向存儲提供商進行身份驗證嘅訪問密鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於向存儲提供商進行身份驗證嘅秘密訪問密鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 存儲桶所在嘅區域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 存儲提供商嘅端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 將存儲構件嘅存儲桶名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | 用於驗證 S3 HTTPS 連接嘅 PEM 編碼 CA 證書。適用於具有自簽名證書或內部證書頒發機構嘅隔離環境。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立與存儲提供商連接嘅超時時間（以毫秒為單位） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從存儲提供商接收數據嘅超時時間（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 連接池到存儲提供商嘅超時時間（以毫秒為單位）。使用 `infinity` 表示無超時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連接嘅最大空閒時間（以毫秒為單位）。使用 `infinity` 以保持連接永久活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個池嘅最大連接數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用嘅連接池數量 | 否 | 系統調度器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連接到存儲提供商時使用嘅協議（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將存儲桶名稱構建為子域（虛擬主機） | 否 | `false` | `1` |

> [!NOTE]
> **來自環境變數嘅 AWS Web 身份驗證**
>
> 如果你嘅存儲提供商係 AWS，並且你想使用 Web 身份令牌進行身份驗證，你可以將環境變數 `TUIST_S3_AUTHENTICATION_METHOD` 設置為 `aws_web_identity_token_from_env_vars`，Tuist 將使用常規 AWS 環境變數採用該方法。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請按照 [這些文檔](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 獲取 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設置為 `https://storage.googleapis.com`。其他環境變數與任何其他 S3 兼容存儲相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，設置 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並配置 Azure 存儲帳戶憑據：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 存儲帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 嘅存儲帳戶訪問密鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 存儲伺服器構件嘅容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略以使用 `https://<account>.blob.core.windows.net` | 否 | 從帳戶名稱派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 嘅 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm chart 時，設置 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。Chart 嘅頂層 `objectStorage` 設置保持 S3 兼容，因為可選嘅緩存和註冊表鏡像工作負載仍然需要 S3 兼容存儲。如果禁用這些工作負載且伺服器使用 Azure Blob，請設置 `objectStorage.mode=external` 並將外部對象存儲端點和憑據留空，以避免部署嵌入式 MinIO 服務。

#### 構件保留 {#artifact-retention}

自託管實例預設禁用構件清理。每種受支援嘅構件類型都有自己嘅環境變數。將變數設置為正整數天數以啟用該構件類型嘅清理。將變數留空或不設置只會禁用該構件類型嘅清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm chart 時，將相同嘅時間窗口配置為映射：

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

所有六個鍵都係可選嘅。此示例啟用了每種受支援嘅構件類型，並具有獨立嘅保留窗口。省略鍵或將其值留空以保持禁用該構件類型嘅清理。自託管保留窗口沒有 30 天嘅上限。配置嘅值如果不是正整數，會導致伺服器在啟動時失敗。

更改保留變數後重新啟動伺服器。每個排隊嘅自託管清理批次在刪除文件之前都會檢查當前配置，因此取消設置或清空變數，或者增加其窗口，也會在重新啟動後保護文件免受待處理作業嘅影響。

| 環境變數 | 從對象存儲中刪除嘅構件文件 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 緩存、舊版內容尋址存儲緩存、模塊緩存和 Gradle 緩存文件 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App 預覽構建和圖標 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 當前和舊版構建歸檔 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 存儲在已過期運行嘅構件前綴下嘅所有對象，包括結果包、調用記錄和會話歸檔 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片包 |

計劃清理僅刪除構件 blob。它保留相應嘅 PostgreSQL 和 ClickHouse 行，因此構建、測試、運行、預覽和分片元數據在其下載過期後仍可在儀表板中可見。此配置不會更改 ClickHouse 表保留規則。

### 電子郵件配置 {#email-configuration}

Tuist 需要電子郵件功能用於用戶身份驗證和事務性通知（例如，密碼重置、帳戶通知）。目前，**僅支援 Mailgun** 作為電子郵件提供商。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於向 Mailgun 進行身份驗證嘅 API 密鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件嘅域 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將出現在「發件人」字段中嘅電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用於用戶回覆嘅可選回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新用戶註冊嘅電子郵件確認。啟用時，用戶會自動確認並可以在註冊後立即登錄 | 否 | 如果未配置電子郵件則為 `true`，如果已配置電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅當你想發送電子郵件時才需要電子郵件配置變數。如果未配置，電子郵件確認會自動跳過

> [!NOTE]
> **SMTP 支援**
>
> 目前不提供通用 SMTP 支援。如果你需要為本地部署提供 SMTP 支援，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev) 討論你嘅需求。


> [!NOTE]
> **隔離網絡部署**
>
> 對於沒有互聯網訪問或電子郵件提供商配置嘅本地安裝，預設會自動跳過電子郵件確認。用戶可以在註冊後立即登錄。如果你已配置電子郵件但仍想跳過確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。要在配置電子郵件時要求電子郵件確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額和密碼重置鏈接**
>
> 配置電子郵件時，邀請郵件（創建、批量或重新發送）限制為每五分鐘每個收件人一封，並且每個組織和每個邀請者每小時補充 50 封嘅突發限制為 50 封。取消邀請不會恢復配額，邀請 API 會以 `429` 和 `Retry-After` 回應耗盡嘅配額。使用多個副本時，配置共享 Valkey 以實現部署範圍內嘅配額；如果已配置但不可用，邀請郵件會被拒絕。密碼重置鏈接在 15 分鐘後過期。


### Git 平台配置 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台集成</.localized_link> 以提供額外功能，例如自動在你嘅拉取請求中發布評論。

#### GitHub {#platform-github}

自託管嘅 Tuist 伺服器無法安裝運行於 `https://tuist.dev` 嘅 GitHub App。GitHub App 會綁定到註冊佢哋嘅伺服器，所以你嘅部署需要在 github.com 上擁有自己嘅 App。

##### 註冊 App {#platform-github-registering-the-app}

[創建一個由你嘅 GitHub 組織擁有嘅 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。你可以重用為身份驗證創建嘅 App，除非你創建嘅係 OAuth App。使用以下配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 嘅值：

| 設置 | 值 |
| --- | --- |
| 回調 URL | `YOUR_APP_URL/users/auth/github/callback` 同 `YOUR_APP_URL/integrations/github/authorize` |
| 設置 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重定向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任何隨機字符串。你會將其設置為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予以下存儲庫權限：

| 權限 | 訪問 |
| --- | --- |
| 內容 | 只讀 |
| 元數據 | 只讀 |
| Issues | 讀寫 |
| 拉取請求 | 讀寫 |
| Checks | 讀寫 |

同時授予 **成員：只讀** 組織權限。在 github.com 設置期間，Tuist 會檢查連接組織安裝嘅人係活躍嘅 GitHub 組織所有者，而不僅僅係可以訪問其中一個存儲庫嘅人。

訂閱 App 嘅 `Check run`、`Pull request` 同 `Issue comment` 事件。

保持 **安裝期間請求用戶授權 (OAuth)** 為禁用狀態，以便 GitHub 將安裝程序發送到設置 URL。Tuist 使用額外嘅 `/integrations/github/authorize` 回調啟動單獨嘅授權步驟以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝程序然後選擇一個 Tuist 組織；在 Tuist 中開始嘅安裝會保留其組織。

##### 配置伺服器 {#platform-github-configuring-the-server}

設置以下環境變數，然後重新啟動伺服器：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 嘅 slug，即其公共頁面 URL `https://github.com/apps/<slug>` 嘅最後一個路徑組件 | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式嘅客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式嘅客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式嘅 base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，因為後者對平台處理換行符嘅方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上配置嘅 webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **配置所有必需嘅 App 憑證**
>
> 組織集成頁面上嘅 **安裝 GitHub App** 按鈕會保持禁用狀態，直到設置好 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 同私鑰為止。數字 `TUIST_GITHUB_APP_ID` 亦需要用嚟驗證安裝所有權。安裝 URL 嵌入咗 App slug，所以如果缺少 `TUIST_GITHUB_APP_NAME`，特別係會產生一個 GitHub 回應 404 嘅連結。

伺服器重新啟動後，組織管理員按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 安裝 App 並將存儲庫連接到項目。

##### OIDC 身份驗證依賴此項 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份驗證</.localized_link> 會根據連接到你項目嘅存儲庫來解析 CI 令牌中嘅存儲庫聲明，而連接只能通過已安裝嘅 GitHub App 創建。在你嘅 CI 工作流使用 OIDC 進行身份驗證之前，請完成上述設置。

你嘅 Tuist 伺服器亦需要出站訪問權限以訪問你嘅 CI 供應商嘅 OIDC 頒發者，從而獲取其簽名密鑰：

| CI 供應商 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變數僅配置 Tuist 嘅 github.com App。要將 Tuist 與 GitHub Enterprise Server (GHES) 實例集成，組織管理員需切換到集成頁面上嘅 **企業伺服器** 標籤並輸入 GHES 基礎 URL — Tuist 會引導佢哋完成 GitHub 嘅 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)，以在佢哋嘅 GHES 實例上註冊一個新嘅 Tuist App。新 App 嘅憑證會按安裝加密存儲；無需額外嘅 `TUIST_GITHUB_APP_*` 環境變數。

#### Origin {#platform-origin}

自託管嘅 Tuist 伺服器需要自己嘅 Origin app，並配置好你部署嘅 URL 同簽名密鑰。為每個 Tuist 環境註冊單獨嘅 app，以便安裝同憑證保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支持 Ed25519 嘅 OpenSSL 生成 Ed25519 簽名密鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設置](https://cursor.com/codebase/settings/apps) 中創建一個 app。將 `origin-app-public.pem` 嘅內容註冊為其公共簽名密鑰。保密 `origin-app-private.pem`；你會將其提供給 Tuist 伺服器，而不是上傳到 Cursor。
3. 配置以下設置，將 `YOUR_APP_URL` 替換為你 Tuist 部署嘅 HTTPS 基礎 URL：

   | 設置 | 值 |
   | --- | --- |
   | 主頁 URL | `YOUR_APP_URL` |
   | 重定向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 複製註冊嘅 App ID，它以 `app_` 開頭。

Tuist 在安裝期間請求以下權限：

| 範圍 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 查找拉取請求及其當前 head commit。 |
| `repository:pull_requests:reviews:write` | 閱讀、發布同更新報告評論。Origin 包含相應嘅 review-read 權限。 |
| `repository:metadata:read` | 發現存儲庫並讀取其默認分支。由 Origin 自動授予。 |

唔好揀選可選嘅存儲庫 webhook 事件。安裝生命週期通知已經足夠；無需原始碼訪問權限、合併權限同 check-run 權限。

##### 配置伺服器 {#platform-origin-configuring-the-server}

設置以下環境變數，然後重新啟動伺服器：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設置中複製嘅 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 嘅完整內容，包括 `BEGIN PRIVATE KEY` 同 `END PRIVATE KEY` 行以及所有換行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私鑰存儲喺你部署嘅密鑰管理器中。保留其多行 PEM 格式；此設置不接受 base64 編碼嘅替換。切勿將密鑰提交到源代碼控制或喺日誌中公開。兩個變數必須屬於同一個註冊嘅 app。

你嘅 Tuist 伺服器需要對 `api.cursor.com` 嘅出站 HTTPS 訪問權限。Cursor 必須能夠將請求發送到 webhook URL，而管理員必須能夠喺瀏覽器中返回到重定向 URI。兩個註冊嘅 URL 必須與你部署嘅 HTTPS 基礎 URL 匹配。

##### 安裝 App {#platform-origin-installing-the-app}

伺服器重新啟動後，管理員打開 **設置 → 集成**，喺 Origin 下選擇 **連接**，並批准 app 對適當嘅 Origin 帳戶同存儲庫嘅訪問權限。整個流程中會保留 Tuist 組織。如果直接從 Origin 發起安裝，則會提示管理員登錄並選擇要連接嘅 Tuist 組織。然後佢哋選擇 **添加新項目連接** 以將 Tuist 項目鏈接到原生存儲庫。

請遵循 <.localized_link href="/guides/integrations/gitforge/origin">Origin 集成指南</.localized_link> 了解項目連接同結果上傳要求。安裝 app 不會啟動構建或測試工作流；這些工作流會繼續向你嘅 Tuist 伺服器報告結果。

#### Entire {#platform-entire}

自託管嘅 Tuist 伺服器需要自己嘅 Entire 插件，並配置好你部署嘅 URL 同簽名密鑰。Entire 插件需要合作夥伴註冊，因此喺開始之前請聯繫 Entire。為每個 Tuist 環境註冊單獨嘅插件，或者至少註冊單獨嘅簽名密鑰，以便安裝同憑證保持獨立。

##### 註冊插件 {#platform-entire-registering-the-plugin}

1. 使用支持 Ed25519 嘅 OpenSSL 生成 Ed25519 簽名密鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. 按照 Entire 嘅 [插件註冊指南](https://docs.entire.com/guides/api/plugins/register) 註冊插件。分享 `entire-plugin-public.pem` 嘅內容，或者發布它嘅 JWKS URL，作為插件嘅簽名密鑰。保密 `entire-plugin-private.pem`；你會將其提供給 Tuist 伺服器，而不是 Entire。
3. 配置以下 URL，將 `YOUR_APP_URL` 替換為你 Tuist 部署嘅 HTTPS 基礎 URL：

   | 設置 | 值 |
   | --- | --- |
   | 安裝後 URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL | `YOUR_APP_URL/webhooks/entire` |

4. 記下 Entire 確認嘅插件 slug 同佢提供嘅 webhook 簽名密鑰 URL。

請求以下權限：

| 權限 | 用途 |
| --- | --- |
| `contents:read` | 接收 Trail 事件並查找帶有 head commits 嘅開放同草稿 Trails。 |
| `checks:write` | 發布 Tuist gate。 |
| `findings:write` | 發布並解決失敗同不穩定嘅測試發現。 |
| `discussions:write` | 發布同更新摘要評論。未授予此權限嘅安裝仍然會收到 gate 同發現。 |

無需存儲庫寫入訪問權限。如果你向現有註冊添加權限，請要求 Entire 更新它並確認安裝已授予新權限。參見 Entire 嘅 [Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings) 同 [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) 合約。

##### 配置伺服器 {#platform-entire-configuring-the-server}

設置以下環境變數，然後重新啟動伺服器：

| 環境變數 | 描述 | 必填 | 預設值 | 例子 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認嘅插件 slug。 | 係 | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` 嘅完整內容，包括 `BEGIN PRIVATE KEY` 同 `END PRIVATE KEY` 行以及所有換行。 | 係 | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Entire 喺註冊時提供嘅 webhook 簽名密鑰 URL。 | 係 | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 當你透過 JWKS 註冊簽名密鑰時嘅金鑰 ID。 | 否 | | |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求嘅 Entire Core URL。 | 否 | `https://eu.auth.entire.io` | |

將私鑰儲存喺你部署嘅秘密管理器中，並保留其多行 PEM 格式。切勿將密鑰提交到源代碼控制或喺日誌中公開。使用 Tuist Helm chart 時，你可以改為將 PEM 儲存喺你嘅 1Password 保險庫中作為 `ENTIRE_PLUGIN/private_key`，並同時啟用 `server.config.entirePluginKey.enabled` 同 `server.config.managedSecrets`；項目同字段名稱可以透過 `server.config.entirePluginKey.item` 同 `.field` 進行配置。此映射不會設置 slug 或 webhook 簽名密鑰 URL。

你嘅 Tuist 伺服器需要對 Entire Core 同服務你存儲庫嘅區域性 Entire API 主機進行出站 HTTPS 訪問，全部位於 `entire.io` 或 `entire.com` 之下。Tuist 會驗證安裝收據同 webhook 簽名，鑄造短期嘅存儲庫範圍令牌，並且永遠唔會將令牌嵌入報告鏈接中。

##### 啟用集成 {#platform-entire-enabling-the-integration}

喺推出應用程序之前應用伺服器遷移，然後全局啟用 `entire_trails` 功能標誌以向所有帳戶或選定帳戶提供集成。啟用該標誌不會改變誰可以喺 Entire 中安裝插件；要喺插件所屬嘅 Entire 項目之外提供它，請聯繫你嘅 Entire 聯絡人以允許。該集成獨立於 Tuist 嘅 CI 執行配置。

如果你回滾應用程序，請保留 `entire_trail_reports` 表，以便稍後嘅升級可以恢復正在進行嘅發布。

管理員隨後按照 <.localized_link href="/guides/integrations/gitforge/entire">Entire 集成指南</.localized_link> 安裝插件並將存儲庫連接到項目。安裝插件不會啟動構建或測試工作流；這些工作流會繼續向你嘅 Tuist 伺服器報告結果。

## 本地測試 {#testing-locally}

我哋提供一個全面嘅 Docker Compose 配置，其中包含喺部署到你嘅基礎設施之前喺本地機器上測試 Tuist 伺服器所需嘅所有依賴項：

- PostgreSQL 15
- ClickHouse 26.5 用於分析
- ClickHouse Keeper 用於協調
- MinIO 用於兼容 S3 嘅存儲
- Kura 用於本地自託管緩存測試
- pgweb 用於數據庫管理

> [!CAUTION]
> **需要許可證**
>
> 運行 Tuist 伺服器（包括本地開發實例） legally 需要有效嘅 `TUIST_LICENSE` 環境變數。如果你需要許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速開始：**

1. 下載配置文件：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 配置環境變數：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   捆綁嘅 ClickHouse 服務接受以下可選嘅操作日誌控制：

   | 環境變數 | 描述 | 預設值 | 例子 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 同 `part_log`）嘅保留窗口（以天為單位） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 伺服器記錄器同 `system.text_log` 級別 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 替換系統日誌表時，對其留下嘅 `<name>_N` 表做什麼。`ignore` 會保留它們，`delete` 會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   喺 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 同依賴映像嘅 `linux/arm64` 變體。要強制使用 amd64 模擬進行調試，請使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 運行 Compose。

   捆綁嘅 compose 文件使用命名嘅 Docker 卷來存儲持久數據。如果你用主機綁定掛載替換它們，請先創建主機目錄並使其對容器用戶可寫，特別係 ClickHouse 同 ClickHouse Keeper 嘅數據目錄。

4. 喺 http://localhost:8080 訪問伺服器

**服務端點：**
- Tuist 伺服器：http://localhost:8080
- Kura 緩存（HTTP + REAPI gRPC 共用一個端口）：http://localhost:4000
- MinIO 控制台：http://localhost:9003（憑證：`tuist` / `tuist_dev_password`）
- MinIO API：http://localhost:9002
- pgweb（PostgreSQL UI）：http://localhost:8081
- Prometheus 指標：http://localhost:9091/metrics
- ClickHouse HTTP：http://localhost:8124

**常用命令：**

檢查服務狀態：
```bash
docker compose ps
# or: podman compose ps
```

查看日誌：
```bash
docker compose logs -f tuist
```

停止服務：
```bash
docker compose down
```

重置所有內容（刪除所有數據）：
```bash
docker compose down -v
```

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整嘅 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變數示例文件

## 使用 Helm 部署 Kubernetes {#kubernetes-with-helm}

Tuist 提供官方 Helm chart 用於喺 Kubernetes 上部署。該 chart 打包咗 Tuist 伺服器同緩存服務，以及嵌入式基礎設施依賴項，你可以根據需要將其替換為外部提供商。

### 安裝 chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

要鎖定特定嘅 chart 版本：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### 許可證 {#helm-license}

`server.license.key` 值接受標準許可證密鑰，對於隔離安裝，亦接受 Base64 編碼嘅許可證證書；伺服器會自動檢測係邊一種。

使用 `--set` 傳遞許可證適用於快速安裝。如果你將值保存喺版本控制中，請將許可證存儲喺一個由 Helm 之外管理嘅 Kubernetes Secret 中（例如使用 Vault、Sealed Secrets 或 SOPS），並將 chart 指向它：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下嘅條目命名咗你嘅 Secret 中保存許可證值嘅字段，該值可以係許可證密鑰，或者對於隔離安裝，係 Base64 編碼嘅許可證證書。`existingSecretKeys` 下嘅每個條目預設為 chart 自己嘅鍵名，因此將你嘅 Secret 中不包含嘅條目設置為空字符串，如上所示嘅 `certificateBase64`。否則，pod 會引用不存在嘅密鑰並無法啟動。喺安裝或升級 chart 之前，請喺發布命名空間中創建 Secret。

只通過一個來源配置許可證：`server.license.key` 或 `server.license.existingSecret`。如果未設置任何來源或組合咗多個來源，chart 將無法渲染。通過 `server.extraEnv` 傳遞嘅許可證不算作來源，因此請改用 `existingSecret`。

### 基礎設施依賴項 {#helm-infrastructure-dependencies}

Chart 管理三個基礎設施依賴項：`postgresql`、`clickhouse` 同 `objectStorage`。每個都預設為 **嵌入式** 模式，即 chart 會喺集群內部部署它們。要指向你自己嘅外部實例，請將依賴項嘅 `mode` 設置為 `external` 並喺你嘅 `values.yaml` 中填寫連接詳情。例如，要使用外部 PostgreSQL 數據庫：

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

如果你喺 Helm 之外管理 PostgreSQL 憑證，請將 chart 指向現有嘅 Kubernetes Secret：

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

Chart 從 Secret 中讀取主機、用戶名同密碼，並通過 Kubernetes 環境變數替換組成 `DATABASE_URL`，因此密碼不會渲染到 Helm manifest 中。Secret 嘅密碼值應該係 URL 安全嘅，因為它會被插入到數據庫 URL 中。

同樣嘅模式適用於 `clickhouse` 同 `objectStorage`。請參見 chart 嘅 `values.yaml` 中每個部分下嘅 `external` 塊，以獲取完整嘅可配置字段集。

### 共享調度同標籤 {#helm-shared-scheduling-and-labels}

Chart 喺 `global` 下公開一組少量嘅共享 pod 設置，以便運維人員可以調整部署以適應其集群，而無需為每個工作負載重複相同嘅值：

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

當你需要同以下操作時使用這些設置：

- 為每個 pod 添加集群特定嘅標籤
- 從私人註冊表拉取鏡像
- 定位到專用節點池
- 允許 Pod 調度到為 Tuist 工作負載保留嘅受污染節點

### 工作負載身份同服務帳戶 {#helm-workload-identity}

Chart 按應用工作負載劃分服務帳戶範圍，以便你只喺需要嘅地方授予身份：

- `server.serviceAccount` 適用於 Tuist 伺服器部署同遷移任務
- `cache.serviceAccount` 適用於緩存部署

例如，當緩存使用 EKS 上嘅外部 S3 存儲桶時，你可以為緩存工作負載啟用 IRSA，而無需將相同嘅 IAM 角色附加到嵌入式數據庫：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 兼容性覆蓋 {#helm-compatibility-overrides}

Chart 將存儲同網格特定嘅調整設為可選，以保持默認值嘅可移植性：

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

僅喺你嘅集群需要時使用這些覆蓋：

- `cache.podSecurityContext` 預設為空。如果你嘅存儲類或 CSI 驅動程序需要喺掛載卷上共享組所有權，請設置 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 嘅標準 `9000` 原生服務端口，當服務網格或平台保留與該端口衝突時可以更改。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，令 ClickHouse 對嵌入式內部日誌表（例如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 同 `system.part_log`）保持無限制保留。設置它會一次性取代這些表，因此請連同 `supersededTables: delete` 一起採用 — 參見 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制運營日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對於嵌入式 ClickHouse 伺服器日誌記錄器同 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不屬於任何表定義，因此更改它永遠不會取代表。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore` 並決定當 ClickHouse 取代系統日誌表時 `<name>_N` 表嘅處理方式。將其設置為 `delete` 以喺每次 `helm upgrade` 時刪除它們。
- 對 `ttlDays` 同 `level` 嘅編輯會喺 ClickHouse Pod 下次重啟時生效，因為兩者都係 `subPath` 掛載，且 Chart 喺其 ConfigMap 更改時不會滾動 StatefulSet。

### 可觀測性 {#helm-observability}

Chart 包含一個可選嘅可觀測性棧（OpenTelemetry Collector、Prometheus、Grafana、Loki 同 Tempo）。它預設**禁用**。要喺你嘅 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 可用，並預配置咗日誌、追蹤同指標下鑽。對於外部可觀測性，請保持此功能禁用並通過 `server.extraEnv` 配置端點：

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

有關可配置值嘅完整列表，請參見 Chart 嘅 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 鏡像位於：
```
ghcr.io/tuist/tuist
```

發布嘅鏡像包含用於 `.xcactivitylog` 歸檔嘅嵌入式 Linux 構建處理，因此自託管部署可以處理構建而無需運行任何額外服務 — `ProcessBuildWorker` Oban 任務喺每個伺服器 Pod 上進程內運行。如果你想將構建處理卸載到專用副本集（例如，獨立於 Web 層擴展解析吞吐量），請喺 Helm Chart 中設置 `processor.enabled: true`：Chart 會將相同鏡像部署為僅隊列消費者（`TUIST_PROCESSOR_MODE=true`）。有關完整配置項，請參見 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

> [!NOTE]
> `.xcresult` 解析依賴 Xcode 中嘅 `xcresulttool`，因此只能喺 macOS 上運行。CLI 為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 伺服器預設為 **本地** 處理模式，喺開發者機器上解析 xcresult（該機器已安裝 Xcode 用於構建本身）並上傳結構化結果。測試結果無需任何額外基礎設施即可被攝取。

### 拉取 Docker 鏡像 {#pulling-the-docker-image}

你可以通過執行以下命令來檢索鏡像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

鏡像同時發布咗 `linux/amd64` 同 `linux/arm64` 版本，因此 Docker 會自動為主機選擇原生 Linux 架構。

或者拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 鏡像 {#deploying-the-docker-image}

Docker 鏡像嘅部署過程將根據你選擇嘅雲提供商同你組織嘅持續部署方法而有所不同。由於大多數雲解決方案同工具（如 [Kubernetes](https://kubernetes.io/)）都使用 Docker 鏡像作為基本單元，因此本節中嘅示例應該與你現有嘅設置很好地對齊。

> [!WARNING]
> 如果你嘅部署流水線需要驗證伺服器是否已啟動並運行，你可以向 `/ready` 發送 `GET` HTTP 請求並斷言響應中嘅 `200` 狀態碼。


#### Fly {#fly}

要喺 [Fly](https://fly.io/) 上部署應用，你需要一個 `fly.toml` 配置文件。考慮喺你嘅持續部署 (CD) 流水線中動態生成它。以下係供你使用嘅參考示例：

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

然後你可以運行 `fly launch --local-only --no-deploy` 來啟動應用。喺後續部署中，與其運行 `fly launch --local-only`，你需要運行 `fly deploy --local-only`。Fly.io 不允許拉取私人 Docker 鏡像，這就是為什麼我們需要使用 `--local-only` 標誌。


## Prometheus 指標 {#prometheus-metrics}

Tuist 喺 `/metrics` 公開 Prometheus 指標，以幫助你監控你嘅自託管實例。這些指標包括：

### Finch HTTP 客戶端指標 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 客戶端，並公開有關 HTTP 請求嘅詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求持續時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求異常總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連接池隊列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連接池隊列中等待嘅時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連接在被使用前處於空閒狀態嘅時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 隊列異常總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連接指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連接所花費嘅時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`error`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 連接嘗試總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`

#### 發送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 發送請求所花費嘅時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連接在發送前處於空閒狀態嘅時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標都提供 `_bucket`、`_sum` 同 `_count` 變體以供詳細分析。

### 其他指標

除咗 Finch 指標外，Tuist 亦公開以下指標：
- BEAM 虛擬機性能
- 自定義業務邏輯指標（存儲、帳戶、項目等）
- 數據庫性能（使用 Tuist 託管基礎設施時）

## 運維 {#operations}

Tuist 喺 `/ops/` 下提供一組實用工具，你可以用嚟管理你嘅實例。

> [!WARNING]
> **授權**
>
> 只有電子郵件域名與 `TUIST_OPERATOR_EMAIL_DOMAIN` 匹配嘅用戶才能訪問 `/ops/` 端點。如果未設置該變量，則無人可以訪問它們。將其設置為你控制郵箱嘅域名。
>
> 用戶亦必須證明佢哋對地址嘅控制權：可以透過點擊確認或重設密碼電郵、使用 Google、GitHub 或 Apple 登入，或者輸入一次性代碼或出示代理登入嘅已驗證電郵。自動確認嘅帳戶（喺無郵件提供者時係預設情況）未符合要求，直到佢哋完成上述步驟為止。帳戶創建後，只有當地址位於 `TUIST_OPERATOR_EMAIL_DOMAIN` 內時才會記錄證明，因此當你設置或更改該變量後，尚未在此之下證明其地址嘅運維人員需要再次進行證明。透過其中一個提供者登入或透過代理登入創建嘅帳戶，會自創建時起攜帶證明。如果無郵件提供者，使用密碼註冊嘅帳戶無法連結其中一個提供者，因此請透過使用 Google、GitHub 或 Apple 登入來創建運維人員帳戶，或者配置郵件提供者。
>
> 喺此檢查存在之前創建嘅帳戶尚未記錄該證明，因此現有運維人員喺重設密碼或使用其中一個提供者登入一次後即可重新獲得訪問權限。
>
> 當運維域名中無該證明嘅帳戶首次以該方式證明其地址時，Tuist 會移除其密碼、通行密鑰同組織單一登入提供者嘅連結，並將其從瀏覽器同 CLI 登出，因為註冊該地址嘅人可能並非其所有者。對此類帳戶進行密碼重設亦會執行相同操作，除咗設置新密碼之外。帳戶上設置嘅身份驗證器應用會保留；如果唔係所有者嘅，請為佢哋移除。運維域名之外嘅已確認帳戶會保留其憑證。所有者可以繼續使用提供者登入，或者透過重設設置新密碼。
>
> 由 SCIM 配置創建或重命名嘅帳戶喺其所有者提供證明之前無任何證明。


- **錯誤 (`/ops/errors`)：** 你可以查看應用程式中發生嘅意外錯誤。這對於調試同了解問題所在很有用，如果你遇到問題，我哋可能會要求你同我哋分享此信息。
- **儀表板 (`/ops/dashboard`)：** 你可以查看一個儀表板，它提供對應用程式性能同健康狀況嘅洞察（例如記憶體消耗、運行中嘅進程、請求數量）。這個儀表板對於了解你使用嘅硬件是否足以處理負載非常有用。
