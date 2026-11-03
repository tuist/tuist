---
{
  "title": "Server",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "學習如何喺你嘅基礎設施上部署 Tuist server。"
}
---
# 伺服器 {#server}

我哋提供 Tuist 伺服器嘅自託管版本，俾需要對基礎設施有更多控制權嘅組織使用。呢個版本允許你喺自己嘅基礎設施上託管 Tuist，確保你嘅數據保持安全同私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要合法有效嘅付費授權。Tuist 嘅本地部署版本只適用於 Enterprise 計劃嘅組織。如果你對呢個版本有興趣，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊式自託管快取節點技術已不建議用於新安裝。請參閱<.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link>以了解當前嘅自託管快取基礎設施。
>
> 現有部署仍然可以參考 GitHub Markdown 檢視器中嘅舊版源文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)同[快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發布：**canary**（每次提交到 `main`）、**release candidate**（每週一發布，測試一週）同**stable**（下週一提升）。只有穩定版本會移動 `:latest` 並作為預設解析；canary 同 release candidate 係 GitHub 預發布版本，你需要通過固定標籤來選擇使用。伺服器同 Kura 跟隨相同嘅每週發布列車，與 [Tuist CLI 嘅發布時間表](/en/cli/release-channels) 同步。

我哋遵循 [語義化版本](https://semver.org/) 以確保可預測嘅版本管理同兼容性。主要版本組件用於標記 Tuist 伺服器中需要與自託管用戶協調嘅破壞性變更；你唔應該預期我哋會經常使用它，如果真係需要，请放心，我哋會協助你順利過渡。

請參閱 <.localized_link href="/guides/server/self-host/release-channels">發布渠道</.localized_link> 頁面，了解每個渠道嘅發布方式、如何喺你嘅部署中固定一個渠道，以及建議嘅策略：讓生產環境保持在變動較慢嘅穩定線路，同時讓預演環境測試即將到來嘅發布。

## OAuth 升級同回滾邊界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 實體快取需要對現有安裝進行分階段升級。喺部署停止 OAuth 快取失效嘅版本之前，首先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 嘅權威讀取兼容版本部署到 **每個 OAuth 讀取器同寫入器**。呢個兼容階段首次出現喺 **1.355** 發布線中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；生產部署應喺提升後使用穩定嘅 `1.355.x` 版本。安裝喺 1.354 或更早版本嘅必須完成此階段，然後先升級到包含移除操作嘅後續版本。保持 1.355 線僅作兼容用途：唔好將失效移除回溯移植到其中。

原始兼容提交亦可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 獲取。另一個映像僅當佢保留權威讀取 **並保留舊版失效** 且舊消費者仍然存在時，才適合作為兼容階段。喺提供流量之前運行該階段嘅正常數據庫遷移，包括刷新令牌查找索引。

檢查每個環境中嘅所有 Web 副本、背景工作器、排程作業同單獨固定嘅處理器映像。等待兼容推廣完成，並喺移除失效之前驗證沒有剩餘嘅快取讀取二進制文件。唔好讓浮動映像標籤喺自動升級期間跳過此階段。沒有舊消費者嘅全新安裝不需要中間部署。

> [!WARNING]
> **保留權威讀取回滾目標**
>
> 移除失效後，普通滾動回滾必須針對 #14040 或另一個權威讀取版本。即使所有無失效程序已停止，保留嘅 OAuth 快取條目仍可能過時，並且重新啟動嘅快取讀取副本可以從對等節點導入它們。
>
> 進一步回滾需要停止並排空 **所有** 無失效 OAuth 消費者，然後喺啟動任何快取讀取消費者之前清除或替換 **每個** 保留嘅 Boruta 快取參與者。防止保留參與者重新加入。僅排空入口或僅重新啟動 Web 副本係不足夠嘅；請與你嘅 Tuist 支援聯絡人協調此恢復過程，而唔係自動清除快取或回滾數據庫遷移。

## 多副本集群 {#multi-replica-clustering}

支持嘅多副本 Web 部署需要 Erlang 集群以進行跨副本 Phoenix PubSub 同 Oban PG 通知，而非作為身份驗證權威。當 `server.cluster.enabled` 為 false 時，圖表會拒絕多個副本，包括可以增長超過一個副本嘅自動縮放器。先前接受嘅非集群部署必須計劃此升級，而唔係繞過保護措施。喺更改成員資格之前，完成 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括失效移除。

使用你嘅密鑰管理器喺發布命名空間中創建私有 cookie Secret，然後配置其名稱同密鑰：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必須具有高熵並由所有參與嘅 Web 副本共享。切勿使用嵌入喺發布映像中嘅 cookie：擁有分發 cookie 意味著可以喺其節點上執行遠程代碼。分佈式發布啟動現在拒絕缺少私有 `RELEASE_COOKIE` 或無效端口，包括明確配置嘅 `RELEASE_DISTRIBUTION=name` 或 `sname` 但沒有 DNS 發現。非圖表部署還必須一致地配置 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 同 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

使用普通伺服器連接嘅 `helm upgrade` 時，留空 `cookieExistingSecret` 會創建一個 cookie Secret 並喺後續升級中重用其當前值。離線 `helm template`、Argo CD 同其他沒有實時 Secret 查找嘅 GitOps 渲染器無法保留該生成值；它們必須使用由單獨管理、穩定嘅 Secret 支持嘅 `cookieExistingSecret`。唔好更改 cookie 密鑰以隱式輪換活動集群。Cookie 輪換需要協調每個參與者嘅遷移/重新啟動；僅更新 Secret 不會更新現有進程。

由映像內置 cookie 進行嘅首次推出會形成獨立嘅新舊成員資格島嶼，直到所有 Web 副本都使用私有 Secret。為實時更新規劃遷移窗口。後續嘅滾動部署會形成混合版本集群，因此請根據實際嘅新舊版本驗證 PubSub、Oban 通知同對等節點替換。呢啲通知唔係持久交付保證。喺回滾兼容版本時，保留一個具有權威讀取能力嘅回滾映像，並保持相同嘅私有 cookie。

僅允許受信任嘅伺服器對等節點之間訪問 EPMD（TCP 4369）同配置嘅分發端口，切勿來自租戶工作負載或公共網絡。驗證你環境中實際嘅入口/出口隔離；渲染 NetworkPolicy 並唔證明執行或後端可達性。處於持續負載下嘅雙副本金絲雀必須通過加入、滾動替換同故障/恢復測試先可以升級。DNS 用於發現對等節點，而唔係喺短暫失敗或部分響應時斷開健康節點；真實節點丟失同 OTP 分區預防仍然適用。libcluster 可能仍會記錄保留回調嘅成功「斷開」操作而唔關閉連接；應從節點上線/下線事件或 `Node.list()` 建立實際成員資格，而唔係僅憑該日誌行。

## 持續部署 {#continuous-deployment}

我哋建議將生產環境鎖定喺穩定嘅次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），以便日常升級只包含回溯修復。穩定版本線喺候選發布渠道浸泡一週後，於每週一 UTC 時間 06:00 提升；喺金絲雀或當前候選發布標籤上嘅預演環境可以喺問題影響用戶之前捕獲回歸。請參閱 <.localized_link href="/guides/server/self-host/release-channels">發布渠道</.localized_link> 以獲取推薦嘅鎖定策略。

如果你希望喺唔觸碰清單文件嘅情況下吸收新功能，請鎖定 `:latest`。該標籤每週一早上移動一次，因此請相應安排你嘅部署窗口。以下係一個 GitHub Actions 工作流示例，它按照該頻率檢查並部署最新嘅穩定映像：

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

自託管安裝可以允許受信任網絡上嘅開發人員喺唔登錄嘅情況下提交洞察、使用快取，或兩者兼有。儀表板同管理仍然需要身份驗證。

僅啟用你需要嘅功能：

| 伺服器環境變量 | 允許無需登錄 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交構建同測試洞察 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀寫快取嘅構建輸出 |

兩個設置默認都係 **關閉**，相互獨立，並適用於實例範圍內嘅所有帳戶同項目，包括私有項目。它們喺託管嘅 Tuist 上不可用，亦唔取代自託管許可證。

當 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 未設置時，先前嘅 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍作為兼容性後備。

> [!WARNING]
> 僅喺強制執行嘅辦公網絡或 VPN 邊界後面啟用呢啲設置。任何能夠訪問已啟用端點嘅人都可以提交報告，或者喺啟用快取訪問嘅情況下讀取同覆蓋快取輸出。這允許偽造遙測數據、快取投毒同容量耗盡。報告響應亦可能洩露私有項目句柄同構建系統。Tuist 唔會驗證 VPN 成員資格或信任轉發嘅 IP 頭部作為成員資格證明。

### 配置實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器同任何 Bazel BES 入口限制喺你嘅受信任網絡。
2. 喺升級客戶端之前升級每個伺服器同 Kura 副本。保持 Kura 身份驗證啟用，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑據；禁用它會繞過呢啲限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 配置你嘅快取端點。
3. 喺每個相關嘅 Tuist 伺服器副本上設置上述所需變量，然後重新啟動或重新部署它們。只有確切值 `true` 才能啟用設置。儀表板上沒有切換開關，亦沒有單獨嘅 Kura 標誌。

### 配置客戶端 {#network-trusted-client-configuration}

喺每個兼容嘅客戶端上配置最終嘅自託管伺服器 URL 同項目。當缺少憑據時，客戶端會自動發現哪些功能已啟用；無需客戶端選擇加入。發現過程唔會跟隨重定向。現有憑據繼續使用，無效或刷新失敗嘅憑據會導致錯誤而唔係匿名回退。重新登錄或明確登出以恢復。

喺啟用洞察訪問之前，將所有共享憑據嘅工具升級到能夠保留損壞或被拒絕憑據、拒絕無法讀取嘅憑據目錄，並從未簽名報告中省略 Git 來源嘅版本。較舊嘅工具可能會刪除憑據並無意中允許匿名回退；僅伺服器升級無法解決此問題。如果伺服器缺乏發現支持或回滾到較舊版本，客戶端必須進行身份驗證。先前嘅 `TUIST_NETWORK_TRUSTED_PUBLISHING` 客戶端設置不再適用。

- **洞察：** 僅提交已完成嘅 Xcode、Gradle、Elixir/Mix 同 Bazel 報告，唔包含歸檔、附件、覆蓋率、分片規劃或現有報告訪問。參與者聲明未經驗證；未簽名嘅遙測數據唔會驅動可信測試證據或自動化。請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 同 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南以獲取客戶端設置同隱私詳情。
- **快取：** 支持 CLI 編譯/模塊快取、Bazel 快取同 Gradle 任務快取。快取清除同遠程資產下載仍然需要憑據。唔支持嘅客戶端必須繼續進行身份驗證。
- **Bazel：** 報告需要明確嘅 `TUIST_BAZEL_BES_BACKEND` 同兼容嘅 Kura。快取同報告選項獨立啟用。更改憑據或任一設置後重新運行 `tuist bazel setup`；更改編譯快取配置後重新運行 `tuist cache config`。

報告請求限制為每個項目 8 MB、每分鐘 60 個請求同每日 10,000 個請求。為具有多個副本嘅部署範圍配額配置共享 Valkey；否則限制係按進程計算。如果配置嘅共享配額後端不可用，未簽名報告將被拒絕。同時添加入口連接、主體同速率限制。

### 禁用網絡可信訪問 {#disable-network-trusted-publishing}

將相關變數設為 `false`，然後重新啟動 **每個相關嘅伺服器副本**。舊副本喺被替換之前可以繼續接受無需憑據嘅請求。快取訪問會喺最後一個副本切換後 60 秒內停止處理新請求；進行中嘅傳輸唔會被取消。如果需要立即撤銷，請先喺入口處阻止流量。現有報告保留其通常嘅可見性同保留策略，已驗證嘅客戶端繼續正常工作。

## 運行時要求 {#runtime-requirements}

本節概述咗喺你嘅基礎設施上託管 Tuist 伺服器嘅要求。

### 兼容性矩陣 {#compatibility-matrix}

Tuist 伺服器已經過測試，並與以下最低版本兼容：

| 組件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能所需 |

### 運行 Docker 虛擬化映像 {#running-dockervirtualized-images}

我哋透過 [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像形式分發伺服器。

要運行它，你嘅基礎設施必須支持運行 Docker 映像。請注意，大多數基礎設施提供商都支持它，因為佢已經成為喺生產環境中分發同運行軟件嘅標準容器。

### Postgres 數據庫 {#postgres-database}

除咗運行 Docker 映像外，你仲需要一個 [Postgres 數據庫](https://www.postgresql.org/) 來存儲關係數據。大多數基礎設施提供商都喺其產品中包含 Postgres 數據庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 同 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待定嘅架構遷移。


### ClickHouse 數據庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來存儲同查詢大量分析數據。ClickHouse 對於構建洞察等功能係 **必需** 嘅。你可以選擇自行託管 ClickHouse 或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待定嘅 ClickHouse 架構遷移。

捆綁嘅 Docker Compose 同 Helm 嵌入式 ClickHouse 配置將 ClickHouse 文本日誌級別從映像嘅 `trace` 默認值降低到 `information`，這係 `system.text_log` 體積嘅主要來源。兩者都可以限制 ClickHouse 自身嘅 `system.*` 操作日誌表，否則這些表係無邊界嘅，但默認情況下此功能係關閉嘅 — 見下文。外部 ClickHouse 部署應該直接喺其 ClickHouse 服務中配置這些操作日誌。

#### ClickHouse 複製拓撲 {#clickhouse-replication-topology}

Tuist 背後嘅多副本 ClickHouse 僅喺 ClickHouse Cloud 上受支持。自行管理嘅 ClickHouse 係單副本。

攝取遷移發出普通嘅 `MergeTree` 引擎。喺 Cloud 上，這會透明地變成 `SharedMergeTree`，因此寫入會落入共享對象存儲，任何副本數量都可以工作。喺自行管理嘅 ClickHouse 上，`MergeTree` 僅寫入一個副本嘅本地磁盤；多副本設置要么靜默地喺副本之間拆分攝取，要么根據連接用戶上 `database_replicated_allow_only_replicated_engine` 嘅設置方式，以 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒絕 CREATE。

喺自行管理嘅 ClickHouse 上運行一個帶有一個副本嘅分片，並定期備份 ClickHouse 數據目錄。如果節點丟失，沒有第二個副本可以回退。

#### 限制操作日誌保留 {#capping-operational-log-retention}

保留可以應用於 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 同 `system.part_log`。

喺已有數據嘅實例上開啟它係一次性、單向嘅步驟，這就是為什麼兩個捆綁包都唔會為你執行此操作。任何保留窗口都會導致這些表定義不再匹配其配置，因此 ClickHouse 會將每個表重命名並開始一個新表，如 [被取代嘅日誌表](#superseded-log-tables) 下所述。留下嘅世代保留咗迄今為止積累嘅所有內容，並且自身不帶有任何保留策略，因此除非你喺同一步驟中回收它，否則它會永久留喺磁盤上，而新窗口僅限制從那時起寫入嘅行。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

該單一 `helm upgrade` 係自包含嘅，因為將 `ttlDays` 從空白改為設置會添加 drop-in 掛載並滾動 ClickHouse pod：它重新啟動，取代表，然後升級後作業會刪除它們。使用 `helm upgrade --wait` 部署，以便喺作業運行之前滾動 pod；否則世代會喺它查看之後出現，而下一次 `helm upgrade` 會改為回收它們。

使用 Docker Compose 時，取消註釋 `docker-compose.yml` 中 `clickhouse` 服務上嘅 `clickhouse-log-ttl.xml` 卷，並喺 `.env` 中設置兩個變數：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，你可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，以便後續嘅 ClickHouse 升級唔會自行丟棄歷史記錄。

#### 被取代嘅日誌表 {#superseded-log-tables}

ClickHouse 喺啟動時檢查每個系統日誌表是否仍然匹配其配置。如果不匹配，它會將現有表重命名為 `system.<name>_0`，然後係 `_1`、`_2` 等，並開始一個新表。當你更改保留窗口或進行更改系統日誌架構嘅任何 ClickHouse 升級時，就會發生這種情況。

重命名表唔會複製其數據，因此這唔會消耗額外嘅磁盤空間。被取代嘅表之後嘅情況取決於它來自哪個表，因為它保留咗被取代時活動表擁有嘅任何保留策略。第一次啟用保留時，被取代嘅表沒有任何保留策略，因此它會保留迄今為止積累嘅所有歷史記錄並無限期保留。隨後對窗口嘅更改會取代已經帶有 TTL 嘅表，因此這些表會自行過期並留下一個空表。ClickHouse 永遠唔會刪除表本身，因此喺長期運行嘅實例上，無論哪種方式它們都會積累。

默認情況下會保留被取代嘅表，以便升級永遠唔會自行丟棄操作歷史。將策略設置為 `delete` 以改為刪除它們，這會喺 `docker compose up` 同每次 `helm upgrade` 時發生：

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

刪除被取代嘅表會回收其磁盤空間。活動表永遠唔會被觸及，自從被取代以來寫入嘅行亦都唔會被觸及。

要喺不更改策略嘅情況下一次性回收空間，請手動刪除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 數據庫使用 `Atomic` 引擎，這會將普通嘅 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（默認為八分鐘）。`SYNC` 會立即刪除數據，當因為磁盤已滿而刪除這些表時，這正是你想要嘅。


### 存儲 {#storage}

你亦都需要一個解決方案來存儲文件（例如框架同庫嘅二進制文件）。Tuist 服務器支持 S3 兼容存儲同 Azure Blob Storage，用於存儲服務器擁有嘅構件。

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
3. 使用 `KURA_REGISTRATION_URL` 同 `KURA_ADVERTISED_HTTP_URL` 配置每個 Kura 節點。註冊心跳會告訴服務器它可以向 CLI 宣傳哪些就緒、面向客戶嘅 Kura 端點。

## 配置 {#configuration}

服務嘅配置係通過環境變數喺運行時完成嘅。鑑於這些變數嘅敏感性，我哋建議加密並將它們存儲喺安全嘅密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變數，確保它們永遠唔會顯示喺日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要嘅變數會喺啟動時進行驗證。如果缺少任何變數，啟動將失敗，錯誤消息將詳細說明缺失嘅變數。


### 許可證配置 {#license-configuration}

作為本地部署用戶，你會收到一個許可證，你需要將其作為環境變數公開。許可證用於驗證部署並確保服務喺協議條款範圍內運行。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務級別協議後提供嘅許可證。接受標準許可證密鑰或喺空氣隔離環境中使用嘅 base64 編碼證書，喺這些環境中服務器無法聯繫外部服務。 | 是 | | `******` |

> [!WARNING]
> **到期日期**
>
> 許可證有到期日期。如果許可證喺少於 30 天內到期，用戶喺使用與服務器交互嘅 Tuist 命令時會收到警告。如果你有興趣續訂許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境配置 {#base-environment-configuration}

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從互聯網訪問實例嘅基礎 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密信息嘅密鑰（例如 cookie 中嘅會話） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於生成哈希密碼嘅鹽 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於生成隨機令牌嘅密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於 AES-GCM 加密敏感數據嘅 32 字節密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | 當設為 `1` 時，會配置應用程式使用 IPv6 地址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程式使用嘅日誌級別 | 否 | `info` | [日誌級別](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 你嘅 GitHub 應用程式嘅 slug，取自 `https://github.com/apps/<slug>`。安裝應用程式時必需。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式解鎖額外功能（例如自動發布 PR 評論）嘅 base64 編碼私鑰 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程式解鎖額外功能（例如自動發布 PR 評論）嘅私鑰。**我哋建議改用 base64 編碼版本，以避免特殊字符引起嘅問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件地址以 `@<this-domain>` 結尾嘅已確認用戶可以訪問運營 URL（`/ops/*`） | 否 | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 喺儀表板導航欄中顯示為徽章嘅標籤，用於標識服務器實例（例如版本號或分支名稱） | 否 | 開發環境中嘅 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用 Web 服務器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許無需登錄即可提交構建和測試洞察。請參閱 [網絡信任訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許無需登錄即可讀寫緩存。請參閱 [網絡信任訪問](#network-trusted-access) 了解設置和安全要求。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 用於發送追蹤數據嘅 OpenTelemetry Collector 嘅 gRPC 端點 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 用於推送日誌嘅 Loki 兼容端點嘅基礎 URL（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **通過 HTTPS 提供應用程式**
>
> 會話 Cookie 被標記為 `Secure`，因此瀏覽器會喺純 `http://` 連接上丟棄它們，導致用戶無法登錄。請喺服務器前端終止 TLS（使用來自你內部 CA 嘅證書嘅反向代理即可），並將 `TUIST_APP_URL` 設置為 `https://` URL，即使係內部或僅限 VPN 嘅部署。

### 數據庫配置 {#database-configuration}

以下環境變數用於配置數據庫連接：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 訪問 Postgres 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程式表所使用嘅 PostgreSQL schema。當數據庫政策禁止使用 `public` schema 時，請設置此項。Schema 名稱必須係未經引用嘅 PostgreSQL 標識符。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用嘅可選 Postgres URL。當 `DATABASE_URL` 指向權限較窄嘅運行時角色時，請將此項設置為所有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程式表權限嘅運行時 Postgres 角色。當 Web 服務器不應以 schema 所有者身份連接時，請將此項與 `TUIST_MIGRATION_DATABASE_URL` 配合使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 訪問 ClickHouse 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 當設為 true 時，會使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連接數據庫 | 否 | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | 喺連接池中保持打開嘅連接數 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出嘅所有連接是否超過隊列間隔嘅時間間隔（以毫秒為單位）[（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 隊列中嘅閾值時間（以毫秒為單位），池使用此時間來決定是否開始丟棄新連接 [（更多資訊）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩存刷新之間嘅時間間隔（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新前嘅最大 ClickHouse 緩存大小（以字節為單位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要運行嘅 ClickHouse 緩存進程數 | 否 | `5` | `5` |

當 `TUIST_DATABASE_SCHEMA` 唔係 `public` 時，如果 schema 尚未存在，發佈遷移會喺運行 Ecto 遷移鏈之前創建該 schema。如果遷移角色無法創建 schema，請預先創建 schema 並將遷移角色設為其所有者。

Tuist 通過設置會話 `search_path` 將連接指向自定義 schema。某些池化或代理嘅 Postgres 設置（例如 PgBouncer，或限制啟動參數嘅託管數據庫）不會應用此設置，導致會話回退到 `public`，這會喺遷移期間顯示為 `permission denied for schema public`。通過此類設置連接時，請將 schema 固定喺角色本身，以便每個會話無論代理如何都從此 schema 開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 身份驗證環境配置 {#authentication-environment-configuration}

我哋通過 [身份提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進身份驗證。要使用此功能，請確保所選提供者所需嘅所有環境變數都存在於服務器環境中。**缺少變數** 會導致 Tuist 跳過該提供者。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登錄以及自助註冊係內置並默認啟用嘅。喺需要強制使用身份提供者（例如實施 SSO 時）嘅實例上，你可以完全關閉它們。這會從登錄體驗中移除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉所有匹配嘅服務器端端點，包括 CLI 使用嘅電子郵件/密碼端點（`tuist auth`）。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登錄和註冊。設置為 `0` 以從登錄頁面移除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉匹配嘅服務器端端點 | 否 | `1` | `0` |

#### 禁用已配置嘅身份提供者 {#disabling-a-configured-identity-provider}

默認情況下，只要配置了提供者，它就會作為登錄選項出現。要保持提供者已配置（其憑據仍然設置）同時將其從登錄和註冊頁面中移除，請將相應嘅開關設置為 `0`。對於 GitHub、Google 和 Apple，這也會關閉登錄回調，因此該方法將完全不可用。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄（請參閱 [GitHub](#github) 部分，了解為何 App 會與登錄共享其憑據） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登錄 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 已配置嘅 Okta 提供者是否作為登錄選項出現 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登錄 | 否 | `1` | `0` |

#### GitHub {#github}

我哋建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行身份驗證，但你也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保服務器環境中包含 GitHub 指定嘅所有必要環境變數。缺少變數會導致 Tuist 忽略 GitHub 身份驗證。要正確設置 GitHub app：
- 喺 GitHub app 嘅常規設置中：
    - 複製 `Client ID` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 創建並複製一個新嘅 `client secret` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設置為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以係你服務器嘅 IP 地址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀寫
  - 賬戶：
    - 電子郵件地址：只讀

喺 `Permissions and events` 嘅 `Account permissions` 部分，將 `Email addresses` 權限設置為 `Read-only`。

然後你需要喺 Tuist 服務器運行嘅環境中公開以下環境變數：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程序嘅客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程序嘅客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄。你為平台集成（PR 評論等）配置嘅 GitHub App 會與登錄共享其客戶端憑據，因此它會作為登錄選項出現。設置為 `0` 以保留 App 同時從登錄頁面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

你可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設置與 Google 嘅身份驗證。為此，你需要創建一個類型為 OAuth 客戶端 ID 嘅新憑據。創建憑據時，選擇「Web Application」作為應用程序類型，將其命名為 `Tuist`，並將重定向 URI 設置為 `{base_url}/users/auth/google/callback`，其中 `base_url` 係你託管服務運行嘅 URL。創建應用程序後，複製客戶端 ID 和密鑰，並分別將它們設置為環境變數 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意屏幕範圍**
>
> 你可能需要創建一個同意屏幕。當你這樣做時，請確保添加 `userinfo.email` 和 `openid` 範圍，並將應用程序標記為內部。


#### Okta {#okta}

你可以透過 [OAuth 2.0](https://oauth.net/2/) 協議啟用 Okta 身份驗證。你需要按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些指示</.localized_link>喺 Okta 上 [創建應用程序](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

喺設置 Okta 應用程序期間獲取客戶端 ID 和密鑰後，你需要設置以下環境變數：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於對 Okta 進行身份驗證嘅客戶端 ID。該數字應該係你嘅組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於對 Okta 進行身份驗證嘅客戶端密鑰 | 是 | | |

數字 `1` 需要替換為你嘅組織 ID。這通常係 1，但請檢查你嘅數據庫。

### 存儲環境配置 {#storage-environment-configuration}

 Tuist 需要存儲空間來存放透過 API 上傳嘅構建產物。要讓 Tuist 有效運行，**必須配置其中一種受支持嘅存儲解決方案**。

設置 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇服務器構建產物後端：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 服務器構建產物存儲後端。對於 S3 兼容存儲使用 `s3`，對於 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 兼容存儲 {#s3compliant-storages}

你可以使用任何 S3 兼容存儲提供商來存儲構建產物。需要以下環境變數來對存儲提供商進行身份驗證並配置集成：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於對存儲提供商進行身份驗證嘅訪問密鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於對存儲提供商進行身份驗證嘅秘密訪問密鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 存儲桶所在嘅區域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 存儲提供商嘅端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 用於存儲構建產物嘅存儲桶名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | 用於驗證 S3 HTTPS 連接嘅 PEM 編碼 CA 證書。對於使用自簽名證書或內部證書頒發機構嘅隔離環境非常有用。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立與存儲提供商連接嘅超時時間（以毫秒為單位） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從存儲提供商接收數據嘅超時時間（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 連接池連接到存儲提供商嘅超時時間（以毫秒為單位）。使用 `infinity` 表示無超時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連接嘅最大空閒時間（以毫秒為單位）。使用 `infinity` 以保持連接永久活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個池嘅最大連接數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用嘅連接池數量 | 否 | 系統調度器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連接到存儲提供商時使用嘅協議（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將存儲桶名稱構建為子域（虛擬主機） | 否 | `false` | `1` |

> [!NOTE]
> **使用來自環境變數嘅 Web 身份令牌進行 AWS 身份驗證**
>
> 如果你嘅存儲提供商係 AWS，並且你想使用 Web 身份令牌進行身份驗證，你可以將環境變數 `TUIST_S3_AUTHENTICATION_METHOD` 設置為 `aws_web_identity_token_from_env_vars`，Tuist 將使用常規嘅 AWS 環境變數採用該方法。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請按照 [這些文檔](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 獲取 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設置為 `https://storage.googleapis.com`。其他環境變數與任何其他 S3 兼容存儲相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，設置 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並配置 Azure 存儲帳戶憑據：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 存儲帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 嘅存儲帳戶訪問密鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 存儲服務器構建產物嘅容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略以使用 `https://<account>.blob.core.windows.net` | 否 | 從帳戶名稱派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 嘅 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm chart 時，設置 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。chart 頂層嘅 `objectStorage` 設置仍然與 S3 兼容，因為可選嘅緩存和註冊表鏡像工作負載仍然需要 S3 兼容存儲。如果禁用這些工作負載且服務器使用 Azure Blob，請設置 `objectStorage.mode=external` 並將外部對象存儲端點和憑據留空，以避免部署嵌入式 MinIO 服務。

#### 構建產物保留 {#artifact-retention}

在自託管實例上，默認情況下禁用構建產物清理。每種受支持嘅構建產物類型都有自己嘅環境變數。將變數設置為正整數天數以啟用該類型構建產物嘅清理。將變數留空或不設置僅會禁用該類型構建產物嘅清理。

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

所有六個鍵都是可選嘅。此示例啟用了每種受支持嘅構建產物類型，並具有獨立嘅保留窗口。省略某個鍵或將其值留空以保持禁用該類型構建產物嘅清理。自託管保留窗口沒有 30 天嘅上限。配置嘅值如果不是正整數，會導致服務器在啟動時失敗。

更改保留變數後重新啟動服務器。每個排隊嘅自託管清理批次在刪除文件之前都會檢查當前配置，因此取消設置或清空變數，或增加其窗口，也可以在重新啟動後保護文件免受待處理作業嘅影響。

| 環境變數 | 從對象存儲中刪除嘅構建產物文件 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 緩存、舊版內容尋址存儲緩存、模塊緩存和 Gradle 緩存文件 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | 應用預覽構建和圖標 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 當前和舊版構建歸檔 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 存儲在已過期運行構建產物前綴下嘅所有對象，包括結果包、調用記錄和會話歸檔 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片包 |

計劃清理僅刪除構建產物 blob。它保留相應嘅 PostgreSQL 和 ClickHouse 行，因此在下載過期後，構建、測試、運行、預覽和分片中繼數據仍可在儀表板中可見。此配置不會更改 ClickHouse 表保留規則。

### 電子郵件配置 {#email-configuration}

Tuist 需要電子郵件功能用於用戶身份驗證和事務性通知（例如，密碼重置、帳戶通知）。目前，**僅支持 Mailgun** 作為電子郵件提供商。

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於向 Mailgun 進行身份驗證嘅 API 密鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件嘅域 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將出現在「發件人」字段中嘅電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用於用戶回覆嘅可選回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新用戶註冊嘅電子郵件確認。啟用後，用戶將自動確認並可以在註冊後立即登錄 | 否 | 如果未配置電子郵件則為 `true`，如果已配置電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅當你想發送電子郵件時才需要電子郵件配置變數。如果未配置，則自動跳過電子郵件確認

> [!NOTE]
> **SMTP 支持**
>
> 目前不提供通用 SMTP 支持。如果你需要為本地部署提供 SMTP 支持，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 討論你嘅需求。


> [!NOTE]
> **隔離網絡部署**
>
> 對於沒有互聯網訪問或電子郵件提供商配置嘅本地安裝，默認情況下會自動跳過電子郵件確認。用戶可以在註冊後立即登錄。如果你已配置電子郵件但仍想跳過確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。如果要在配置電子郵件時要求電子郵件確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。


### Git 平台配置 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台集成</.localized_link>，以提供額外功能，例如自動在你嘅拉取請求中發布評論。

#### GitHub {#platform-github}

自託管嘅 Tuist 服務器無法安裝運行於 `https://tuist.dev` 嘅 GitHub App。GitHub App 綁定到註冊它們嘅服務器，因此你嘅部署需要在 github.com 上有自己嘅 App。

##### 註冊 App {#platform-github-registering-the-app}

[創建一個 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)，由你嘅 GitHub 組織擁有。你可以重用為身份驗證創建嘅 App，除非你創建嘅是 OAuth App。使用以下內容進行配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 嘅值：

| 設置 | 值 |
| --- | --- |
| 回調 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設置 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重定向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任何隨機字符串。你將將其設置為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予以下存儲庫權限：

| 權限 | 訪問 |
| --- | --- |
| 內容 | 只讀 |
| 元數據 | 只讀 |
| Issues | 讀寫 |
| Pull requests | 讀寫 |
| Checks | 讀寫 |

同時授予 **成員：只讀** 組織權限。在 github.com 設置期間，Tuist 會檢查連接組織安裝嘅人是否為活躍嘅 GitHub 組織所有者，而不僅僅是能夠訪問其某個存儲庫嘅人。

訂閱 App 嘅 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **在安裝期間請求用戶授權 (OAuth)** 禁用，以便 GitHub 將安裝程序發送到設置 URL。Tuist 使用額外嘅 `/integrations/github/authorize` 回調啟動單獨嘅授權步驟以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝程序然後選擇一個 Tuist 組織；在 Tuist 中開始嘅安裝保留其組織。

##### 配置服務器 {#platform-github-configuring-the-server}

設置以下環境變數，然後重新啟動服務器：

| 環境變數 | 描述 | 必需 | 預設 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 嘅 slug，即其公開頁面 URL `https://github.com/apps/<slug>` 嘅最後路徑組件 | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式嘅客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式嘅客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程式嘅 base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，後者對平台處理換行符嘅方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程式上配置嘅 webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **配置所有必需嘅 App 憑證**
>
> 組織集成頁面上嘅 **安裝 GitHub App** 按鈕會保持禁用狀態，直到設置好 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私鑰。數字 `TUIST_GITHUB_APP_ID` 亦需要用於驗證安裝所有權。安裝 URL 嵌入咗 App slug，因此缺少 `TUIST_GITHUB_APP_NAME` 特別會導致 GitHub 返回 404 錯誤嘅鏈接。

服務器重新啟動後，組織管理員按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 安裝 App 並將存儲庫連接到項目。

##### OIDC 身份驗證依賴於此 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份驗證</.localized_link> 會根據連接到你項目嘅存儲庫解析 CI 令牌中嘅存儲庫聲明，而連接只能通過已安裝嘅 GitHub App 創建。在你嘅 CI 工作流運行 `tuist auth login` 且沒有令牌之前，請完成上述設置。

你嘅 Tuist 服務器还需要出站訪問你嘅 CI 提供商嘅 OIDC 頒發者以獲取其簽名密鑰：

| CI 提供商 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變數僅配置 Tuist 嘅 github.com App。要將 Tuist 與 GitHub Enterprise Server (GHES) 實例集成，組織管理員需切換到集成頁面上嘅 **企業服務器** 標籤並輸入 GHES 基礎 URL — Tuist 會引導他們通過 GitHub 嘅 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 實例上註冊一個新嘅 Tuist App。新 App 嘅憑證會按安裝加密存儲；不需要額外嘅 `TUIST_GITHUB_APP_*` 環境變數。

#### Origin {#platform-origin}

自託管嘅 Tuist 服務器需要自己嘅 Origin app，並配置你部署嘅 URL 和簽名密鑰。為每個 Tuist 環境註冊單獨嘅 app，以使安裝和憑證保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支持 Ed25519 嘅 OpenSSL 生成 Ed25519 簽名密鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設置](https://cursor.com/codebase/settings/apps) 中創建一個 app。將 `origin-app-public.pem` 嘅內容註冊為其公共簽名密鑰。保密 `origin-app-private.pem`；你會將其提供給 Tuist 服務器，而不是上傳到 Cursor。
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
| `repository:pull_requests:reviews:write` | 讀取、發布和更新報告評論。Origin 包含相應嘅 review-read 權限。 |
| `repository:metadata:read` | 發現存儲庫並讀取其默認分支。由 Origin 自動授予。 |

保持可選嘅存儲庫 webhook 事件未選中。安裝生命週期通知已足夠；不需要源代碼訪問、合併權限和 check-run 權限。

##### 配置服務器 {#platform-origin-configuring-the-server}

設置以下環境變數，然後重新啟動服務器：

| 環境變數 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設置複製嘅 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 嘅完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私鑰存儲在你部署嘅密鑰管理器中。保留其多行 PEM 格式；此設置不接受 base64 編碼嘅替換。切勿將密鑰提交到源代碼控制或在日誌中暴露。兩個變數必須屬於同一個註冊嘅 app。

你嘅 Tuist 服務器需要出站 HTTPS 訪問 `api.cursor.com`。Cursor 必須能夠將請求發送到 webhook URL，並且管理員必須能夠在瀏覽器中返回重定向 URI。兩個註冊嘅 URL 必須與你部署嘅 HTTPS 基礎 URL 匹配。

##### 安裝 App {#platform-origin-installing-the-app}

服務器重新啟動後，管理員打開 **設置 → 集成**，在 Origin 下選擇 **連接**，並批准 app 對適當嘅 Origin 帳戶和存儲庫嘅訪問權限。Tuist 組織在此流程中得以保留。直接從 Origin 發起嘅安裝會提示管理員登錄並選擇要連接嘅 Tuist 組織。然後他們選擇 **添加新項目連接** 以將 Tuist 項目鏈接到本機存儲庫。

按照 <.localized_link href="/guides/integrations/gitforge/origin">Origin 集成指南</.localized_link> 了解項目連接和結果上傳要求。安裝 app 不會啟動構建或測試工作流；這些工作流繼續向你嘅 Tuist 服務器報告結果。

## 本地測試 {#testing-locally}

我哋提供一個全面嘅 Docker Compose 配置，其中包含在部署到你嘅基礎設施之前在本地機器上測試 Tuist 服務器所需嘅所有依賴項：

- PostgreSQL 15
- ClickHouse 26.5 用於分析
- ClickHouse Keeper 用於協調
- MinIO 用於兼容 S3 嘅存儲
- Kura 用於本地自託管緩存測試
- pgweb 用於數據庫管理

> [!CAUTION]
> **需要許可證**
>
> 運行 Tuist 服務器（包括本地開發實例）在法律上需要有效嘅 `TUIST_LICENSE` 環境變數。如果你需要許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


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

   捆綁嘅 ClickHouse 服務接受這些可選嘅操作日誌控制：

   | 環境變數 | 描述 | 默認值 | 示例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 同 `part_log`）嘅保留期（以日為單位） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 服務器日誌記錄器同 `system.text_log` 級別 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 取代系統日誌表時，點樣處理佢留下嘅 `<name>_N` 表。`ignore` 會保留佢哋，`delete` 會刪除佢哋 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   喺 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 同依賴映像嘅 `linux/arm64` 變體。如果要強制使用 amd64 模擬進行調試，請使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 運行 Compose。

   捆綁嘅 compose 文件使用命名嘅 Docker 卷來存儲持久數據。如果你用主機綁定掛載替換佢哋，請先創建主機目錄，並確保容器用戶可以寫入，特別係 ClickHouse 同 ClickHouse Keeper 嘅數據目錄。

4. 喺 http://localhost:8080 訪問服務器

**服務端點：**
- Tuist Server: http://localhost:8080
- Kura 緩存（HTTP + REAPI gRPC 共用一個端口）：http://localhost:4000
- MinIO Console: http://localhost:9003（憑證：`tuist` / `tuist_dev_password`）
- MinIO API: http://localhost:9002
- pgweb（PostgreSQL UI）：http://localhost:8081
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

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整嘅 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變數示例文件

## 使用 Helm 部署 Kubernetes {#kubernetes-with-helm}

Tuist 提供官方 Helm chart 用於喺 Kubernetes 上部署。該 chart 打包咗 Tuist 服務器同緩存服務，以及嵌入式基礎設施依賴項，你可以根據需要將佢哋替換為外部提供商。

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

`server.license.key` 值接受標準許可證密鑰，對於隔離網絡安裝，亦接受 Base64 編碼嘅許可證證書；服務器會自動檢測係邊一種。

使用 `--set` 傳遞許可證適用於快速安裝。如果你將值保存喺版本控制中，請將許可證存儲喺 Helm 之外管理嘅 Kubernetes Secret 中（例如使用 Vault、Sealed Secrets 或 SOPS），並將 chart 指向佢：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下嘅條目命名咗你 Secret 中保存許可證值嘅字段，該值可以係許可證密鑰，或者對於隔離網絡安裝，係 Base64 編碼嘅許可證證書。`existingSecretKeys` 下嘅每個條目默認為 chart 自己嘅密鑰名稱，因此將你 Secret 中不包含嘅條目設置為空字符串，如上所述嘅 `certificateBase64`。否則，pod 會引用不存在嘅密鑰並無法啟動。喺安裝或升級 chart 之前，請喺 release namespace 中創建 Secret。

只通過一個來源配置許可證：`server.license.key` 或 `server.license.existingSecret`。如果未設置任何來源或組合咗來源，chart 將無法渲染。通過 `server.extraEnv` 傳遞嘅許可證不計為來源，因此請改用 `existingSecret`。

### 基礎設施依賴項 {#helm-infrastructure-dependencies}

該 chart 管理三個基礎設施依賴項：`postgresql`、`clickhouse` 同 `objectStorage`。每個都默認為 **embedded** 模式，即 chart 將佢哋部署喺集群內部。如果要指向你自己嘅外部實例，請將依賴項嘅 `mode` 設置為 `external` 並喺你嘅 `values.yaml` 中填寫連接詳情。例如，要使用外部 PostgreSQL 數據庫：

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

Chart 從 Secret 中讀取主機、用戶名同密碼，並通過 Kubernetes 環境變量替換組成 `DATABASE_URL`，因此密碼不會渲染到 Helm manifest 中。Secret 嘅密碼值應該係 URL 安全嘅，因為它會被插入到數據庫 URL 中。

相同嘅模式適用於 `clickhouse` 同 `objectStorage`。請參閱 chart 嘅 `values.yaml` 中每個部分下嘅 `external` 塊，以獲取可配置字段嘅完整集合。

### 共享調度同標籤 {#helm-shared-scheduling-and-labels}

Chart 喺 `global` 下公開咗一組共享嘅 pod 設置，讓運維人員可以調整部署以適應佢哋嘅集群，而無需為每個工作負載重複相同嘅值：

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

當你需要以下操作時使用呢啲設置：

- 為每個 pod 添加集群特定嘅標籤
- 從私有倉庫拉取鏡像
- 定位到專用節點池
- 允許 pod 運行喺為 Tuist 工作負載保留嘅污點節點上

### 工作負載身份同服務帳戶 {#helm-workload-identity}

Chart 按應用程序工作負載劃分服務帳戶範圍，以便你只喺需要嘅地方授予身份：

- `server.serviceAccount` 適用於 Tuist 服務器部署同遷移任務
- `cache.serviceAccount` 適用於緩存部署

例如，當緩存喺 EKS 上使用外部 S3 存儲桶時，你可以為緩存工作負載啟用 IRSA，而無需將相同嘅 IAM 角色附加到嵌入式數據庫：

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

僅喺你嘅集群需要時才使用呢啲覆蓋：

- `cache.podSecurityContext` 默認為空。如果你嘅存儲類或 CSI 驅動程序需要喺掛載卷上共享組所有權，請設置 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 默認為 ClickHouse 嘅標準 `9000` 原生服務端口，當服務網格或平台保留與該端口衝突時可以更改。
- `clickhouse.embedded.systemLogs.ttlDays` 默認為空，保留 ClickHouse 喺嵌入式內部日誌表（例如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 同 `system.part_log`）上嘅無限制保留。設置它會一次性覆蓋呢啲表，因此請與 `supersededTables: delete` 一起採用 — 參見 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制運營日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對於嵌入式 ClickHouse 服務器日誌記錄器同 `system.text_log` 默認為 `information`。與 `ttlDays` 不同，它不屬於任何表定義，因此更改它永遠不會覆蓋表。
- `clickhouse.embedded.systemLogs.supersededTables` 默認為 `ignore` 並決定當 ClickHouse 覆蓋系統日誌表時 `<name>_N` 表嘅處理方式。將其設置為 `delete` 以喺每次 `helm upgrade` 時刪除佢哋。
- 對 `ttlDays` 同 `level` 嘅編輯會喺 ClickHouse pod 下次重啟時生效，因為兩者都係 `subPath` 掛載，並且 Chart 喺其 ConfigMap 更改時不會滾動 StatefulSet。

### 可觀察性 {#helm-observability}

Chart 包含一個可選嘅可觀察性堆棧（OpenTelemetry Collector、Prometheus、Grafana、Loki 同 Tempo）。它 **默認禁用**。要喺你嘅 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 可用，並預配置咗日誌、追蹤同指標下鑽。對於外部可觀察性，請保持此功能禁用並通過 `server.extraEnv` 配置端點：

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

有關可配置值嘅完整列表，請參閱 Chart 嘅 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 映像可用於：
```
ghcr.io/tuist/tuist
```

發布嘅映像包含用於 `.xcactivitylog` 歸檔嘅嵌入式 Linux 構建處理，因此自託管部署可以處理構建而無需運行任何其他服務 — `ProcessBuildWorker` Oban 任務喺每個服務器 pod 上進程內運行。如果你想將構建處理卸載到專用副本集（例如，獨立於 Web 層擴展解析吞吐量），請喺 Helm Chart 中設置 `processor.enabled: true`：Chart 將同一映像部署為僅隊列消費者（`TUIST_PROCESSOR_MODE=true`）。有關完整嘅控制選項，請參見 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

> [!NOTE]
> `.xcresult` 解析依賴 Xcode 中嘅 `xcresulttool`，因此只能喺 macOS 上運行。CLI 為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 服務器默認為 **local** 處理模式，喺開發者機器上解析 xcresult（該機器已經有 Xcode 用於構建本身）並上傳結構化結果。測試結果喺無需任何額外基礎設施嘅情況下被攝取。

### 拉取 Docker 映像 {#pulling-the-docker-image}

你可以通過執行以下命令來檢索映像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

映像發布咗 `linux/amd64` 同 `linux/arm64` 兩個版本，因此 Docker 會自動為主機選擇原生 Linux 架構。

或者拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像 {#deploying-the-docker-image}

Docker 映像嘅部署過程將根據你選擇嘅雲提供商同你組織嘅持續部署方法而有所不同。由於大多數雲解決方案同工具（如 [Kubernetes](https://kubernetes.io/)）都將 Docker 映像用作基本單元，因此本節中嘅示例應該與你現有嘅設置很好地對齊。

> [!WARNING]
> 如果你嘅部署流水線需要驗證服務器是否已啟動並運行，你可以向 `/ready` 發送 `GET` HTTP 請求並斷言響應中嘅 `200` 狀態碼。


#### Fly {#fly}

要喺 [Fly](https://fly.io/) 上部署應用程序，你需要一個 `fly.toml` 配置文件。考慮喺你嘅持續部署 (CD) 流水線中動態生成它。下面係供你參考嘅示例：

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

然後你可以運行 `fly launch --local-only --no-deploy` 來啟動應用程序。喺後續部署中，與其運行 `fly launch --local-only`，你需要運行 `fly deploy --local-only`。Fly.io 不允許拉取私有 Docker 映像，這就係我哋需要使用 `--local-only` 標誌嘅原因。


## Prometheus 指標 {#prometheus-metrics}

Tuist 喺 `/metrics` 公開 Prometheus 指標，幫你監察你自託管嘅實例。呢啲指標包括：

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
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 喺連接池隊列中等待嘅時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連接喺被使用前閒置嘅時間（直方圖）
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
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連接喺發送前閒置嘅時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方圖指標都提供 `_bucket`、`_sum` 同 `_count` 變體以供詳細分析。

### 其他指標

除咗 Finch 指標之外，Tuist 亦公開以下指標：
- BEAM 虛擬機性能
- 自定義業務邏輯指標（存儲、帳戶、項目等）
- 數據庫性能（當使用 Tuist 託管基礎設施時）

## 運維 {#operations}

Tuist 喺 `/ops/` 下提供一組實用工具，你可以用嚟管理你嘅實例。

> [!WARNING]
> **授權**
>
> 只有電郵域名符合 `TUIST_OPERATOR_EMAIL_DOMAIN`（預設為 `tuist.dev`）嘅已確認用戶先可以存取 `/ops/` 端點。


- **錯誤（`/ops/errors`）：** 你可以檢視應用程式中發生嘅意外錯誤。呢個功能對除錯同了解問題所在好有用，如果你遇到問題，我哋可能會請你分享呢啲資訊。
- **儀表板（`/ops/dashboard`）：** 你可以檢視一個儀表板，提供有關應用程式性能同健康狀況嘅洞察（例如記憶體消耗、運行中嘅進程、請求數量）。呢個儀表板對於了解你所用嘅硬件是否足以處理負載相當有用。
