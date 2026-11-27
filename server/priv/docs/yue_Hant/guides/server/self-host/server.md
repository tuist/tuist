---
{
  "title": "Server",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "了解如何喺你嘅基礎設施上部署 Tuist server。"
}
---
# 伺服器 {#server}

我哋提供 Tuist 伺服器嘅自託管版本，俾需要對基礎設施有更多控制權嘅組織。呢個版本允許你喺自己嘅基礎設施上託管 Tuist，確保你嘅數據保持安全同私密。

> [!WARNING]
> **需要授權**
>
> 自託管 Tuist 需要合法有效嘅付費授權。Tuist 嘅內部部署版本只適用於 Enterprise 計劃嘅組織。如果你對呢個版本有興趣，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **舊版快取服務**
>
> 舊嘅自託管快取節點技術已棄用，唔建議新安裝使用。請參考 <.localized_link href="/guides/features/cache/self-hosting">自託管快取指南</.localized_link> 以獲取當前自託管快取基礎設施嘅資訊。
>
> 現有部署仍然可以喺 GitHub 嘅 Markdown 檢視器中參考舊版源文件：[快取節點](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) 同 [快取架構](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 發布節奏 {#release-cadence}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像頻道發布：**canary**（每次提交到 `main`）、**release candidate**（每週一發布，測試一週）同 **stable**（下週一提升）。只有穩定版本會移動 `:latest` 並默認解析；canary 同 release candidate 係 GitHub 預發布版本，你需要通過固定標籤來選擇使用。伺服器同 Kura 跟隨相同嘅每週發布列車，與 <.localized_link href="/cli/release/channels">Tuist CLI 嘅發布時間表</.localized_link> 同步。

我哋遵循 [語義化版本控制](https://semver.org/) 以確保可預測嘅版本控制同兼容性。主要版本用於標記 Tuist 伺服器中需要與自託管用戶協調嘅破壞性變更；你唔應該預期我哋會經常使用它，如果真係需要，請放心我哋會協助你順利過渡。

請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布頻道</.localized_link> 頁面，了解每個頻道嘅發布方式、如何喺你嘅部署中固定一個頻道，以及推薦嘅策略：讓生產環境保持在緩慢移動嘅穩定線上，同時讓暫存環境測試即將到來嘅發布。

## 瀏覽器會話升級 {#browser-session-upgrade}

瀏覽器會話喺七日內沒有經過認證嘅頁面請求或 LiveView 互動後過期，且最遲喺認證後 30 日過期。「記住我」會恢復相同嘅伺服器端會話，但無法延長任何一個截止日期。活動每分鐘檢查一次，因此閒置會話可能提前最多 59 秒過期。WebSocket 心跳、自動重新連接同背景更新不會刷新活動。呢些截止日期不會改變機器憑證或 API 令牌嘅有效期。

喺啟動升級後嘅應用程序進程之前，運行附加嘅 `users_tokens` 遷移。現有記錄不會回填：它們嘅創建時間限制咗不活動時間同絕對過期時間，並且喺訪問強制 SSO 嘅組織之前必須重新認證。回調嘅提供者、發行者或已驗證嘅 Workspace，以及自定義 SSO 連接會儲存喺伺服器端，並與組織嘅當前設置進行比較。關聯賬戶並非會話認證證明。

喺將策略視為強制執行之前，升級每個提供服務嘅 Web 副本。舊版本二進制文件仍然可以接受以前嘅 60 日會話，並且不強制執行新嘅 LiveView 邊界；混合版本喺模式上兼容，但策略上不等效。預計用戶需要重新登錄。回滾到舊版本二進制文件會削弱呢些控制；如果需要模式回滾，請喺刪除新字段之前停止所有讀取新字段嘅二進制文件。切勿延長舊會話或推斷來源以避免重新認證。

## 驗證器應用程式 MFA {#authenticator-app-mfa}

伺服器包含原生驗證器應用程式（TOTP）雙因素認證。儀表板尚未連結到它；後續版本會添加設置入口點。它不需要激活標誌、託管服務依賴或身份提供者憑證：只需要 PostgreSQL、下面嘅遷移、TOTP 驗證器，以及由所有服務副本共享嘅穩定加密密鑰（`TUIST_SECRET_KEY_ENCRYPTION`，回退到 `TUIST_SECRET_KEY_BASE`）。保持伺服器同驗證器時鐘同步。MFA 驗證及其每五分鐘五次失敗代碼嘅共享預算使用 PostgreSQL 行鎖，而非 Redis。

設置需要喺最近五分鐘內登錄，將設置密鑰輸入 TOTP 驗證器應用程式，並確認應用程式生成嘅代碼。十個單次使用嘅恢復代碼只會顯示一次；請安全儲存它們。禁用該因素也需要最近嘅登錄以及未使用嘅驗證器或恢復代碼。更改因素會撤銷其他瀏覽器會話。重置密碼不會移除 MFA，並且此實現不提供僅通過電子郵件或管理員繞過丟失因素嘅方法。

一旦註冊，每次新嘅瀏覽器登錄——包括聯合登錄——都需要原生第二因素，然後才能接收會話或完成基於瀏覽器嘅 CLI/設備授權。直接密碼同 Apple API 登錄會拒絕已註冊用戶，並指示他們使用瀏覽器登錄。已註冊用戶嘅新電子郵件代理聲明需要經過 MFA 驗證嘅瀏覽器會話；僅郵箱嘅舊版聲明會被拒絕。現有 API 令牌、機器憑證、工作負載身份及其續訂規則保持不變。這係可選嘅每用戶支持，並非組織範圍內嘅 MFA 強制要求，亦非驗證身份提供者自身嘅 MFA 策略。組織 SSO 仍然需要正確配置嘅提供者/發行者，加上原生因素。

註冊、登錄、使用恢復代碼或禁用 MFA 都不需要電子郵件。因素更改通知係盡力而為；交付失敗不會撤銷已完成嘅更改。

喺新二進制檔案之前，運行獨立嘅附加 `user_mfa`/`users_tokens.mfa_verified_at` 遷移。TOTP 密鑰使用現有嘅 Vault 加密密鑰；請保留該密鑰及其備份。喺允許 MFA 註冊之前，完成 **所有認證服務副本** 嘅升級。舊版二進制檔案可以繞過原生 MFA，因此喺註冊後，它們並非策略兼容嘅回滾目標。刪除 MFA 架構會破壞註冊同恢復狀態；請先停止讀取器並保留加密備份。混合版本架構兼容性並唔係 MFA 或瀏覽器會話控制已強制執行嘅證據。

## OAuth 升級同回滾邊界 {#oauth-upgrade-and-rollback-boundary}

OAuth 實體緩存移除需要對現有安裝進行分階段升級。喺部署停止 OAuth 緩存失效嘅版本之前，首先將來自 [#14040](https://github.com/tuist/tuist/pull/14040) 嘅權威讀取兼容版本部署到 **每個 OAuth 讀取器同寫入器**。此兼容階段首次出現喺 **1.355** 發布系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升，生產部署應使用穩定嘅 `1.355.x` 版本。1.354 或更早版本嘅安裝必須喺升級到包含移除功能嘅後續版本之前完成此階段。保持 1.355 系列僅作兼容用途：唔好將失效移除反向移植到其中。

原始兼容提交亦可作為 `ghcr.io/tuist/tuist:sha-c8e54471a425` 使用。另一個映像僅喺保留權威讀取 **並保留舊版失效** 同時舊消費者仍然存在時，才適合作為兼容階段。喺提供流量之前，運行該階段嘅正常數據庫遷移，包括刷新令牌查找索引。

檢查每個環境中嘅所有 Web 副本、後台工作器、計劃任務同單獨鎖定嘅處理器映像。等待兼容推廣完成，並喺移除失效之前驗證沒有剩餘嘅緩存讀取二進制檔案。唔好讓浮動映像標籤喺自動升級期間跳過此階段。沒有舊消費者嘅全新安裝唔需要中間部署。

> [!WARNING]
> **保留權威讀取回滾目標**
>
> 移除失效後，普通滾動回滾必須針對 #14040 或另一個權威讀取版本。即使每個無失效進程都已停止，保留嘅 OAuth 緩存條目仍可能過時，並且重新啟動嘅緩存讀取副本可以從對等節點導入它們。
>
> 進一步回滾需要停止並排空 **所有** 無失效 OAuth 消費者，然後喺啟動任何緩存讀取消費者之前清除或替換 **每個** 保留嘅 Boruta 緩存參與者。防止保留參與者重新加入。僅排空入口或僅重新啟動 Web 副本並唔足夠；請與你嘅 Tuist 支持聯繫人協調此恢復操作，而唔係自動清除緩存或回滾數據庫遷移。

## 多副本集群 {#multi-replica-clustering}

支持嘅多副本 Web 部署需要 Erlang 集群用於跨副本 Phoenix PubSub 同 Oban PG 通知，而非作為認證權威。當 `server.cluster.enabled` 為 false 時，圖表會拒絕多個副本，包括可以擴展到超過一個副本嘅自動縮放器。先前接受嘅非集群部署必須計劃此升級，而唔係繞過保護措施。喺更改成員資格之前，完成 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升級序列</.localized_link>，包括失效移除。

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

Cookie 必須具有高熵並由所有參與嘅 Web 副本共享。切勿使用嵌入喺發布映像中嘅 Cookie：擁有分發 Cookie 即授予喺其節點上遠程執行嘅權限。分佈式發布啟動現在拒絕缺少私有 `RELEASE_COOKIE` 或無效端口，包括明確配置嘅 `RELEASE_DISTRIBUTION=name` 或 `sname` 而沒有 DNS 發現嘅情況。非圖表部署還必須一致地配置 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 同 Pod IP/節點名稱。發現目前使用 IPv4 A 記錄。

通過普通伺服器連接嘅 `helm upgrade`，將 `cookieExistingSecret` 留空會創建 Cookie Secret 並喺後續升級中重用其當前值。離線 `helm template`、Argo CD 同其他沒有實時 Secret 查找嘅 GitOps 渲染器無法保留該生成值；它們必須使用由單獨管理嘅穩定 Secret 支持嘅 `cookieExistingSecret`。唔好更改 Cookie 密鑰以隱式輪換活動集群。Cookie 輪換需要協調每個參與者嘅遷移/重新啟動；僅更新 Secret 並唔會更新現有進程。

從映像內置 Cookie 進行嘅首次推廣會形成獨立嘅新舊成員島嶼，直到所有 Web 副本都使用私有 Secret。為實時更新規劃遷移窗口。後續滾動部署會形成混合版本集群，因此請根據實際新舊版本限定 PubSub、Oban 通知同對等節點替換。這些通知並唔係持久交付保證。保留權威讀取回滾映像，並喺回滾兼容版本時保留相同嘅私有 Cookie。

僅允許受信任嘅伺服器對等節點之間訪問 EPMD（TCP 4369）同配置嘅分發端口，絕不允許來自租戶工作負載或公共網絡嘅訪問。驗證你環境中嘅實際入口/出口隔離；渲染 NetworkPolicy 並唔證明強制執行或後端可達性。喺連續負載下嘅雙副本金絲雀必須通過加入、滾動替換同故障/恢復測試才能提升。DNS 用於發現對等節點，而唔係喺暫時失敗或部分響應時斷開健康節點；真實節點丟失同 OTP 分區預防仍然適用。libcluster 可能仍會為保留回調記錄成功嘅「斷開」操作而唔關閉連接；從節點上線/下線事件或 `Node.list()` 建立實際成員資格，而唔係僅憑該日誌行。

## 持續部署 {#continuous-deployment}

我哋建議將生產環境鎖定喺穩定嘅次要版本線（例如 `ghcr.io/tuist/tuist:1.351`），咁日常升級就只會包含回溯修復。穩定版本線會喺每個星期一 UTC 時間 06:00 推出，前提係已經喺候選發布渠道進行咗一週嘅浸泡測試；喺金絲雀或當前候選發布標籤上嘅預備環境可以喺問題影響到你嘅用戶之前捕捉到回歸錯誤。請參閱 <.localized_link href="/guides/server/self-host/release/channels">發布渠道</.localized_link> 以了解建議嘅鎖定策略。

如果你希望喺唔修改清單文件嘅情況下吸收新嘅穩定功能，請鎖定 `:latest`。該標籤每週一早上更新一次，因此請相應安排你嘅部署窗口。以下係一個 GitHub Actions 工作流示例，它會按照該頻率檢查並部署最新嘅穩定映像：

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

自託管安裝可以允許受信任網絡上嘅開發人員喺唔登入嘅情況下提交洞察、使用緩存，或者兩者兼有。儀表板同管理仍然需要身份驗證。

僅啟用你需要嘅功能：

| 伺服器環境變量 | 允許無需登入 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交構建同測試洞察 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 讀取同寫入緩存嘅構建輸出 |

這兩個設置默認都係 **關閉**，彼此獨立，並適用於實例範圍內嘅所有帳戶同項目，包括私有項目。它們喺 Tuist 託管服務上不可用，亦唔能替代自託管許可證。

當 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 未設置時，舊嘅 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名稱仍作為兼容性後備保留。

> [!WARNING]
> 僅喺強制執行嘅辦公網絡或 VPN 邊界後面啟用這些設置。任何能夠訪問已啟用端點嘅人都可以提交報告，或者喺啟用緩存訪問嘅情況下讀取同覆蓋緩存輸出。這可能會導致偽造遙測數據、緩存投毒同容量耗盡。報告響應亦可能洩露私有項目句柄同構建系統。Tuist 唔會驗證 VPN 成員資格，亦唔會將轉發嘅 IP 頭部視為成員資格證明。

### 配置實例 {#network-trusted-instance-configuration}

1. 使用防火牆或私有入口將 Tuist 伺服器、每個 Kura HTTP/gRPC 監聽器同任何 Bazel BES 入口限制喺你嘅受信任網絡內。
2. 喺升級客戶端之前，先升級每個伺服器同 Kura 副本。保持 Kura 身份驗證啟用狀態，使用 `KURA_AUTH_TUIST_URL` 及其控制平面憑證；禁用它會繞過這些限制。使用 <.localized_link href="/guides/features/cache/self-hosting">自託管緩存指南</.localized_link> 配置你嘅緩存端點。
3. 喺每個相關嘅 Tuist 伺服器副本上設置上述所需變量，然後重新啟動或重新部署它們。只有確切值 `true` 才能啟用設置。儀表板上沒有切換開關，Kura 亦沒有單獨嘅標誌。

### 配置客戶端 {#network-trusted-client-configuration}

喺每個兼容嘅客戶端上配置最終嘅自託管伺服器 URL 同項目。當缺少憑證時，客戶端會自動發現哪些功能已啟用；無需客戶端選擇加入。發現過程唔會跟隨重定向。現有憑證會繼續使用，無效或刷新失敗嘅憑證會導致錯誤，而唔會回退到匿名模式。請重新登入或明確登出以恢復。

喺啟用洞察訪問之前，請將所有共享憑證嘅工具升級到能夠保留損壞或被拒絕憑證、拒絕無法讀取嘅憑證目錄，並從未簽名報告中省略 Git 來源嘅版本。舊版工具可能會刪除憑證並無意中允許匿名回退；僅升級伺服器無法解決此問題。如果伺服器缺乏發現支持或回滾到較舊版本，客戶端必須進行身份驗證。舊嘅 `TUIST_NETWORK_TRUSTED_PUBLISHING` 客戶端設置不再適用。

- **洞察：** 僅提交已完成嘅 Xcode、Gradle、Elixir/Mix 同 Bazel 報告，唔包含歸檔、附件、覆蓋率、分片規劃或現有報告訪問權限。參與者聲明未經驗證；未簽名嘅遙測數據唔會驅動可信嘅測試證據或自動化。請參閱 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 同 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南以獲取客戶端設置同隱私詳情。
- **緩存：** 支持 CLI 編譯/模塊緩存、Bazel 緩存同 Gradle 任務緩存。緩存清除同遠程資產下載仍然需要憑證。唔支持嘅客戶端必須繼續進行身份驗證。
- **Bazel：** 報告需要明確嘅 `TUIST_BAZEL_BES_BACKEND` 同兼容嘅 Kura。緩存同報告選項係獨立啟用嘅。更改憑證或任一設置後，請重新運行 `tuist bazel setup`；更改編譯緩存配置後，請重新運行 `tuist cache config`。

報告請求限制為每個項目 8 MB、每分鐘 60 個請求同每日 10,000 個請求。對於具有多個副本嘅部署範圍配額，請配置共享 Valkey；否則限制係針對每個進程。如果配置嘅共享配額後端不可用，未簽名報告將被拒絕。亦請添加入口連接、正文同速率限制。

### 禁用受信任網絡訪問 {#disable-network-trusted-publishing}

將相關變量設置為 `false`，然後重新啟動 **每個相關嘅伺服器副本**。舊副本喺被替換之前可以繼續接受無需憑證嘅請求。最後一個副本切換後 60 秒內，新請求嘅緩存訪問將停止；進行中嘅傳輸唔會被取消。如果需要立即撤銷，請先喺入口處阻止流量。現有報告保留其通常嘅可見性同保留期，已身份驗證嘅客戶端繼續正常工作。

## 運行時要求 {#runtime-requirements}

本節概述喺你嘅基礎設施上託管 Tuist 伺服器嘅要求。

### 兼容性矩陣 {#compatibility-matrix}

Tuist 伺服器已經過測試，並與以下最低版本兼容：

| 組件 | 最低版本 | 備註 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能必需 |

### 運行 Docker 虛擬化映像 {#running-dockervirtualized-images}

我哋通過 [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 映像形式分發伺服器。

要運行它，你嘅基礎設施必須支持運行 Docker 映像。請注意，大多數基礎設施提供商都支持它，因為它已成為喺生產環境中分發同運行軟件嘅標準容器。

### Postgres 數據庫 {#postgres-database}

除咗運行 Docker 映像外，你還需要一個 [Postgres 數據庫](https://www.postgresql.org/) 來存儲關係數據。大多數基礎設施提供商都喺其產品中包含 Postgres 數據庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 同 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅架構遷移。


### ClickHouse 數據庫 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來存儲同查詢大量分析數據。對於構建洞察等功能，ClickHouse 係 **必需** 嘅。你可以選擇自行託管 ClickHouse 或使用其託管服務。

> [!NOTE]
> **遷移**
>
> Docker 映像嘅入口點會喺啟動服務之前自動運行任何待處理嘅 ClickHouse 架構遷移。

捆綁嘅 Docker Compose 同 Helm 嵌入式 ClickHouse 配置將 ClickHouse 文本日誌級別從映像嘅 `trace` 默認值降低到 `information`，這係 `system.text_log` 體積嘅主要來源。兩者亦可以限制 ClickHouse 自身嘅 `system.*` 操作日誌表，否則這些表係無邊界嘅，但此功能默認為關閉 — 請參閱下文。外部 ClickHouse 部署應直接喺其 ClickHouse 服務中配置這些操作日誌。

#### ClickHouse 複製拓撲 {#clickhouse-replication-topology}

僅 ClickHouse Cloud 支持 Tuist 背後嘅多副本 ClickHouse。自行管理嘅 ClickHouse 為單副本。

攝取遷移會發出普通嘅 `MergeTree` 引擎。喺 Cloud 上，這會透明地變為 `SharedMergeTree`，因此寫入會進入共享對象存儲，且任何副本數量都可以工作。喺自行管理嘅 ClickHouse 上，`MergeTree` 僅寫入一個副本嘅本地磁盤；多副本設置要麼靜默地喺副本之間拆分攝取，要麼拒絕 CREATE 並返回 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.`，具體取決於連接用戶如何設置 `database_replicated_allow_only_replicated_engine`。

喺自行管理嘅 ClickHouse 上運行一個帶有一個副本嘅分片，並定期備份 ClickHouse 數據目錄。如果節點丟失，沒有第二個副本可以回退。

#### 限制操作日誌保留期 {#capping-operational-log-retention}

保留期可以應用於 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 同 `system.part_log`。

喺已有數據嘅實例上啟用此功能係一次性、不可逆嘅步驟，這就是為什麼兩個捆綁包都唔會為你執行此操作。任何保留窗口都會導致這些表定義不再匹配其配置，因此 ClickHouse 會將每個表重命名並啟動一個新表，如 [被取代嘅日誌表](#superseded-log-tables) 中所述。留下嘅世代保留迄今為止累積嘅所有內容，且自身沒有保留策略，因此除非你喺同一步驟中回收它，否則它將永久保留喺磁盤上，而新窗口僅限制從那時起寫入嘅行。同時啟用兩者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

單一嘅 `helm upgrade` 係自包含嘅，因為將 `ttlDays` 從空白設置為特定值會添加 drop-in 掛載並滾動 ClickHouse pod：它會重新啟動，取代表，然後升級後作業會刪除它們。使用 `helm upgrade --wait` 進行部署，以便喺作業運行之前滾動 pod；否則，世代會喺作業檢查之後出現，而下一次 `helm upgrade` 會改為回收它們。

使用 Docker Compose 時，取消註釋 `docker-compose.yml` 中 `clickhouse` 服務上嘅 `clickhouse-log-ttl.xml` 卷，並喺 `.env` 中設置兩個變量：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空間被回收，你可以將 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，這樣後續嘅 ClickHouse 升級就不會自動丟棄歷史記錄。

#### 被取代嘅日誌表 {#superseded-log-tables}

ClickHouse 喺啟動時檢查每個系統日誌表是否仍然匹配其配置。如果不匹配，它會將現有表重命名為 `system.<name>_0`，然後係 `_1`、`_2` 等，並啟動一個新表。當你更改保留窗口或進行更改系統日誌架構嘅 ClickHouse 升級時，就會發生這種情況。

重命名表不會複製其數據，因此這不會消耗額外嘅磁盤空間。被取代嘅表之後嘅情況取決於它來自哪個表，因為它會保留被取代時活動表擁有嘅任何保留策略。首次啟用保留時，被取代嘅表沒有任何保留策略，因此它會保留迄今為止累積嘅所有歷史記錄並無限期保留。隨後對窗口嘅更改會取代已經帶有 TTL 嘅表，因此這些表會自行過期並留下一個空表。ClickHouse 永遠不會刪除表本身，因此喺長期運行嘅實例上，它們會以任一方式累積。

默認情況下會保留被取代嘅表，這樣升級就不會自動丟棄操作歷史記錄。將策略設置為 `delete` 以改為刪除它們，這會喺 `docker compose up` 同每次 `helm upgrade` 時發生：

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

刪除被取代嘅表會回收其磁盤空間。活動表永遠不會被觸及，自被取代以來寫入嘅行亦然。

若要喺不更改策略嘅情況下一次性回收空間，請手動刪除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 數據庫使用 `Atomic` 引擎，該引擎會將普通嘅 `DROP TABLE` 延遲 `database_atomic_delay_before_drop_table_sec`（默認為八分鐘）。`SYNC` 會立即刪除數據，這正是你喺因磁盤已滿而刪除這些表時所需要嘅。


### 存儲 {#storage}

你還需要一個解決方案來存儲文件（例如框架同庫二進制文件）。Tuist 伺服器支持 S3 兼容存儲同 Azure Blob Storage 用於伺服器擁有嘅工件。

> [!TIP]
> **優化緩存**
>
> 如果你嘅目標主要係減少緩存延遲，你可能不需要自行託管整個伺服器。你可以喺靠近你嘅 CI 或開發者網絡嘅地方部署自行託管嘅 Kura 節點，並將它們連接到託管嘅 Tuist 伺服器或你嘅自行託管伺服器。
>
> 請參閱 <.localized_link href="/guides/cache/self-host">自行託管緩存指南</.localized_link>。


### 自行託管嘅 Kura 節點 {#self-hosted-cache-nodes}

要喺自行託管嘅 Tuist 伺服器上使用自行託管嘅 Kura 節點：

1. 喺 Tuist 伺服器上配置 `KURA_CONTROL_PLANE_CLIENT_ID` 同 `KURA_CONTROL_PLANE_CLIENT_SECRET`。客戶端 ID **必須係 UUID**。使用 <.localized_link href="/guides/cache/self-host#control-plane-client">自行託管緩存指南</.localized_link> 中嘅命令生成 UUID 同隨機密鑰，並將它們存儲喺你嘅部署密鑰中。
2. 按照 <.localized_link href="/guides/cache/self-host">自行託管緩存指南</.localized_link> 部署 Kura 節點，使用相同嘅控制平面憑證。
3. 使用 `KURA_REGISTRATION_URL` 同 `KURA_ADVERTISED_HTTP_URL` 配置每個 Kura 節點。註冊心跳會告訴伺服器它可以向 CLI 通告哪些就緒、面向客戶嘅 Kura 端點。

## 配置 {#configuration}

服務配置喺運行時通過環境變量完成。鑑於這些變量嘅敏感性，我哋建議加密並將它們存儲喺安全嘅密碼管理解決方案中。請放心，Tuist 會極其謹慎地處理這些變量，確保它們永遠不會顯示喺日誌中。

> [!NOTE]
> **啟動檢查**
>
> 必要嘅變量會喺啟動時進行驗證。如果缺少任何變量，啟動將失敗，錯誤消息將詳細說明缺失嘅變量。


### 許可證配置 {#license-configuration}

作為本地部署用戶，你會收到一個需要作為環境變量公開嘅許可證。該許可證用於驗證部署並確保服務喺協議條款範圍內運行。

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 簽署服務級別協議後提供嘅許可證。接受標準許可證密鑰或喺隔離網絡環境（伺服器無法聯繫外部服務）中使用嘅 base64 編碼證書。 | 是 | | `******` |

> [!WARNING]
> **到期日期**
>
> 許可證有到期日期。如果許可證喺少於 30 天內到期，用戶喺使用與伺服器交互嘅 Tuist 命令時會收到警告。如果你有興趣續訂許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基礎環境配置 {#base-environment-configuration}

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 從互聯網訪問實例嘅基本 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用於加密信息（例如 cookie 中嘅會話）嘅密鑰 | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用於生成哈希密碼嘅加鹽值 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用於生成隨機令牌嘅密鑰 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS_PREVIOUS` | 之前嘅 `TUIST_SECRET_KEY_TOKENS`，仍然驗證輪換之前發出嘅令牌。一旦它們過期（30 天）就將其刪除 | 否 | | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用於敏感數據 AES-GCM 加密嘅密鑰。超過 32 字節嘅值會被截斷為前 32 字節；建議使用 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | 逗號分隔嘅 `id:base64` 加密密鑰，每個 32 字節（`openssl rand -base64 32`）。第一個用於加密新數據；其他密鑰同 `TUIST_SECRET_KEY_ENCRYPTION`（ID `V1`）仍然用於解密現有數據。使用 `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` 將現有數據移動到當前密鑰 | 否 | | `k2:3q2+7w...` |
| `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` | 當不應該係 `TUIST_SECRET_KEY_ENCRYPTION_KEYS` 中第一個密鑰時，用於加密新數據嘅密鑰 ID | 否 | | `V1` |
| `TUIST_SSO_CLIENT_ASSERTION_PRIVATE_KEYS` | 一個或多個 RSA 私鑰（2048 位或更多），以 PEM 格式連接，允許組織使用 `private_key_jwt` 而不是客戶端密鑰向他們嘅 OAuth2 SSO 提供商驗證 Tuist。第一個密鑰用於簽名；每個密鑰都發布喺 `/.well-known/sso-client-jwks.json`，每個密鑰對應嘅證書位於 `/.well-known/sso-client-certificates/<kid>.pem`。要輪換，請附加新密鑰，讓組織註冊它，然後將其移到第一位。沒有它，組織只能使用客戶端密鑰。 | 否 | | |
| `TUIST_USE_IPV6` | 當為 `1` 時，它會配置應用程序使用 IPv6 地址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 應用程序使用嘅日誌級別 | 否 | `info` | [日誌級別](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 你嘅 GitHub 應用程序嘅 slug，取自 `https://github.com/apps/<slug>`。安裝應用程序時必需。請參閱 <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程序解鎖額外功能（例如發布自動 PR 評論）嘅 base64 編碼私鑰 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用於 GitHub 應用程序解鎖額外功能（例如發布自動 PR 評論）嘅私鑰。**我哋建議改用 base64 編碼版本以避免特殊字符問題** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 電子郵件地址以 `@<this-domain>` 結尾並證明擁有該域名控制權嘅用戶，可以訪問操作 URL（`/ops/*`）。如果未設置，則無人可以訪問。請參閱 [Operations](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 喺儀表板導航欄中顯示為徽章嘅標籤，用於標識伺服器實例（例如版本號或分支名稱） | 否 | 開發環境中嘅 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 啟用 Web 伺服器端點 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允許無需登錄即可提交構建和測試洞察。有關設置和安全要求，請參閱 [Network-trusted access](#network-trusted-access)。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允許無需登錄即可讀取和寫入緩存。有關設置和安全要求，請參閱 [Network-trusted access](#network-trusted-access)。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 用於發送追蹤數據嘅 OpenTelemetry Collector gRPC 端點 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 用於推送日誌嘅 Loki 兼容端點嘅基本 URL（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **通過 HTTPS 提供應用程序服務**
>
> 會話 Cookie 被標記為 `Secure`，因此瀏覽器會喺純 `http://` 連接中丟棄它們，導致用戶無法登錄。請喺伺服器前端終止 TLS（使用內部 CA 證書嘅反向代理即可），並將 `TUIST_APP_URL` 設置為 `https://` URL，即使係內部或僅限 VPN 嘅部署也是如此。

#### 反向代理後面嘅客戶端地址 {#client-addresses-behind-a-reverse-proxy}

伺服器根據客戶端地址對登錄和 API 速率限制進行密鑰管理，並記錄請求。喺反向代理後面，它從 `X-Forwarded-For` 讀取該地址，並且只相信私有網絡（RFC 1918、運營商級 NAT、環回、鏈路本地或 IPv6 唯一本地地址）上嘅代理所寫入嘅內容：它採用標頭中最右側嘅公共地址，因此客戶端無法通過發送標頭來選擇自己嘅地址。帶有端口嘅條目（例如 `203.0.113.7:51234`）也會被讀取。

如果代理從公共地址連接到伺服器，伺服器會忽略該標頭，每個請求都被視為來自代理，因此所有客戶端共享一個速率限制預算。請通過私有網絡將代理連接到伺服器以保持每個客戶端嘅限制。早期版本從任何連接中獲取最左側嘅 `X-Forwarded-For` 條目。

### 數據庫配置 {#database-configuration}

以下環境變量用於配置數據庫連接：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 訪問 Postgres 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 應用程式表格所用嘅 PostgreSQL schema。當您嘅數據庫政策不允許使用 `public` schema 時，請設置此項。Schema 名稱必須係一個未經引用嘅 PostgreSQL 標識符。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 僅由 `Tuist.Release.migrate` 使用嘅可選 Postgres URL。當 `DATABASE_URL` 指向權限較窄嘅運行時角色時，請將其設置為擁有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 遷移完成後應授予應用程序表格權限嘅運行時 Postgres 角色。當 Web 伺服器不應以 schema 擁有者身份連接時，請與 `TUIST_MIGRATION_DATABASE_URL` 配合使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 訪問 ClickHouse 數據庫嘅 URL。請注意，URL 應包含身份驗證信息 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 當為 true 時，它使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連接數據庫。除非啟用 `TUIST_DATABASE_SSL_VERIFY`，否則不會驗證伺服器證書 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 當為 true 時，數據庫伺服器證書必須鏈接到受信任嘅 CA 並匹配 `DATABASE_URL` 主機。需要 `TUIST_USE_SSL_FOR_DATABASE`。我哋建議啟用此功能 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 包含用於驗證數據庫伺服器嘅 CA 證書嘅 PEM 文件路徑。如果未設置，則使用操作系統嘅信任存儲 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 在連接池中保持打開嘅連接數 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 檢查從池中取出嘅所有連接是否超過隊列間隔嘅時間間隔（以毫秒為單位）[(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 隊列中嘅閾值時間（以毫秒為單位），池使用該時間來確定是否應開始丟棄新連接 [(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新之間嘅時間間隔（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 強制刷新之前嘅最大 ClickHouse 緩衝區大小（以字節為單位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要運行嘅 ClickHouse 緩衝區進程數 | 否 | `5` | `5` |

默認情況下，Tuist 會加密數據庫連接但不驗證伺服器證書，因此網絡路徑上嘅攻擊者可以冒充數據庫。設置 `TUIST_DATABASE_SSL_VERIFY=1` 以進行驗證。如果您嘅提供商使用其自己嘅 CA 簽署證書（如 Amazon RDS 和 Google Cloud SQL 所做嘅那樣），請下載其 CA 捆綁包，將其掛載到容器中，並將 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向它。`DATABASE_URL` 中嘅主機必須匹配證書中嘅名稱或 IP 地址。啟用驗證後，未能通過這些檢查嘅證書會導致每個數據庫連接失敗，因此啟用後請檢查伺服器日誌中是否有 `Bad Certificate` 或 `Unknown CA`。

當 `TUIST_DATABASE_SCHEMA` 不是 `public` 時，如果在運行 Ecto 遷移鏈之前 schema 不存在，release 遷移會創建該 schema。如果遷移角色無法創建 schema，請預先創建 schema 並使遷移角色成為其擁有者。

Tuist 通過設置會話 `search_path` 將連接指向自定義 schema。某些池化或代理嘅 Postgres 設置（例如 PgBouncer，或限制啟動參數嘅託管數據庫）不會應用此設置，會話會回退到 `public`，這在遷移期間會顯示為 `permission denied for schema public`。當通過此類設置連接時，請將 schema 固定喺角色本身，以便無論代理如何，每個會話都從中開始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 身份驗證環境配置 {#authentication-environment-configuration}

我哋通過 [identity providers (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促進身份驗證。要利用此功能，請確保所選提供商所需嘅所有環境變量都存在於伺服器環境中。**Missing variables** 會導致 Tuist 繞過該提供商。

#### 電子郵件和密碼 {#email-and-password}

電子郵件和密碼登錄以及自助註冊已內置並默認啟用。喺需要要求身份提供商嘅實例上（例如，當強制執行 SSO 時），您可以完全關閉它們。這會從登錄體驗中刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉每個匹配嘅伺服器端端點，包括 CLI 使用嘅電子郵件/密碼端點 (`tuist auth`)。

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用電子郵件和密碼進行登錄和註冊。設置為 `0` 以從登錄頁面刪除電子郵件/密碼表單、註冊鏈接和密碼重置流程，並關閉匹配嘅伺服器端端點 | 否 | `1` | `0` |

#### 停用已配置嘅身份提供商 {#disabling-a-configured-identity-provider}

默認情況下，只要配置咗某個提供商，佢就會顯示為登錄選項。要保留提供商配置（其憑證仍然設置）同時從登錄和註冊頁面中移除佢，請將對應嘅開關設置為 `0`。對於 GitHub、Google 和 Apple，這亦會關閉登錄回調，因此該方法將完全無法使用。

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄（請參閱 [GitHub](#github) 部分以了解為何 App 會共享其憑證用於登錄） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 進行登錄 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 已配置嘅 Okta 提供商是否顯示為登錄選項 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 進行登錄 | 否 | `1` | `0` |

#### GitHub {#github}

我哋建議使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 進行身份驗證，但您亦可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請確保伺服器環境中包含 GitHub 指定嘅所有必要環境變量。缺少變量會導致 Tuist 忽略 GitHub 身份驗證。要正確設置 GitHub app：
- 喺 GitHub app 嘅一般設置中：
    - 複製 `Client ID` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_ID`
    - 創建並複製一個新嘅 `client secret` 並將其設置為 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將 `Callback URL` 設置為 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 亦可以係您伺服器嘅 IP 地址。
- 需要以下權限：
  - 儲存庫：
    - Pull requests：讀寫
  - 帳戶：
    - 電子郵件地址：只讀

喺 `Permissions and events` 嘅 `Account permissions` 部分，將 `Email addresses` 權限設置為 `Read-only`。

然後您需要喺運行 Tuist 伺服器嘅環境中公開以下環境變量：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程式嘅客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程式嘅客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 進行登錄。您為平台集成（PR 評論等）配置嘅 GitHub App 會共享其客戶端憑證用於登錄，因此它否則會顯示為登錄選項。設置為 `0` 以保留 App 同時從登錄頁面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

你可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設置 Google 身份驗證。為此，你需要創建一個類型為 OAuth 客戶端 ID 的新憑證。創建憑證時，選擇「Web Application」作為應用程式類型，將其命名為 `Tuist`，並將重定向 URI 設置為 `{base_url}/users/auth/google/callback`，其中 `base_url` 係你託管服務運行嘅 URL。創建應用程式後，複製客戶端 ID 和密鑰，並分別將它們設置為環境變量 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意畫面範圍**
>
> 你可能需要創建一個同意畫面。創建時，請確保添加 `userinfo.email` 和 `openid` 範圍，並將應用程式標記為內部。


#### Okta {#okta}

你可以通過 [OAuth 2.0](https://oauth.net/2/) 協議啟用 Okta 身份驗證。你需要按照 <.localized_link href="/guides/integrations/authentication/sso#okta">這些說明</.localized_link> 喺 Okta 上 [創建應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

喺設置 Okta 應用程式期間獲得客戶端 ID 和密鑰後，你需要設置以下環境變量：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用於對 Okta 進行身份驗證嘅客戶端 ID。該數字應為你嘅組織 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於對 Okta 進行身份驗證嘅客戶端密鑰 | 是 | | |

數字 `1` 需要替換為你嘅組織 ID。這通常係 1，但請檢查你嘅數據庫。

### 存儲環境配置 {#storage-environment-configuration}

 Tuist 需要存儲空間來存放通過 API 上傳嘅構件。要讓 Tuist 有效運作，**必須配置其中一種受支持嘅存儲解決方案**。

設置 `TUIST_OBJECT_STORAGE_PROVIDER` 以選擇伺服器構件後端：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 伺服器構件存儲後端。對於 S3 兼容存儲使用 `s3`，對於 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 兼容存儲 {#s3compliant-storages}

你可以使用任何 S3 兼容嘅存儲提供商來存儲構件。以下環境變量係認證和配置與存儲提供商集成所必需嘅：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用於對存儲提供商進行身份驗證嘅訪問密鑰 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用於對存儲提供商進行身份驗證嘅秘密訪問密鑰 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 儲存桶所在嘅區域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 存儲提供商嘅端點 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 用於存儲構件嘅儲存桶名稱 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | 用於驗證 S3 HTTPS 連接嘅 PEM 編碼 CA 證書。適用於使用自簽名證書或內部證書頒發機構嘅隔離環境。 | 否 | 系統 CA 捆綁包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立與存儲提供商連接嘅超時時間（以毫秒為單位） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 從存儲提供商接收數據嘅超時時間（以毫秒為單位） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 連接到存儲提供商嘅連接池超時時間（以毫秒為單位）。使用 `infinity` 表示無超時 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中連接嘅最大空閒時間（以毫秒為單位）。使用 `infinity` 以保持連接永久活躍 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每個池嘅最大連接數 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用嘅連接池數量 | 否 | 系統調度器數量 | `4` |
| `TUIST_S3_PROTOCOL` | 連接到存儲提供商時使用嘅協議（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL 是否應將儲存桶名稱作為子域（虛擬主機）構建 | 否 | `false` | `1` |

> [!NOTE]
> **來自環境變量嘅 AWS Web 身份認證**
>
> 如果你嘅存儲提供商係 AWS，並且你想使用 Web 身份令牌進行認證，你可以將環境變量 `TUIST_S3_AUTHENTICATION_METHOD` 設置為 `aws_web_identity_token_from_env_vars`，Tuist 將使用常規嘅 AWS 環境變量採用該方法。


#### Google Cloud Storage {#google-cloud-storage}
對於 Google Cloud Storage，請按照 [這些文檔](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 獲取 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 配對。`AWS_ENDPOINT` 應設置為 `https://storage.googleapis.com`。其他環境變量與任何其他 S3 兼容存儲相同。

#### Azure Blob Storage {#azure-blob-storage}

對於 Azure Blob Storage，設置 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 並配置 Azure 存儲帳戶憑據：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 存儲帳戶名稱 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用於簽署 Azure Blob REST 請求和 SAS URL 嘅存儲帳戶訪問密鑰 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 存儲服務器構件嘅容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服務端點。省略以使用 `https://<account>.blob.core.windows.net` | 否 | 從帳戶名稱派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用於簽署請求和 SAS URL 嘅 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm chart 時，設置 `server.storage.provider=azure_blob` 並填寫 `server.azureBlob.*`。chart 嘅頂層 `objectStorage` 設置保持 S3 兼容，因為可選嘅緩存和註冊表鏡像工作負載仍然需要 S3 兼容存儲。如果禁用這些工作負載且服務器使用 Azure Blob，請設置 `objectStorage.mode=external` 並將外部對象存儲端點和憑據留空，以避免部署嵌入式 MinIO 服務。

#### 構件保留 {#artifact-retention}

在自託管實例上，默認情況下禁用構件清理。每種受支持嘅構件類型都有自己嘅環境變量。將變量設置為正整數天數以啟用該構件類型嘅清理。將變量留空或不設置僅會禁用該構件類型嘅清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm chart 時，將相同嘅窗口配置為映射：

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

所有六個鍵都是可選嘅。此示例啟用了每種受支持嘅構件類型，並具有獨立嘅保留窗口。省略鍵或將其值留空以保持禁用該構件類型嘅清理。自託管保留窗口沒有 30 天嘅上限。配置嘅值如果不是正整數，會導致服務器在啟動時失敗。

更改保留變量後重新啟動服務器。每個排隊嘅自託管清理批次在刪除文件之前都會檢查當前配置，因此取消設置或清空變量，或增加其窗口，也可以在重新啟動後保護文件免受待處理作業嘅影響。

| 環境變量 | 從對象存儲中刪除嘅構件文件 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 緩存、舊版內容尋址存儲緩存、模塊緩存和 Gradle 緩存文件 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App Preview 構建和圖標 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 當前和舊版構建歸檔 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 存儲在已過期運行構件前綴下嘅所有對象，包括結果包、調用記錄和會話歸檔 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 測試執行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 測試分片包 |

計劃清理僅刪除構件 blob。它保留相應嘅 PostgreSQL 和 ClickHouse 行，因此在下載過期後，構建、測試、運行、預覽和分片元數據仍可在大屏上可見。此配置不會更改 ClickHouse 表保留規則。

### 電子郵件配置 {#email-configuration}

Tuist 需要電子郵件功能用於用戶認證和事務性通知（例如，密碼重置、帳戶通知）。目前，**僅支持 Mailgun** 作為電子郵件提供商。

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用於與 Mailgun 進行身份驗證嘅 API 密鑰 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 發送電子郵件嘅域名 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 將顯示在「發件人」字段中嘅電子郵件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用於用戶回覆嘅可選回覆地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳過新用戶註冊嘅電子郵件確認。啟用後，用戶將自動確認並可以在註冊後立即登錄 | 否 | 如果未配置電子郵件則為 `true`，如果已配置電子郵件則為 `false` | `true`, `false`, `1`, `0` |

\* 僅當你想發送電子郵件時才需要電子郵件配置變量。如果未配置，系統會自動跳過電子郵件確認

> [!NOTE]
> **SMTP 支援**
>
> 目前不提供通用 SMTP 支援。如果你需要為本地部署提供 SMTP 支援，請聯絡 [contact@tuist.dev](mailto:contact@tuist.dev) 討論你的需求。


> [!NOTE]
> **隔離網絡部署**
>
> 對於沒有互聯網訪問或電子郵件提供商配置的本地安裝，默認情況下會自動跳過電子郵件確認。用戶可以在註冊後立即登錄。如果你已配置電子郵件但仍想跳過確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。若要在配置電子郵件時要求電子郵件確認，請設置 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **電子郵件配額和密碼重置連結**
>
> 配置電子郵件後，邀請郵件（新建、批量或重發）限制為每五分鐘每個收件人一封，且每個組織和每個邀請者每小時可突發發送 50 封並以此速率補充。取消邀請不會恢復配額，當配額耗盡時，邀請 API 會返回 `429` 和 `Retry-After`。使用多個副本時，請配置共享 Valkey 以實現整個部署範圍的配額；如果已配置但不可用，邀請郵件將被拒絕。密碼重置連結在 15 分鐘後過期。


### Git 平台配置 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">與 Git 平台集成</.localized_link>，提供額外功能，例如自動在你的拉取請求中發布評論。

#### GitHub {#platform-github}

自託管 Tuist 服務器無法安裝運行於 `https://tuist.dev` 的 GitHub App。GitHub App 綁定到註冊它們的服務器，因此你的部署需要在 github.com 上擁有自己的 App。

##### 註冊 App {#platform-github-registering-the-app}

[創建一個由你的 GitHub 組織擁有的 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非你創建的是 OAuth App，否則你可以重用為認證創建的 App。使用以下內容進行配置，將 `YOUR_APP_URL` 替換為 `TUIST_APP_URL` 的值：

| 設置 | 值 |
| --- | --- |
| 回調 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 設置 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新時重定向 | 已啟用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密鑰 | 任意隨機字符串。你將將其設置為 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予以下存儲庫權限：

| 權限 | 訪問 |
| --- | --- |
| 內容 | 只讀 |
| 元數據 | 只讀 |
| Issues | 讀寫 |
| Pull requests | 讀寫 |
| Checks | 讀寫 |

同時授予 **成員：只讀** 組織權限。在 github.com 設置期間，Tuist 會檢查連接組織安裝的人是否是活躍的 GitHub 組織所有者，而不僅僅是能夠訪問其某個存儲庫的人。

訂閱 App 的 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **安裝期間請求用戶授權 (OAuth)** 為禁用狀態，以便 GitHub 將安裝程序發送到設置 URL。Tuist 使用額外的 `/integrations/github/authorize` 回調啟動單獨的授權步驟，以驗證安裝所有權。當在 GitHub 上開始安裝時，安裝者隨後選擇一個 Tuist 組織。GitHub 組織上的安裝始終顯示此選擇；在 Tuist 中開始的安裝會保留其組織。

##### 配置服務器 {#platform-github-configuring-the-server}

設置以下環境變量，然後重新啟動服務器：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公共頁面 URL 的最後路徑組件 `https://github.com/apps/<slug>` | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 數字 App ID，用於驗證安裝所有權 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 應用程序的客戶端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用程序的客戶端密鑰 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 應用程序的 base64 編碼私鑰。優先於 `TUIST_GITHUB_APP_PRIVATE_KEY`，後者對平台處理換行符的方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 應用程序上配置的 Webhook 密鑰 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **配置所有必需的 App 憑據**
>
> 在 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私鑰全部設置之前，組織集成頁面上的 **安裝 GitHub App** 按鈕將保持禁用狀態。還需要數字 `TUIST_GITHUB_APP_ID` 來驗證安裝所有權。安裝 URL 嵌入了 App slug，因此缺少 `TUIST_GITHUB_APP_NAME` 尤其會導致 GitHub 返回 404 錯誤的連結。

服務器重新啟動後，組織管理員按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 安裝 App 並將存儲庫連接到項目。

##### OIDC 認證依賴於此 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 認證</.localized_link> 根據連接到你項目的存儲庫解析 CI 令牌中的存儲庫聲明，而連接只能通過已安裝的 GitHub App 創建。在你的 CI 工作流使用 OIDC 進行認證之前，請完成上述設置。

你的 Tuist 服務器還需要出站訪問你的 CI 提供商的 OIDC 頒發者以獲取其簽名密鑰：

| CI 提供商 | 主機 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述環境變量僅配置 Tuist 的 github.com App。要將 Tuist 與 GitHub Enterprise Server (GHES) 實例集成，組織管理員需切換到集成頁面上的 **企業服務器** 標籤並輸入 GHES 基礎 URL — Tuist 會引導他們完成 GitHub 的 [App 清單流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)，以在他們的 GHES 實例上註冊一個新的 Tuist App。新 App 的憑據按安裝加密存儲；不需要額外的 `TUIST_GITHUB_APP_*` 環境變量。

#### Origin {#platform-origin}

自託管 Tuist 服務器需要自己的 Origin app，並使用你部署的 URL 和簽名密鑰進行配置。為每個 Tuist 環境註冊單獨的 app，以使安裝和憑據保持獨立。

##### 註冊 App {#platform-origin-registering-the-app}

1. 使用支持 Ed25519 的 OpenSSL 生成 Ed25519 簽名密鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin app 設置](https://cursor.com/codebase/settings/apps) 中創建一個 app。將 `origin-app-public.pem` 的內容註冊為其公共簽名密鑰。保密 `origin-app-private.pem`；你將將其提供給 Tuist 服務器，而不是上傳到 Cursor。
3. 配置以下設置，將 `YOUR_APP_URL` 替換為你的 Tuist 部署的 HTTPS 基礎 URL：

   | 設置 | 值 |
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
| `repository:metadata:read` | 發現存儲庫並讀取其默認分支。由 Origin 自動授予。 |

保持可選的存儲庫 webhook 事件未選中。安裝生命週期通知已足夠；不需要源代碼訪問、合併權限和 check-run 權限。

##### 配置服務器 {#platform-origin-configuring-the-server}

設置以下環境變量，然後重新啟動服務器：

| 環境變量 | 描述 | 必需 | 默認 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 從 Origin app 設置複製的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

將私鑰存儲在你部署的密鑰管理器中。保留其多行 PEM 格式；此設置不接受 base64 編碼的替換。切勿將密鑰提交到源代碼控制或在日誌中暴露。兩個變量必須屬於同一個已註冊的 app。

你的 Tuist 服務器需要對 `api.cursor.com` 的出站 HTTPS 訪問。Cursor 必須能夠將請求發送到 webhook URL，並且管理員必須能夠在瀏覽器中返回到重定向 URI。兩個註冊的 URL 必須與你部署的 HTTPS 基礎 URL 匹配。

##### 安裝 App {#platform-origin-installing-the-app}

服務器重新啟動後，管理員打開 **設置 → 集成**，在 Origin 下選擇 **連接**，並批准 app 訪問適當的 Origin 帳戶和存儲庫。整個流程中都會保留 Tuist 組織。直接從 Origin 發起的安裝則會提示管理員登錄並選擇要連接的 Tuist 組織。然後他們選擇 **添加新項目連接** 以將 Tuist 項目鏈接到本機存儲庫。

按照 <.localized_link href="/guides/integrations/gitforge/origin">Origin 集成指南</.localized_link> 了解項目連接和結果上傳要求。安裝 app 不會啟動構建或測試工作流；這些工作流繼續向你的 Tuist 服務器報告結果。

#### Entire {#platform-entire}

自託管 Tuist 服務器需要自己的 Entire 插件，並使用你部署的 URL 和簽名密鑰進行配置。Entire 插件需要合作夥伴註冊，因此在開始之前請聯繫 Entire。為每個 Tuist 環境註冊單獨的插件，或者至少註冊單獨的簽名密鑰，以使安裝和憑據保持獨立。

##### 註冊插件 {#platform-entire-registering-the-plugin}

1. 使用支持 Ed25519 的 OpenSSL 生成 Ed25519 簽名密鑰對：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. 按照 Entire 的 [插件註冊指南](https://docs.entire.com/guides/api/plugins/register) 註冊插件。分享 `entire-plugin-public.pem` 的內容，或發布它的 JWKS URL，作為插件的簽名密鑰。保密 `entire-plugin-private.pem`；你將將其提供給 Tuist 服務器，而不是 Entire。
3. 配置以下 URL，將 `YOUR_APP_URL` 替換為你的 Tuist 部署的 HTTPS 基礎 URL：

   | 設置 | 值 |
   | --- | --- |
   | 安裝後 URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL | `YOUR_APP_URL/webhooks/entire` |

4. 注意 Entire 確認的插件 slug 及其提供的 webhook 簽名密鑰 URL。

請求以下權限：

| 權限 | 用途 |
| --- | --- |
| `contents:read` | 接收 Trail 事件，並找出帶有 head commit 的開啟中和草稿狀態 Trail。 |
| `checks:write` | 發布 Tuist gate。 |
| `findings:write` | 發布並解決失敗和不穩定測試的發現。 |
| `discussions:write` | 張貼並更新摘要評論。未授予此權限的安裝仍會收到 gate 和發現。 |

不需要存儲庫寫入權限。如果你為現有註冊添加權限，請要求 Entire 更新它，並確認安裝已授予新權限。請參閱 Entire 的 [Checks](https://docs.entire.com/guides/api/plugins/report-checks)、[Findings](https://docs.entire.com/guides/api/plugins/trail-findings) 和 [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) 合約。

##### 配置服務器 {#platform-entire-configuring-the-server}

設置以下環境變量，然後重新啟動服務器：

| 環境變量 | 描述 | 必需 | 默認值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認的插件 slug。 | 是 | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` 的完整內容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有換行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 註冊時由 Entire 提供的 webhook 簽名密鑰 URL。 | 是 | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 當你通過 JWKS 註冊簽名密鑰時的密鑰 ID。 | 否 | | |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core URL。 | 否 | `https://eu.auth.entire.io` | |

將私鑰存儲在你部署的密鑰管理器中，並保留其多行 PEM 格式。切勿將密鑰提交到源代碼控制或在日誌中暴露。使用 Tuist Helm chart 時，你可以改為將 PEM 存儲在 1Password vault 中作為 `ENTIRE_PLUGIN/private_key`，並與 `server.config.managedSecrets` 一起啟用 `server.config.entirePluginKey.enabled`；項目和字段名稱可通過 `server.config.entirePluginKey.item` 和 `.field` 進行配置。此映射不會設置 slug 或 webhook 簽名密鑰 URL。

你的 Tuist 服務器需要對 Entire Core 以及為你的存儲庫提供服務的区域性 Entire API 主機（均位於 `entire.io` 或 `entire.com` 下）的出站 HTTPS 訪問。Tuist 會驗證安裝收據和 webhook 簽名，生成短生命週期的存儲庫範圍令牌，並且從不在報告鏈接中嵌入令牌。

##### 啟用集成 {#platform-entire-enabling-the-integration}

在推出應用程序之前應用服務器遷移，然後全局啟用 `entire_trails` 功能標誌以向所有帳戶提供集成，或僅向選定帳戶提供。啟用該標誌不會改變誰可以在 Entire 中安裝插件；要在插件所屬的 Entire 項目之外提供它，請聯繫你的 Entire 聯絡人允許這樣做。該集成獨立於 Tuist 的 CI 執行配置。

如果你回滾應用程序，請保留 `entire_trail_reports` 表，以便後續升級可以恢復正在進行的發布。

然後管理員按照 <.localized_link href="/guides/integrations/gitforge/entire">Entire 集成指南</.localized_link> 安裝插件並將存儲庫連接到項目。安裝插件不會啟動構建或測試工作流；這些工作流繼續向你的 Tuist 服務器報告結果。

## 本地測試 {#testing-locally}

我們提供了一個全面的 Docker Compose 配置，其中包含在部署到基礎設施之前在本地機器上測試 Tuist 服務器所需的所有依賴項：

- PostgreSQL 15
- ClickHouse 26.5 用於分析
- ClickHouse Keeper 用於協調
- MinIO 用於 S3 兼容存儲
- Kura 用於本地自託管緩存測試
- pgweb 用於數據庫管理

> [!CAUTION]
> **需要許可證**
>
> 運行 Tuist 服務器（包括本地開發實例）在法律上需要有效的 `TUIST_LICENSE` 環境變量。如果你需要許可證，請聯繫 [contact@tuist.dev](mailto:contact@tuist.dev)。


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

2. 配置環境變量：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   內置的 ClickHouse 服務接受以下可選的操作日誌控制：

   | 環境變量 | 描述 | 默認值 | 示例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日誌表（例如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留期（天數） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 服務器日誌記錄器和 `system.text_log` 級別 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 當 ClickHouse 替換系統日誌表時，如何處理其留下的 `<name>_N` 表。`ignore` 會保留它們，`delete` 會刪除它們 | `ignore` | `delete` |

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 會自動拉取 Tuist 和依賴項鏡像的 `linux/arm64` 變體。若要強制使用 amd64 模擬進行調試，請使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 運行 Compose。

   內置的 compose 文件使用命名的 Docker 卷來存儲持久數據。如果你用主機綁定掛載替換它們，請先創建主機目錄並使其對容器用戶可寫，特別是 ClickHouse 和 ClickHouse Keeper 的數據目錄。

4. 在 http://localhost:8080 訪問服務器

**服務端點：**
- Tuist 服務器：http://localhost:8080
- Kura 緩存（HTTP + REAPI gRPC 在同一端口）：http://localhost:4000
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

重置一切（刪除所有數據）：
```bash
docker compose down -v
```

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 環境變量示例文件

## 使用 Helm 部署 Kubernetes {#kubernetes-with-helm}

Tuist 提供官方的 Helm chart 用於在 Kubernetes 上部署。該 chart 打包了 Tuist 服務器和緩存服務，以及嵌入式基礎設施依賴項，你可以根據需要將其替換為外部提供商。

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

### 許可證 {#helm-license}

`server.license.key` 值接受標準許可證密鑰，對於隔離安裝，也接受 Base64 編碼的許可證證書；服務器會自動檢測是哪一種。

使用 `--set` 傳遞許可證適用於快速安裝。如果你將值保存在版本控制中，請將許可證存儲在 Helm 之外管理的 Kubernetes Secret 中，例如使用 Vault、Sealed Secrets 或 SOPS，並將 chart 指向它：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下的條目命名你 Secret 中儲存許可證值的欄位，該值可以是許可證密鑰，或對於隔離安裝而言是 Base64 編碼的許可證證書。`existingSecretKeys` 下的每個條目預設為 chart 自身的鍵名，因此請將你的 Secret 不包含的條目設為空字串，如上文的 `certificateBase64`。否則，Pod 會引用不存在的鍵並導致啟動失敗。在安裝或升級 chart 之前，請在 release 命名空間中創建 Secret。

僅透過單一來源配置許可證：`server.license.key` 或 `server.license.existingSecret`。當未設置任何來源或混合使用來源時，chart 將無法渲染。透過 `server.extraEnv` 傳遞的許可證不被視為來源，因此請改用 `existingSecret`。

### 基礎設施依賴項 {#helm-infrastructure-dependencies}

該 chart 管理三個基礎設施依賴項：`postgresql`、`clickhouse` 和 `objectStorage`。每個依賴項預設為 **嵌入式** 模式，意味著 chart 會在集群內部部署它們。若要指向你自己的外部實例，請將依賴項的 `mode` 設為 `external` 並在 `values.yaml` 中填寫連接詳情。例如，要使用外部 PostgreSQL 數據庫：

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

如果你在 Helm 之外管理 PostgreSQL 憑證，請將 chart 指向現有的 Kubernetes Secret：

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

chart 從 Secret 讀取主機、用戶名和密碼，並透過 Kubernetes 環境變量替換組成 `DATABASE_URL`，因此密碼不會渲染到 Helm manifest 中。Secret 中的密碼值應該是 URL 安全的，因為它會被插入到數據庫 URL 中。

相同的模式適用於 `clickhouse` 和 `objectStorage`。請參閱 chart 的 `values.yaml` 中每個部分下的 `external` 塊，以獲取可配置欄位的完整列表。

### 共享調度和標籤 {#helm-shared-scheduling-and-labels}

chart 在 `global` 下公開一組共享的 Pod 設置，以便運維人員可以調整部署以適應其集群，而無需為每個工作負載重複相同的值：

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

在以下情況下使用這些設置：

- 為每個 Pod 添加集群特定的標籤
- 從私有註冊表拉取鏡像
- 目標指向專用的節點池
- 允許 Pod 進入為 Tuist 工作負載保留的受汙染節點

### 工作負載身份和服務帳戶 {#helm-workload-identity}

chart 按應用工作負載劃分服務帳戶範圍，以便你僅在需要的地方授予身份：

- `server.serviceAccount` 適用於 Tuist 服務器部署和遷移任務
- `cache.serviceAccount` 適用於緩存部署

例如，當緩存在 EKS 上使用外部 S3 存儲桶時，你可以為緩存工作負載啟用 IRSA，而無需將相同的 IAM 角色附加到嵌入式數據庫：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 兼容性覆蓋 {#helm-compatibility-overrides}

chart 保持存儲和網格特定的調整為可選，以保持預設值的可移植性：

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

僅在你的集群需要時使用這些覆蓋：

- `cache.podSecurityContext` 預設為空。如果你的存儲類或 CSI 驅動程序需要在掛載卷上共享組所有權，請設置 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 預設為 ClickHouse 的標準 `9000` 原生服務端口，當服務網格或平台保留與該端口衝突時可以更改。
- `clickhouse.embedded.systemLogs.ttlDays` 預設為空，使 ClickHouse 對嵌入式內部日誌表（如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 和 `system.part_log`）保持無限制的保留策略。設置它會一次性替換這些表，因此請與 `supersededTables: delete` 一起採用——參見 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制操作日誌保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 對於嵌入式 ClickHouse 服務器日誌記錄器和 `system.text_log` 預設為 `information`。與 `ttlDays` 不同，它不是任何表定義的一部分，因此更改它永遠不會替換表。
- `clickhouse.embedded.systemLogs.supersededTables` 預設為 `ignore` 並決定 ClickHouse 在替換系統日誌表時留下的 `<name>_N` 表的處理方式。將其設置為 `delete` 以在每次 `helm upgrade` 時刪除它們。
- 對 `ttlDays` 和 `level` 的編輯將在 ClickHouse Pod 下次重啟時生效，因為兩者都是 `subPath` 掛載，且 chart 在其 ConfigMap 更改時不會滾動更新 StatefulSet。

### 可觀察性 {#helm-observability}

chart 包含一個可選的可觀察性棧（OpenTelemetry Collector、Prometheus、Grafana、Loki 和 Tempo）。它**預設禁用**。要在 `values.yaml` 中啟用它：

```yaml
# values.yaml
observability:
  enabled: true
```

啟用後，Grafana 可用，並預配置了日誌、追蹤和指標的下鑽功能。對於外部可觀察性，請保持此項禁用並透過 `server.extraEnv` 配置端點：

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

有關可配置值的完整列表，請參閱 chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 鏡像可在以下位置獲取：
```
ghcr.io/tuist/tuist
```

發布的鏡像包含用於 `.xcactivitylog` 歸檔的嵌入式 Linux 構建處理，因此自託管部署可以在不運行任何額外服務的情況下處理構建——`ProcessBuildWorker` Oban 任務在每個服務器 Pod 內進程中運行。如果你想將構建處理卸載到專用的副本集（例如，獨立於 Web 層擴展解析吞吐量），請在 Helm chart 中設置 `processor.enabled: true`：chart 將部署相同的鏡像作為僅隊列消費者（`TUIST_PROCESSOR_MODE=true`）。有關完整的控制選項，請參見 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

> [!NOTE]
> `.xcresult` 解析依賴於 Xcode 中的 `xcresulttool`，因此只能在 macOS 上運行。CLI 為自託管部署透明地處理此問題：`tuist test` 針對任何非 `tuist.dev` 服務器預設為 **本地** 處理模式，在開發者機器上解析 xcresult（該機器已擁有用於構建本身的 Xcode）並上傳結構化結果。測試結果無需任何額外基礎設施即可被攝取。

### 拉取 Docker 鏡像 {#pulling-the-docker-image}

你可以通過執行以下命令來檢索鏡像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

該鏡像同時發布了 `linux/amd64` 和 `linux/arm64` 版本，因此 Docker 會自動為主機選擇原生的 Linux 架構。

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 鏡像 {#deploying-the-docker-image}

Docker 鏡像的部署流程會根據你選擇的雲端供應商及組織的持續部署方式而有所不同。由於大多數雲端解決方案和工具（例如 [Kubernetes](https://kubernetes.io/)）都將 Docker 鏡像作為基本單元，本節中的示例應能與你現有的設置良好配合。

> [!WARNING]
> 如果你的部署流水線需要驗證服務器是否已啟動並運行，你可以向 `/ready` 發送 `GET` HTTP 請求，並斷言回應中的狀態碼為 `200`。


#### Fly {#fly}

要在 [Fly](https://fly.io/) 上部署應用程式，你需要一個 `fly.toml` 配置文件。考慮在你的持續部署 (CD) 流水線中動態生成它。以下是一個供你參考的示例：

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

然後你可以運行 `fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署中，你不需要運行 `fly launch --local-only`，而是需要運行 `fly deploy --local-only`。Fly.io 不允許拉取私有 Docker 鏡像，這就是我們需要使用 `--local-only` 標誌的原因。


## Prometheus 指標 {#prometheus-metrics}

Tuist 在 `/metrics` 公開 Prometheus 指標，以幫助你監控自託管實例。這些指標包括：

### Finch HTTP 客戶端指標 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 客戶端，並公開有關 HTTP 請求的詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求持續時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - 桶：10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求異常總數（計數器）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連接池隊列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連接池隊列中等待的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連接在使用前處於空閒狀態的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 隊列異常總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 連接指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連接所花費的時間（直方圖）
  - 標籤：`finch_name`、`scheme`、`host`、`port`、`error`
  - 桶：10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 連接嘗試總數（計數器）
  - 標籤：`finch_name`、`scheme`、`host`、`port`

#### 發送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 發送請求所花費的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連接在發送前處於空閒狀態的時間（直方圖）
  - 標籤：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

所有直方圖指標均提供 `_bucket`、`_sum` 和 `_count` 變體，以供詳細分析。

### 其他指標

除 Finch 指標外，Tuist 還公開以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳戶、專案等）
- 資料庫效能（使用 Tuist 託管基礎設施時）

## 營運 {#operations}

Tuist 在 `/ops/` 下提供一組實用工具，你可用以管理你的實例。

> [!WARNING]
> **授權**
>
> 只有電子郵件網域符合 `TUIST_OPERATOR_EMAIL_DOMAIN` 的使用者才能存取 `/ops/` 端點。如果未設定該變數，則無人可以存取。請將其設定為你控制的郵件信箱所屬的網域。
>
> 使用者亦必須證明其地址的控制權：方法是點擊確認或重設密碼電子郵件中的連結、透過 Google、GitHub 或 Apple 登入、輸入一次性代碼，或出示代理登入的已驗證電子郵件。自動確認的帳戶（在未設定郵件提供者時的預設情況）在完成此步驟前不符合資格。帳戶建立後，僅當地址位於 `TUIST_OPERATOR_EMAIL_DOMAIN` 時才會記錄證明；因此，在你設定或更改該變數後，尚未在其下證明其地址的營運人員需要再次進行證明。透過其中一個提供者登入或透過代理登入建立的帳戶，會從建立時起攜帶證明。在沒有郵件提供者的情況下，以密碼註冊的帳戶無法連結其中一個提供者，因此請透過 Google、GitHub 或 Apple 登入來建立營運人員帳戶，或設定郵件提供者。
>
> 在此檢查存在之前建立的帳戶尚未記錄該證明，因此現有營運人員在重設密碼或使用其中一個提供者登入一次後可重新獲得存取權。
>
> 當營運人員網域中沒有該證明的帳戶首次以該方式證明其地址時，Tuist 會移除其密碼、通行金鑰及與組織單一登入提供者的連結，並將其從瀏覽器及 CLI 登出，因為註冊該地址的人可能並非其擁有者。對此類帳戶重設密碼會執行相同操作，除了設定新密碼外。帳戶上設定的驗證器應用程式會保留；如果它不屬於擁有者，請為他們移除。營運人員網域外的已確認帳戶會保留其憑證。擁有者可繼續透過提供者登入，或透過重設設定新密碼。
>
> 由 SCIM 佈建建立或重新命名的帳戶在擁有者提供證明之前沒有任何證明。


- **錯誤（`/ops/errors`）：** 你可以檢視應用程式中發生的意外錯誤。這對於除錯及了解問題所在很有幫助，如果你遇到問題，我們可能會要求你與我們分享此資訊。
- **儀表板（`/ops/dashboard`）：** 你可以檢視一個儀表板，它提供有關應用程式效能及健康狀況的洞察（例如記憶體消耗、正在運行的進程、請求數量）。此儀表板對於了解你使用的硬體是否足以處理負載相當有用。
