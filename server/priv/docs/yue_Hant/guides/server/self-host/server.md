---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解如何將 Tuist server 部署到你嘅基礎設施。"
}
---
# Server {#server}

我哋為需要更多基礎設施控制權嘅組織提供 Tuist server 嘅自託管版本。此版本允許你喺自己嘅基礎設施上託管 Tuist，確保你嘅數據保持安全同私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要合法有效嘅付費授權。Tuist 嘅本地部署版本僅適用於 Enterprise 計劃嘅組織。如果你對此版本感興趣，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊式自託管快取節點技術已唔適用於新安裝。請使用<.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link>了解當前嘅自託管快取基礎設施。
>
> 現有部署仍然可以參考 GitHub Markdown 檢視器中嘅舊版源文件文檔：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)同[快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist server 同 Kura cache server 透過三個 GHCR 映像渠道發布：**canary**（每次提交到 `main`）、**release candidate**（每週一截取，測試一週）同**stable**（下週一提升）。只有 stable 版本會移動 `:latest` 並默認解析；canary 同 release candidate 係 GitHub 預發布版本，你需要通過固定標籤來選擇加入。Server 同 Kura 遵循相同嘅每週發布週期，與 [Tuist CLI 嘅發布時間表](/en/cli/release-channels) 同步。

我哋遵循 [語義化版本控制](https://semver.org/) 以確保可預測嘅版本控制同兼容性。主要版本用於標記 Tuist server 中需要與自託管用戶協調嘅破壞性變更；你唔應該預期我哋會經常使用它，如果真係需要，请放心，我哋會協助你順利過渡。

請參閱 <.localized_link href="/guides/server/self-host/release-channels">發布渠道</.localized_link> 頁面，了解每個渠道如何截取、如何喺你嘅部署中固定一個渠道，以及建議嘅策略：讓生產環境停留喺變動緩慢嘅 stable 線路，同時讓暫存環境測試即將到來嘅版本。

## 瀏覽器會話升級 {#browser-session-upgrade}

如果 15 分鐘內沒有經過身份驗證嘅頁面請求或 LiveView 交互，瀏覽器會話將過期，且無論如何都唔會超過身份驗證後嘅八小時。「記住我」會恢復相同嘅服務端會話，但無法延長任何一個期限。活動每分鐘檢查一次，因此閒置會話可能提前最多 59 秒過期。WebSocket 心跳、自動重新連接同背景更新唔會刷新活動。這些期限唔會改變機器憑證或 API 令牌嘅有效期。

喺啟動升級後嘅應用程序進程之前，運行附加嘅 `users_tokens` 遷移。現有行唔會回填：它們嘅創建時間限制咗非活動時間同絕對過期時間，並且喺訪問強制 SSO 嘅組織之前必須重新進行身份驗證。回調嘅提供者、簽發者或已驗證嘅 Workspace，以及自定義 SSO 連接會存儲喺服務端，並與組織嘅當前設置進行比較。關聯賬戶唔係會話身份驗證證明。

喺將策略視為強制執行之前，升級每個提供服務嘅 Web 副本。較舊嘅二進制文件仍然可以接受其以前嘅 60 天會話，並且唔會強制執行新嘅 LiveView 邊界；混合版本喺模式上兼容，但策略上唔等效。預計用戶需要再次登錄。回滾到較舊嘅二進制文件會削弱這些控制；如果需要模式回滾，請喺刪除新字段之前停止所有讀取新字段嘅二進制文件。切勿延長舊會話或推斷來源以避免重新身份驗證。

## OAuth 升級同回滾邊界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 實體快取需要對現有安裝進行分階段升級。喺部署停止 OAuth 快取失效嘅版本之前，首先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 嘅權威讀取兼容版本部署到 **每個 OAuth 讀取器同寫入器**。此兼容階段首次出現喺 **1.355** 發布系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升，生產部署應使用穩定嘅 `1.355.x` 版本。1.354 或更早版本嘅安裝必須完成此階段，然後才能升級到包含移除操作嘅更高版本。保持 1.355 系列僅用於兼容：唔要將失效移除反向移植到其中。

原始兼容提交亦可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 獲取。另一個映像僅當它保留權威讀取 **並保留舊版失效** 同時舊消費者仍然存在時，才適合作為兼容階段。喺提供流量之前運行該階段嘅正常數據庫遷移，包括刷新令牌查找索引。

檢查每個環境中嘅所有 Web 副本、背景工作器、計劃任務同單獨固定嘅處理器映像。等待兼容推出完成，並喺移除失效之前驗證沒有剩餘嘅快取讀取二進制文件。唔好讓浮動映像標籤喺自動升級期間跳過此階段。沒有舊消費者嘅全新安裝唔需要中間部署。

> [!WARNING]
> **保留權威讀取回滾目標**
>
> 移除失效後，常規滾動回滾必須針對 #14040 或另一個權威讀取版本。即使每個無失效進程都已停止，保留嘅 OAuth 快取條目仍可能過時，並且重新啟動嘅快取讀取副本可以從對等節點導入它們。
>
> 進一步回滾需要停止並排空 **所有** 無失效 OAuth 消費者，然後喺啟動任何快取讀取消費者之前清除或替換 **每個** 保留嘅 Boruta 快取參與者。防止保留嘅參與者重新加入。僅排空入口或僅重新啟動 Web 副本係不足夠嘅；請與你嘅 Tuist 支持聯絡人協調此恢復過程，而唔係自動清除快取或回滾數據庫遷移。

## 多副本集群 {#multi-replica-clustering}

支援嘅多副本 Web 部署需要 Erlang 集群嚟進行跨副本 Phoenix PubSub 同 Oban PG 通知，而唔係作為身份驗證權威。當 `server.cluster.enabled` 為 false 時，Chart 會拒絕多個副本，包括可以擴展到超過一個副本嘅自動縮放器。先前接受嘅未集群部署必須計劃此升級，而唔係繞過保護。喺更改成員資格之前，完成 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括移除失效。

使用你嘅密鑰管理器喺發布命名空間中創建私有 Cookie Secret，然後配置其名稱同密鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵並由所有參與嘅 Web 副本共享。切勿使用嵌入喺發布映像中嘅 Cookie：擁有分發 Cookie 即授予喺其節點上遠程執行嘅權限。分佈式發布啟動現在拒絕缺少私有 `RELEASE_COOKIE` 或無效端口，包括明確配置但沒有 DNS 發現嘅 `RELEASE_DISTRIBUTION=name` 或 `sname`。非 Chart 部署還必須一致地配置 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 以及 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

透過常規伺服器連接嘅 `helm upgrade`，將 `cookieExistingSecret` 留空會創建一個 Cookie Secret，並喺後續升級中重用其當前值。離線 `helm template`、Argo CD 同其他沒有實時 Secret 查找功能嘅 GitOps 渲染器無法保留該生成值；它們必須使用由單獨管理嘅穩定 Secret 支持嘅 `cookieExistingSecret`。唔好更改 Cookie 密鑰嚟隱式輪換活動集群。Cookie 輪換需要協調每個參與者嘅遷移/重新啟動；僅更新 Secret 唔會更新現有進程。

從映像內置 Cookie 進行嘅首次推出會形成獨立嘅新舊成員島嶼，直到所有 Web 副本都使用私有 Secret。為實時更新規劃遷移窗口。後續滾動部署會形成混合版本集群，因此要根據實際新舊版本限定 PubSub、Oban 通知同對等節點替換。這些通知唔係持久交付保證。回滾兼容版本時，保留權威讀取回滾映像並保持相同嘅私有 Cookie。

只允許受信任嘅伺服器對等節點之間訪問 EPMD (TCP 4369) 同配置嘅分發端口，絕唔允許來自租戶工作負載或公共網絡嘅訪問。驗證你環境中實際嘅入口/出口隔離；渲染 NetworkPolicy 並唔證明強制執行或後端可達性。兩副本金絲雀喺持續負載下必須通過加入、滾動替換同故障/恢復測試先至可以提升。DNS 用於發現對等節點，而唔係喺暫時失敗或部分響應時斷開健康節點；真實節點丟失同 OTP 分區預防仍然適用。libcluster 可能仍會喺保留回調中記錄成功嘅「斷開」操作而唔關閉連接；應從節點上線/下線事件或 `Node.list()` 確定實際成員資格，而唔係僅憑該日誌行。

## 持續部署 {#continuous-deployment}

我哋建議將生產環境固定喺穩定嘅次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），以便日常升級只包含向後移植嘅修復程序。穩定版本線喺候選發布渠道浸泡一週後，於每週一 UTC 時間 06:00 提升；喺金絲雀或當前候選發布標籤上嘅預演環境會喺回歸影響用戶之前捕獲它們。請參閱 <.localized_link href="/guides/server/self-host/release-channels">發布渠道</.localized_link> 以獲取推薦嘅固定策略。

如果你寧願喺新功能變得穩定時吸收它們而唔觸碰你嘅清單，請固定 `:latest`。該標籤喺每週一早上移動一次，因此相應安排你嘅部署窗口。以下係一個 GitHub Actions 工作流程示例，它按照該頻率檢查並部署最新穩定映像：

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

## 網絡可信訪問 {#network-trusted-access}

自託管安裝可以允許受信任網絡上嘅開發人員無需登錄即可提交見解、使用快取，或兩者兼有。儀表板同管理仍然需要身份驗證。

只啟用你需要嘅功能：

| 伺服器環境變量 | 允許無需登錄 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交構建同測試見解 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀取同寫入快取嘅構建輸出 |

兩個設置默認都係 **關閉**，相互獨立，並適用於實例範圍內嘅所有帳戶同項目，包括私有項目。它們喺託管 Tuist 上不可用，亦唔替代自託管許可證。

當 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 未設置時， former `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍然作為兼容性回退保留。

> [!WARNING]
> 只喺強制執行嘅辦公網絡或 VPN 邊界後面啟用這些設置。任何能夠訪問已啟用端點嘅人都可以提交報告，或者喺啟用快取訪問時讀取同覆蓋快取輸出。這允許偽造遙測數據、快取投毒同容量耗盡。報告響應亦可能洩露私有項目句柄同構建系統。Tuist 唔驗證 VPN 成員資格，亦唔信任轉發嘅 IP 頭部作為成員資格證明。

### 配置實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器同任何 Bazel BES 入口限制喺你嘅受信任網絡。
2. 喺升級客戶端之前升級每個伺服器同 Kura 副本。保持 Kura 身份驗證啟用狀態，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑據；禁用它會繞過這些限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 配置你嘅快取端點。
3. 喺每個相關嘅 Tuist 伺服器副本上設置上述所需變量，然後重新啟動或重新部署它們。只有確切值 `true` 先至會啟用設置。沒有儀表板切換或單獨嘅 Kura 標誌。

### 配置客戶端 {#network-trusted-client-configuration}

喺每個兼容客戶端上配置最終自託管伺服器 URL 同項目。當缺少憑據時，客戶端會自動發現啟用了哪些功能；唔需要客戶端選擇加入。發現唔會跟隨重定向。現有憑據繼續使用，無效或刷新失敗嘅憑據會導致錯誤而唔係匿名回退。重新登錄或明確登出以恢復。

喺啟用見解訪問之前，將所有共用憑據嘅工具升級到可以保留損壞或被拒絕憑據、拒絕無法讀取嘅憑據目錄，並喺未簽署報告中省略 Git 來源嘅版本。較舊嘅工具可能會刪除憑據並無意中允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏發現支援或回滾到較舊版本，客戶端必須進行身份驗證。以前嘅 `TUIST_NETWORK_TRUSTED_PUBLISHING` 客戶端設置不再適用。

- **見解：** 只提交已完成嘅 Xcode、Gradle、Elixir/Mix 同 Bazel 報告，唔包括存檔、附件、覆蓋率、分片規劃或現有報告訪問權限。參與者聲明未經驗證；未簽署嘅遙測數據唔會驅動受信任嘅測試證據或自動化。請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 同 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南以獲取客戶端設置同隱私詳情。
- **快取：** 支援 CLI 編譯/模組快取、Bazel 快取同 Gradle 任務快取。快取清除同遠程資產下載仍然需要憑據。不支援嘅客戶端必須繼續進行身份驗證。
- **Bazel：** 報告需要明確嘅 `TUIST_BAZEL_BES_BACKEND` 同兼容嘅 Kura。快取同報告選項獨立啟用。更改憑據或任一設置後重新運行 `tuist bazel setup`；更改編譯快取配置後重新運行 `tuist cache config`。

報告請求限制為每個項目 8 MB、每分鐘 60 個請求同每日 10,000 個請求。配置共享 Valkey 以實現具有多個副本嘅部署範圍配額；否則限制係按進程計算。如果配置嘅共享配額後端不可用，未簽署報告將被拒絕。同時添加入口連接、主體同速率限制。

### 禁用網絡可信訪問 {#disable-network-trusted-publishing}

將相關變量設置為 `false`，然後重新啟動 **每個相關嘅伺服器副本**。舊副本可以繼續接受無憑據請求，直到被替換。快取訪問會喺最後一個副本切換後 60 秒內停止新請求；傳輸中嘅傳輸不會被取消。如果需要立即撤銷，請先喺入口處阻止流量。現有報告保留其通常嘅可見性同保留期，已身份驗證嘅客戶端繼續工作。

## 運行時要求 {#runtime-requirements}

本節概述喺你嘅基礎設施上託管 Tuist 伺服器嘅要求。

### 兼容性矩陣 {#compatibility-matrix}

Tuist 伺服器已經過測試，並與以下最低版本兼容：

| 組件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析所需 |

### 運行 Docker 虛擬化映像 {#running-dockervirtualized-images}

我哋通過 [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像形式分發伺服器。

要運行它，你嘅基礎設施必須支援運行 Docker 映像。請注意，大多數基礎設施提供商都支援它，因為它已成為喺生產環境中分發同運行軟件嘅標準容器。

### Postgres 數據庫 {#postgres-database}

除咗運行 Docker 映像外，你還需要一個 [Postgres 數據庫](https://www.postgresql.org/) 來存儲關係數據。大多數基礎設施提供商都喺其產品中包含 Postgres 數據庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 同 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅架構遷移。


### ClickHouse 數據庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來存儲同查詢大量分析數據。ClickHouse 對於構建見解等功能係 **必需** 嘅。你可以選擇自託管 ClickHouse 或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅 ClickHouse 架構遷移。

捆綁嘅 Docker Compose 同 Helm 嵌入式 ClickHouse 配置將 ClickHouse 文本日誌級別從映像嘅 `trace` 默認值降低到 `information`，這係 `system.text_log` 卷大部分來源嘅地方。兩者亦可以限制 ClickHouse 自身嘅 `system.*` 操作日誌表，這些表否則係無邊界嘅，但默認情況下係關閉嘅 — 請參閱下文。外部 ClickHouse 部署應該直接喺其 ClickHouse 服務中配置這些操作日誌。

#### ClickHouse 複製拓撲 {#clickhouse-replication-topology}

Tuist 背後嘅多副本 ClickHouse 僅喺 ClickHouse Cloud 上支援。自管理嘅 ClickHouse 係單副本。

攝取遷移發出普通嘅 `MergeTree` 引擎。喺 Cloud 上，這透明地變成 `SharedMergeTree`，因此寫入會進入共享對象存儲，任何副本數量都可以工作。喺自管理嘅 ClickHouse 上，`MergeTree` 只寫入一個副本嘅本地磁盤；多副本設置要么靜默地喺副本之間拆分攝取，要么根據連接用戶上 `database_replicated_allow_only_replicated_engine` 嘅設置方式，使用 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒絕 CREATE。

喺自管理嘅 ClickHouse 上運行一個帶有一個副本嘅分片，並定期備份 ClickHouse 數據目錄。如果節點丟失，沒有第二個副本可以回退。

#### 限制操作日誌保留 {#capping-operational-log-retention}

保留可以應用於 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 同 `system.part_log`。

喺已有數據嘅實例上開啟它係一次性、單向步驟，這就是為什麼兩個捆綁包都唔為你執行此操作。任何保留窗口都會使這些表定義停止匹配其配置，因此 ClickHouse 會將每個表重命名並啟動一個新表，如 [已取代嘅日誌表](#superseded-log-tables) 下所述。留下嘅世代保留迄今為止累積嘅所有内容，並且自身沒有保留，因此除非你喺同一步驟中回收它，否則它會永久留喺磁盤上，而新窗口只限制從那時起寫入嘅行。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

該單一 `helm upgrade` 係自包含嘅，因為將 `ttlDays` 從空白移動到設置會添加 drop-in 掛載並滾動 ClickHouse pod：它重新啟動，取代表，然後升級後作業將其刪除。使用 `helm upgrade --wait` 部署，以便喺作業運行之前滾動 pod；否則世代會喺它查看之後出現，而下一次 `helm upgrade` 會取而代之回收它們。

使用 Docker Compose，取消註釋 `docker-compose.yml` 中 `clickhouse` 服務上嘅 `clickhouse-log-ttl.xml` 卷，並喺 `.env` 中設置兩個變量：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦回收咗空間，你可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改返做 `ignore`，咁樣日後 ClickHouse 升級時就唔會自行丟棄歷史記錄。

#### 已取代嘅日誌表 {#superseded-log-tables}

ClickHouse 喺啟動時會檢查每個系統日誌表是否仍然符合其配置。如果唔符合，它會將現有表重命名為 `system.<name>_0`，然後係 `_1`、`_2`，如此類推，並啟動一個新表。當你更改保留窗口，或者進行任何更改系統日誌架構嘅 ClickHouse 升級時，就會發生呢種情況。

重命名表唔會複製其數據，所以這唔會消耗額外磁盤空間。被取代表之後嘅命運取決於它來自哪個表，因為它會保留活動表喺被取代那一刻擁有嘅任何保留策略。第一次啟用保留時，被取代表沒有任何保留策略，所以它會保存迄今為止累積嘅所有歷史記錄並無限期保留。後來對窗口嘅更改會取代已經帶有 TTL 嘅表，所以那些會自行過期並留下一個空表。ClickHouse 永遠唔會刪除表本身，所以喺長期運行嘅實例上，無論如何它們都會累積。

默認情況下會保留被取代表，以便升級時永遠唔會自行丟棄操作歷史。將策略設置為 `delete` 以改為刪除它們，這會喺 `docker compose up` 同每次 `helm upgrade` 時發生：

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

使用 Helm chart 時，將相同策略配置為值：

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

刪除被取代会回收其磁盤空間。活動表永遠唔會被觸及，自被取代以來寫入嘅行亦都唔會受影響。

如果唔想更改策略而只想回收一次空間，可以手動刪除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 數據庫使用 `Atomic` 引擎，這會將普通 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（默認為八分鐘）。`SYNC` 會立即刪除數據，當磁盤已满而你正在刪除這些表時，這正係你想要嘅。


### 存儲 {#storage}

你仲需要一個解決方案來存儲文件（例如框架同庫嘅二進制文件）。Tuist 服務器支援 S3 兼容存儲同 Azure Blob Storage 用於服務器擁有嘅構件。

> [!TIP]
> **優化緩存**
>
> 如果你嘅目標主要係減少緩存延遲，你可能唔需要自託管整個服務器。你可以喺靠近你嘅 CI 或開發者網絡嘅地方部署自託管 Kura 節點，並將它們連接到託管嘅 Tuist 服務器或你嘅自託管服務器。
>
> 請參閱 <.localized_link href="/guides/cache/self-host">自託管緩存指南</.localized_link>。


### 自託管 Kura 節點 {#self-hosted-cache-nodes}

要喺自託管 Tuist 服務器上使用自託管 Kura 節點：

1. 喺 Tuist 服務器上配置 `KURA_CONTROL_PLANE_CLIENT_ID` 同 `KURA_CONTROL_PLANE_CLIENT_SECRET`。客戶端 ID **必須係 UUID**。使用 <.localized_link href="/guides/cache/self-host#control-plane-client">自託管緩存指南</.localized_link> 中嘅命令生成 UUID 同隨機密鑰，並將它們存儲喺你嘅部署密鑰中。
2. 按照 <.localized_link href="/guides/cache/self-host">自託管緩存指南</.localized_link> 部署 Kura 節點，使用相同嘅控制平面憑證。
3. 使用 `KURA_REGISTRATION_URL` 同 `KURA_ADVERTISED_HTTP_URL` 配置每個 Kura 節點。註冊心跳會告訴服務器哪些就緒、面向客戶嘅 Kura 端點可以向 CLI 廣告。

## 配置 {#configuration}

服務嘅配置係通過環境變量喺運行時完成嘅。鑑於這些變量嘅敏感性，我哋建議加密並將它們存儲喺安全嘅密碼管理解決方案中。請放心，Tuist 會極其小心地處理這些變量，確保它們永遠唔會顯示喺日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要嘅變量會喺啟動時驗證。如果缺少任何變量，啟動將失敗，錯誤消息將詳細說明缺失嘅變量。


### 許可證配置 {#license-configuration}

作為本地部署用戶，你會收到一個許可證，你需要將其作為環境變量公開。許可證用於驗證部署並確保服務喺協議條款內運行。

| 環境變量 | 描述 | 必需 | 默認 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務級別協議後提供嘅許可證。接受標準許可證密鑰或用於氣隙環境（服務器無法聯繫外部服務）嘅 base64 編碼證書。 | 是 | | `******` |

> [!WARNING]
> **到期日期**
>
> 許可證有到期日期。如果許可證喺少於 30 天內到期，用戶喺使用與服務器交互嘅 Tuist 命令時會收到警告。如果你有興趣續訂許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境配置 {#base-environment-configuration}

| 環境變量 | 描述 | 必需 | 默認 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從互聯網訪問實例嘅基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密信息（例如 cookie 中嘅會話）嘅密鑰 | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於生成哈希密碼嘅 Pepper | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於生成隨機令牌嘅密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於 AES-GCM 加密敏感數據嘅 32 字節密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | 當 `1` 時，它配置應用程序使用 IPv6 地址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程序使用嘅日誌級別 | 否 | `info` | [日誌級別](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 你嘅 GitHub 應用程序嘅 slug，取自 `https://github.com/apps/<slug>`。安裝應用程序所必需。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程序以解鎖額外功能（例如發布自動 PR 評論）嘅 base64 編碼私鑰 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程序以解鎖額外功能（例如發布自動 PR 評論）嘅私鑰。**我哋建議使用 base64 編碼版本以避免特殊字符問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件地址以 `@<this-domain>` 結尾嘅已確認用戶可以訪問操作 URL（`/ops/*`） | 否 | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 在儀表板導航欄中顯示為徽章以標識服務器實例嘅標籤（例如版本號或分支名稱） | 否 | 開發環境中嘅 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用 Web 服務器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許無需登錄即可提交構建和測試洞察。請參閱 [網絡可信訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許無需登錄即可讀取和寫入緩存。請參閱 [網絡可信訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 用於發送追蹤數據嘅 OpenTelemetry Collector 嘅 gRPC 端點 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 用於推送日誌嘅 Loki 兼容端點嘅基礎 URL（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **通過 HTTPS 提供應用程序**
>
> 會話 Cookie 被標記為 `Secure`，因此瀏覽器會在純 `http://` 上丟棄它們，用戶無法登錄。在服務器前面終止 TLS（使用來自你內部 CA 嘅證書嘅反向代理就足夠了），並將 `TUIST_APP_URL` 設置為 `https://` URL，即使是內部或僅限 VPN 嘅部署。

### 數據庫配置 {#database-configuration}

以下環境變量用於配置數據庫連接：

| 環境變量 | 描述 | 必需 | 默認 | 示例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 訪問 Postgres 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程序表使用嘅 PostgreSQL 模式。當你嘅數據庫策略不允許使用 `public` 模式時，請設置此項。模式名稱必須係一個未加引號嘅 PostgreSQL 標識符。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用嘅可選 Postgres URL。當 `DATABASE_URL` 指向權限較窄嘅運行時角色時，請將其設置為所有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程序表權限嘅運行時 Postgres 角色。當 Web 服務器不應以模式所有者身份連接時，請將此項與 `TUIST_MIGRATION_DATABASE_URL` 配合使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 訪問 ClickHouse 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 當為 true 時，它使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連接數據庫 | 否 | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | 在連接池中保持打開嘅連接數 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中檢出嘅所有連接是否超過隊列間隔嘅時間間隔（以毫秒為單位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 池用來決定是否開始丟棄新連接嘅隊列閾值時間（以毫秒為單位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩存刷新之間嘅時間間隔（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新之前嘅最大 ClickHouse 緩存大小（以字節為單位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要運行嘅 ClickHouse 緩存進程數 | 否 | `5` | `5` |

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，如果架構尚不存在，發布遷移會在運行 Ecto 遷移鏈之前創建該架構。如果遷移角色無法創建架構，請預先創建架構並將遷移角色設為其所有者。

Tuist 通過設置會話 `search_path` 將連接指向自定義模式。某些池化或代理嘅 Postgres 設置（例如 PgBouncer，或限制啟動參數嘅託管數據庫）不會應用此設置，會話會回退到 `public`，這在遷移期間會顯示為 `permission denied for schema public`。當通過此類設置連接時，請將模式固定在角色本身上，以便無論代理如何，每個會話都從中開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 身份驗證環境配置 {#authentication-environment-configuration}

我哋通過 [身份提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進身份驗證。要利用此功能，請確保所選提供者所需嘅所有環境變量都存在於服務器環境中。**缺少變量** 將導致 Tuist 跳過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登錄以及自助註冊係內置並默認啟用嘅。在需要要求身份提供者嘅實例上（例如，當強制執行 SSO 時），你可以完全關閉它們。這會從登錄體驗中刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉每個匹配嘅服務器端端點，包括 CLI 使用嘅電子郵件/密碼端點 (`tuist auth`)。

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登錄和註冊。設置為 `0` 以從登錄頁面刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉匹配的服務器端端點 | 否 | `1` | `0` |

#### 禁用已配置的身份提供者 {#disabling-a-configured-identity-provider}

默認情況下，只要配置了提供者，它就會作為登錄選項出現。要在保持提供者配置（其憑據保持設置）的同時將其從登錄和註冊頁面中刪除，請將匹配的開關設置為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登錄回調，因此該方法端到端都不可用。

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄（有關應用程序為何與登錄共享其憑據的信息，請參閱 [GitHub](#github) 部分） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登錄 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 配置的 Okta 提供者是否作為登錄選項出現 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登錄 | 否 | `1` | `0` |

#### GitHub {#github}

我哋建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行身份驗證，但你也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保在服務器環境中包含 GitHub 指定的所有必要環境變量。缺少變量將導致 Tuist 忽略 GitHub 身份驗證。要正確設置 GitHub 應用程序：
- 在 GitHub 應用程序的常規設置中：
    - 複製 `Client ID` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 創建並複製新的 `client secret` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設置為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以是你服務器的 IP 地址。
- 需要以下權限：
  - 存儲庫：
    - 拉取請求：讀寫
  - 帳戶：
    - 電子郵件地址：只讀

在 `Permissions and events` 的 `Account permissions` 部分中，將 `Email addresses` 權限設置為 `Read-only`。

然後你需要在 Tuist 服務器運行的環境中公開以下環境變量：

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程序的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程序的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄。你為平台集成（PR 評論等）配置的 GitHub App 會與登錄共享其客戶端憑據，因此它會作為登錄選項出現。設置為 `0` 以保留應用程序同時從登錄頁面刪除 GitHub | 否 | `1` | `0` |

#### Google {#google}

你可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設置與 Google 的身份驗證。為此，你需要創建一個類型為 OAuth 客戶端 ID 的新憑證。在創建憑證時，選擇「Web Application」作為應用程序類型，將其命名為 `Tuist`，並將重定向 URI 設置為 `{base_url}/users/auth/google/callback`，其中 `base_url` 是你的託管服務運行的 URL。創建應用程序後，複製客戶端 ID 和密鑰，並分別將它們設置為環境變量 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意屏幕範圍**
>
> 你可能需要創建一個同意屏幕。這樣做時，請確保添加 `userinfo.email` 和 `openid` 範圍，並將應用程序標記為內部。


#### Okta {#okta}

你可以通過 [OAuth 2.0](https://oauth.net/2/) 協議啟用與 Okta 的身份驗證。你需要按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些說明</.localized_link>在 Okta 上[創建應用程序](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設置 Okta 應用程序期間獲得客戶端 ID 和密鑰後，你需要設置以下環境變量：

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於對 Okta 進行身份驗證的客戶端 ID。該數字應為你的組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於對 Okta 進行身份驗證的客戶端密鑰 | 是 | | |

數字 `1` 需要替換為你的組織 ID。這通常為 1，但請在你的數據庫中檢查。

### 存儲環境配置 {#storage-environment-configuration}

 Tuist 需要存儲來存放通過 API 上傳的構建產物。**必須配置支持的存儲解決方案之一**，Tuist 才能有效運行。

設置 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇服務器構建產物後端：

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 服務器構建產物存儲後端。對於 S3 兼容存儲使用 `s3`，對於 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 兼容存儲 {#s3compliant-storages}

你可以使用任何 S3 兼容的存儲提供者來存儲構建產物。以下環境變量是驗證和配置與存儲提供者的集成所必需的：

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於對存儲提供者進行身份驗證的訪問密鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於對存儲提供者進行身份驗證的私密訪問密鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 儲存桶所在的地區 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 存儲提供者的端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 將存儲構建產物的儲存桶名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | PEM 編碼的 CA 證書，用於驗證 S3 HTTPS 連接。適用於使用自簽名證書或內部證書頒發機構的隔離環境。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立與存儲提供者連接的超時時間（以毫秒為單位） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從存儲提供者接收數據的超時時間（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 與存儲提供者的連接池超時時間（以毫秒為單位）。使用 `infinity` 表示無超時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連接的最大空閒時間（以毫秒為單位）。使用 `infinity` 可讓連接永久保持活動狀態 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個池的最大連接數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用的連接池數量 | 否 | 系統調度器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連接存儲提供者時使用的協議（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將儲存桶名稱作為子域（虛擬主機）構建 | 否 | `false` | `1` |

> [!NOTE]
> **使用來自環境變量的 Web 身份令牌進行 AWS 身份驗證**
>
> 如果你的存儲提供者是 AWS 並且你想使用 Web 身份令牌進行身份驗證，你可以將環境變量 `TUIST_S3_AUTHENTICATION_METHOD` 設置為 `aws_web_identity_token_from_env_vars`，Tuist 將使用該方法並採用常規的 AWS 環境變量。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請按照[這些文檔](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)獲取 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設置為 `https://storage.googleapis.com`。其他環境變量與任何其他 S3 兼容存儲相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，設置 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並配置 Azure 存儲帳戶憑證：

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 存儲帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 的存儲帳戶訪問密鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 存儲伺服器構建產物的容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略則使用 `https://<account>.blob.core.windows.net` | 否 | 從帳戶名稱派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 的 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm chart 時，設置 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。chart 的頂層 `objectStorage` 設置保持 S3 兼容，因為可選的緩存和註冊表鏡像工作負載仍然需要 S3 兼容存儲。如果禁用這些工作負載且伺服器使用 Azure Blob，請設置 `objectStorage.mode=external` 並將外部對象存儲端點和憑證留空，以避免部署嵌入式 MinIO 服務。

#### 構建產物保留 {#artifact-retention}

在自託管實例中，默認情況下禁用構建產物清理。每種支持的構建產物類型都有其自己的環境變量。將變量設置為正整數天數以啟用該類型的清理。將變量留空或不設置僅會禁用該類型的清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm chart 時，將相同的窗口配置為映射：

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

所有六個鍵都是可選的。此示例啟用了每種支持的構建產物類型，並具有獨立的保留窗口。省略鍵或將其值留空以保持該類型的清理禁用。自託管保留窗口沒有 30 天的上限。配置的值如果不是正整數，會導致伺服器在啟動時失敗。

更改保留變量後重新啟動伺服器。每個排隊的自託管清理批次在刪除文件之前都會檢查當前配置，因此取消設置或清空變量，或增加其窗口，也可以在重新啟動後保護文件免受待處理作業的影響。

| 環境變量 | 從對象存儲中刪除的構建產物文件 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 緩存、舊版內容尋址存儲緩存、模塊緩存和 Gradle 緩存文件 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | 應用預覽構建和圖標 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 當前和舊版構建歸檔 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 存儲在已過期運行的構建產物前綴下的所有對象，包括結果包、調用記錄和會話歸檔 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片包 |

計劃的清理僅刪除構建產物 blob。它保留相應的 PostgreSQL 和 ClickHouse 行，因此在下載過期後，構建、測試、運行、預覽和分片中繼數據仍可在儀表板中可見。此配置不會更改 ClickHouse 表保留規則。

### 電子郵件配置 {#email-configuration}

Tuist 需要電子郵件功能用於用戶身份驗證和事務性通知（例如，密碼重置、帳戶通知）。目前，**僅支持 Mailgun** 作為電子郵件提供商。

| 環境變量 | 描述 | 必需 | 預設 | 範例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於與 Mailgun 進行身份驗證的 API 密鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件的域名 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將出現在「發件人」字段中的電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用戶回覆的可選回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新用戶註冊的電子郵件確認。啟用後，用戶會自動確認並可在註冊後立即登入 | 否 | 如果未配置電子郵件則為 `true`，如果已配置電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅當您需要發送電子郵件時才需要電子郵件配置變量。如果未配置，系統會自動跳過電子郵件確認

> [!NOTE]
> **SMTP 支援**
>
> 目前不提供通用 SMTP 支援。如果您需要為本地部署提供 SMTP 支援，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 討論您的需求。


> [!NOTE]
> **隔離網絡部署**
>
> 對於沒有互聯網訪問或電子郵件提供商配置的本地安裝，預設情況下會自動跳過電子郵件確認。用戶可以在註冊後立即登入。如果您已配置電子郵件但仍想跳過確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。如果要在配置電子郵件時要求電子郵件確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額和密碼重置連結**
>
> 配置電子郵件後，邀請電子郵件（新建、批量或重發）限制為每五分鐘每位收件人一封，且每個組織和每個邀請者每小時補充 50 封的突發上限為 50 封。取消邀請不會恢復配額，當配額用盡時，邀請 API 會回應 `429` 和 `Retry-After`。使用多個副本時，請配置共享 Valkey 以實現整個部署的配額；如果已配置但不可用，則會拒絕發送邀請電子郵件。密碼重置連結在 15 分鐘後過期。


### Git 平台配置 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台整合</.localized_link>，提供額外功能，例如在您的拉取請求中自動發布評論。

#### GitHub {#platform-github}

自託管的 Tuist 伺服器無法安裝運行於 `https://tuist.dev` 的 GitHub App。GitHub App 綁定到註冊它們的伺服器，因此您的部署需要在 github.com 上擁有自己的 App。

##### 註冊 App {#platform-github-registering-the-app}

[建立 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)，由您的 GitHub 組織擁有。您可以重複使用為身份驗證建立的 App，除非您建立的是 OAuth App。使用以下內容進行配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 的值：

| 設置 | 值 |
| --- | --- |
| 回調 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設置 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重定向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任意隨機字符串。您將把它設置為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予以下存儲庫權限：

| 權限 | 訪問 |
| --- | --- |
| 內容 | 只讀 |
| 元數據 | 只讀 |
| Issues | 讀寫 |
| 拉取請求 | 讀寫 |
| Checks | 讀寫 |

同時授予 **Members: read-only** 組織權限。在 github.com 設置期間，Tuist 會檢查連接組織安裝的人員是否為活躍的 GitHub 組織所有者，而不僅僅是擁有其某個存儲庫訪問權限的人。

將 App 訂閱到 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **Request user authorization (OAuth) during installation** 禁用，以便 GitHub 將安裝程序發送到 Setup URL。Tuist 使用額外的 `/integrations/github/authorize` 回調啟動單獨的授權步驟以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝者隨後選擇一個 Tuist 組織；在 Tuist 中開始的安裝會保留其組織。

##### 配置伺服器 {#platform-github-configuring-the-server}

設置以下環境變量，然後重啟伺服器：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公共頁面 URL 的最後路徑組件 `https://github.com/apps/<slug>` | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式的 base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，因為它對平台處理換行符的方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上配置的 webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **配置所有必需的 App 憑證**
>
> 組織整合頁面上的 **Install GitHub App** 按鈕將保持禁用狀態，直到 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私鑰全部設置完畢。數字 `TUIST_GITHUB_APP_ID` 也用於驗證安裝所有權。安裝 URL 嵌入了 App slug，因此缺少 `TUIST_GITHUB_APP_NAME` 尤其會導致 GitHub 回應 404 錯誤的連結。

伺服器重啟後，組織管理員按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 安裝 App 並將存儲庫連接到項目。

##### OIDC 身份驗證依賴於此 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份驗證</.localized_link> 會根據連接到您項目的存儲庫解析 CI 令牌中的存儲庫聲明，並且只能通過已安裝的 GitHub App 創建連接。在您的 CI 工作流程運行 `tuist auth login` 而不帶令牌之前，請完成上述設置。

您的 Tuist 伺服器還需要出站訪問您的 CI 提供商的 OIDC 頒發者以獲取其簽名密鑰：

| CI 提供商 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變量僅配置 Tuist 的 github.com App。若要將 Tuist 與 GitHub Enterprise Server (GHES) 實例整合，組織管理員需切換到整合頁面上的 **Enterprise server** 標籤並輸入 GHES 基礎 URL — Tuist 會引導他們通過 GitHub 的 [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 實例上註冊新的 Tuist App。新 App 的憑證按安裝加密存儲；無需額外的 `TUIST_GITHUB_APP_*` 環境變量。

#### Origin {#platform-origin}

自託管的 Tuist 伺服器需要自己的 Origin app，並配置您部署的 URL 和簽名密鑰。為每個 Tuist 環境註冊單獨的 app，以保持安裝和憑證獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支援 Ed25519 的 OpenSSL 產生 Ed25519 簽名金鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app settings](https://cursor.com/codebase/settings/apps) 中建立應用程式。將 `origin-app-public.pem` 的內容註冊為其公開簽名金鑰。請保密 `origin-app-private.pem`；您需要將其提供給 Tuist 伺服器，而不是上傳到 Cursor。
3. 配置以下設定，將 `YOUR_APP_URL` 替換為您 Tuist 部署的 HTTPS 基礎 URL：

   | 設定 | 值 |
   | --- | --- |
   | 主頁 URL | `YOUR_APP_URL` |
   | 重定向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 複製已註冊的 App ID，它以 `app_` 開頭。

Tuist 在安裝期間請求以下權限：

| 範圍 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 查找拉取請求及其當前的 head commit。 |
| `repository:pull_requests:reviews:write` | 讀取、發布和更新報告評論。Origin 包含相應的 review-read 權限。 |
| `repository:metadata:read` | 發現存儲庫並讀取其預設分支。由 Origin 自動授予。 |

不要選擇可選的存儲庫 webhook 事件。安裝生命週期通知已足夠；不需要原始碼訪問、合併權限和 check-run 權限。

##### 配置伺服器 {#platform-origin-configuring-the-server}

設置以下環境變量，然後重啟伺服器：

| 環境變量 | 描述 | 必需 | 預設值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app settings 複製的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私鑰存儲在您部署的密鑰管理器中。保留其多行 PEM 格式；此設定不接受 base64 編碼的替代方案。切勿將金鑰提交到原始碼控制或在日誌中暴露。兩個變量必須屬於同一個已註冊的 app。

您的 Tuist 伺服器需要對 `api.cursor.com` 的出站 HTTPS 訪問權限。Cursor 必須能夠將請求發送到 webhook URL，並且管理員必須能夠在瀏覽器中返回重定向 URI。兩個註冊的 URL 必須與您部署的 HTTPS 基礎 URL 匹配。

##### 安裝 App {#platform-origin-installing-the-app}

伺服器重啟後，管理員打開 **Settings → Integrations**，在 Origin 下選擇 **Connect**，並批准 app 訪問適當的 Origin 帳戶和存儲庫。在此流程中會保留 Tuist 組織。直接從 Origin 發起的安裝則會提示管理員登入並選擇要連接的 Tuist 組織。然後他們選擇 **Add new project connection** 將 Tuist 項目連結到原生存儲庫。

請遵循 <.localized_link href="/guides/integrations/gitforge/origin">Origin 整合指南</.localized_link> 了解項目連接和結果上傳要求。安裝 app 不會啟動構建或測試工作流程；這些工作流程會繼續向您的 Tuist 伺服器報告結果。

## 本地測試 {#testing-locally}

我們提供了一個全面的 Docker Compose 配置，其中包含在部署到基礎設施之前在本地機器上測試 Tuist 伺服器所需的所有依賴項：

- PostgreSQL 15
- ClickHouse 26.5 用於分析
- ClickHouse Keeper 用於協調
- MinIO 用於 S3 兼容存儲
- Kura 用於本地自託管快取測試
- pgweb 用於數據庫管理

> [!CAUTION]
> **需要授權**
>
> 執行 Tuist 伺服器（包括本地開發實例）在法律上需要有效的 `TUIST_LICENSE` 環境變量。如需授權，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速開始：**

1. 下載配置檔案：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 配置環境變量：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   內置的 ClickHouse 服務接受以下可選的操作日誌控制：

   | 環境變量 | 描述 | 預設值 | 示例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留期（以天為單位） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 伺服器日誌記錄器和 `system.text_log` 級別 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 替換系統日誌表時，如何處理其留下的 `<name>_N` 表。`ignore` 會保留它們，`delete` 會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 和依賴映像的 `linux/arm64` 變體。若要強制使用 amd64 模擬進行調試，請使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 運行 Compose。

   內置的 compose 檔案使用命名的 Docker 卷來存儲持久數據。如果您將它們替換為主機綁定掛載，請先創建主機目錄並使其對容器用戶可寫，特別是 ClickHouse 和 ClickHouse Keeper 數據目錄。

4. 在 http://localhost:8080 訪問伺服器

**服務端點：**
- Tuist Server: http://localhost:8080
- Kura cache (HTTP + REAPI gRPC on one port): http://localhost:4000
- MinIO Console: http://localhost:9003 (憑證：`tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

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

**配置檔案：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變量示例檔案

## 使用 Helm 的 Kubernetes {#kubernetes-with-helm}

Tuist 提供官方的 Helm chart 用於在 Kubernetes 上部署。該 chart 打包了 Tuist 伺服器和快取服務，以及嵌入式基礎設施依賴項，您可以根據需要將其替換為外部提供商。

### 安裝 chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

要鎖定特定的 chart 版本：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### 授權 {#helm-license}

`server.license.key` 值同時接受標準授權金鑰，以及針對隔離環境安裝的 Base64 編碼授權證書；伺服器會自動偵測是哪一種。

使用 `--set` 傳遞授權適合快速安裝。如果您將值存放在版本控制中，請將授權儲存在 Kubernetes Secret 中，並在 Helm 之外管理（例如使用 Vault、Sealed Secrets 或 SOPS），然後將 chart 指向該 Secret：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下的項目命名了您 Secret 中儲存授權值的欄位，可以是授權金鑰，或是針對隔離環境安裝的 Base64 編碼授權證書。`existingSecretKeys` 下的每個項目預設為 chart 自身的金鑰名稱，因此請將您的 Secret 不包含的項目設為空字串，如上方的 `certificateBase64` 所示。否則，Pod 會參考不存在的金鑰而無法啟動。請在安裝或升級 chart 之前，在發布命名空間中建立該 Secret。

僅透過一個來源設定授權：`server.license.key` 或 `server.license.existingSecret`。當兩者皆未設定或混合來源時，chart 將無法渲染。透過 `server.extraEnv` 傳遞的授權不算作來源，因此請改用 `existingSecret`。

### 基礎設施依賴項 {#helm-infrastructure-dependencies}

Chart 管理三個基礎設施依賴項：`postgresql`、`clickhouse` 和 `objectStorage`。每個依賴項預設為 **嵌入式** 模式，即 chart 會在叢集內部部署它們。若要改為指向您自己的外部實例，請將依賴項的 `mode` 設為 `external`，並在您的 `values.yaml` 中填寫連線詳細資訊。例如，要使用外部 PostgreSQL 資料庫：

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

如果您在 Helm 之外管理 PostgreSQL 憑證，請改為將 chart 指向現有的 Kubernetes Secret：

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

Chart 會從 Secret 讀取主機、使用者名稱和密碼，並透過 Kubernetes 環境變數替換組成 `DATABASE_URL`，因此密碼不會渲染到 Helm manifest 中。Secret 的密碼值應符合 URL 安全規範，因為它會被插入到資料庫 URL 中。

相同的模式適用於 `clickhouse` 和 `objectStorage`。請參閱 chart 的 `values.yaml` 中各章節下的 `external` 區塊，以取得完整的可設定欄位清單。

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

當您需要執行以下操作時，請使用這些設定：

- 為每個 Pod 新增叢集專屬標籤
- 從私人註冊表拉取鏡像映像
- 鎖定專用的節點池
- 允許 Pod 進入保留給 Tuist 工作負載的污點節點

### 工作負載身分與服務帳戶 {#helm-workload-identity}

Chart 會根據應用程式工作負載範圍限定服務帳戶，以便僅在需要的地方授予身分：

- `server.serviceAccount` 適用於 Tuist 伺服器部署和遷移作業
- `cache.serviceAccount` 適用於快取部署

例如，當快取在 EKS 上使用外部 S3 儲存貯體時，您可以為快取工作負載啟用 IRSA，而無需將相同的 IAM 角色附加到嵌入式資料庫：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 相容性覆寫 {#helm-compatibility-overrides}

Chart 將儲存和網格特定的調整設為選擇性加入，以保持預設值的可移植性：

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

- `cache.podSecurityContext` 預設為空。如果您的儲存類別或 CSI 驅動程式需要在掛載的卷上共用群組擁有權，請設定 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 的標準 `9000` 原生服務埠，當服務網格或平台保留與該埠衝突時可以更改。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，使 ClickHouse 對嵌入式內部日誌表（例如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 和 `system.part_log`）保持無限制的保留。設定它會一次性替換這些表，因此請與 `supersededTables: delete` 一起採用 — 請參閱 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制操作日誌保留期</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對於嵌入式 ClickHouse 伺服器日誌記錄器和 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不屬於任何表定義的一部分，因此更改它永遠不會替換表。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore`，並決定當 ClickHouse 替換系統日誌表時，如何處理其留下的 `<name>_N` 表。將其設為 `delete` 以在每次 `helm upgrade` 時刪除它們。
- 對 `ttlDays` 和 `level` 的編輯會在 ClickHouse Pod 下次重新啟動時生效，因為兩者都是 `subPath` 掛載，且當其 ConfigMap 更改時，chart 不會滾動更新 StatefulSet。

### 可觀測性 {#helm-observability}

Chart 包含一個可選的可觀測性堆疊（OpenTelemetry Collector、Prometheus、Grafana、Loki 和 Tempo）。它**預設為停用**。要在您的 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 即可使用，並已預先設定好日誌、追蹤和指標的下鑽功能。對於外部可觀測性，請保持此項停用，並透過 `server.extraEnv` 設定端點：

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

如需完整的可設定值清單，請參閱 chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 映像位於：
```
ghcr.io/tuist/tuist
```

發布的映像包含用於 `.xcactivitylog` 歸檔的嵌入式 Linux 建置處理，因此自託管部署可以在不運行任何額外服務的情況下處理建置 — `ProcessBuildWorker` Oban 作業在每個伺服器 Pod 中以進程內方式運行。如果您想將建置處理卸載到專用的副本集（例如，獨立於 Web 層擴展解析吞吐量），請在 Helm chart 中設定 `processor.enabled: true`：chart 會將同一個映像部署為僅佇列消費者（`TUIST_PROCESSOR_MODE=true`）。請參閱 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) 以取得完整的控制項清單。

> [!NOTE]
> `.xcresult` 解析依賴於 Xcode 中的 `xcresulttool`，因此只能在 macOS 上運行。CLI 為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 伺服器預設為 **本機** 處理模式，在開發者機器上解析 xcresult（該機器已具備用於建置本身的 Xcode）並上傳結構化結果。測試結果可在無需任何額外基礎設施的情況下被攝取。

### 拉取 Docker 映像 {#pulling-the-docker-image}

你可以執行以下指令來取得映像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

該映像同時發布了 `linux/amd64` 和 `linux/arm64` 版本，因此 Docker 會自動為主機選擇原生的 Linux 架構。

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像 {#deploying-the-docker-image}

Docker 映像的部署流程會根據你選擇的雲端供應商和你組織的持續部署方式而有所不同。由於大多數雲端解決方案和工具（例如 [Kubernetes](https://kubernetes.io/)）都將 Docker 映像作為基本單位，因此本節中的範例應該能與你現有的設定良好配合。

> [!WARNING]
> 如果你的部署管道需要驗證伺服器是否已啟動並運行，你可以向 `/ready` 發送 `GET` HTTP 請求，並斷言回應中的狀態碼為 `200`。


#### Fly {#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，你需要一個 `fly.toml` 設定檔。建議在你的持續部署 (CD) 管道中動態產生它。以下是供你參考的範例：

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

然後你可以執行 `fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署時，不要執行 `fly launch --local-only`，而是需要執行 `fly deploy --local-only`。Fly.io 不允許拉取私有 Docker 映像，這就是我們需要使用 `--local-only` 標誌的原因。


## Prometheus 指標 {#prometheus-metrics}

Tuist 在 `/metrics` 公開 Prometheus 指標，以幫助你監控自託管實例。這些指標包括：

### Finch HTTP 用戶端指標 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 用戶端，並公開有關 HTTP 請求的詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求持續時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - 桶區間：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求異常總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連線池佇列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連線池佇列中等待的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在使用前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶區間：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列異常總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連線指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所花費的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`error`
  - 桶區間：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 連線嘗試總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`

#### 發送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 發送請求所花費的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連線在發送前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶區間：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標都提供 `_bucket`、`_sum` 和 `_count` 變體，以便進行詳細分析。

### 其他指標

除了 Finch 指標外，Tuist 還公開以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳戶、專案等）
- 資料庫效能（使用 Tuist 託管基礎設施時）

## 營運 {#operations}

Tuist 在 `/ops/` 下提供一組實用工具，你可以用來管理你的實例。

> [!WARNING]
> **授權**
>
> 只有電子郵件網域符合 `TUIST_OPERATOR_EMAIL_DOMAIN`（預設為 `tuist.dev`）的已確認用戶才能存取 `/ops/` 端點。


- **錯誤（`/ops/errors`）：** 你可以檢視應用程式中發生的意外錯誤。這對於除錯和了解問題所在很有幫助，如果你遇到問題，我們可能會要求你與我們分享這些資訊。
- **儀表板（`/ops/dashboard`）：** 你可以檢視一個儀表板，它提供有關應用程式效能和健康狀況的洞察（例如記憶體消耗、正在執行的進程、請求數量）。這個儀表板對於了解你使用的硬體是否足以處理負載相當有用。
