---
{
  "title": "自行託管",
  "titleTemplate": ":title | 快取 | 指南 | Tuist",
  "description": "了解如何自行託管 Tuist 快取節點，並與 Tuist 託管的網狀架構進行複製。"
}
---

# 自行託管快取 {#self-host-cache}

Tuist 的快取以**節點網狀架構**運作，彼此複製構件。你可以在自己的基礎設施上執行快取節點，讓快取靠近開發人員與 CI，縮短網路距離，避免影響快取本應提供的速度。

自行託管節點是單一容器 (`ghcr.io/tuist/kura`)，將構件儲存在本機磁碟；加入對等網狀架構後，會透過內部對等連接埠與該網狀架構的其他節點通訊。Tuist 擔任**控制平面**：負責驗證流量、配置受管快取容量，並計量使用量。它絕不會直接存取你的節點。

> [!NOTE]
> 自行託管快取節點需要**Enterprise 方案**。
>
> 節點可連線至託管的 Tuist 伺服器 (`https://tuist.dev`) 或自行託管的 Tuist 伺服器。自行託管 Tuist 伺服器本身需要額外的伺服器授權。請參閱<.localized_link href="/guides/server/self-host/server">伺服器自行託管指南</.localized_link>。

## 兩種拓撲 {#topologies}

執行自行託管節點有兩種方式，採用哪一種完全取決於你的帳戶是否同時執行**Tuist 受管**快取區域。

### 橋接：Tuist 託管網狀架構 + 你的節點 {#topology-bridged}

你的帳戶至少執行一個 Tuist 受管快取區域，而你的自行託管節點會**加入該網狀架構**。寫入你的節點的資料會持續傳播到受管網狀架構；節點加入時，會從受管網狀架構的現有快取預熱。這能讓低延遲快取靠近你的執行器（大部分寫入由它們產生），同時它們的寫入也會餵給共用快取。請注意，在節點加入後，於受管網狀架構其他位置寫入的新構件**尚未**持續回傳到該節點；這是計畫中的增強功能。

若你希望擁有本機快取的速度，又不想放棄共用且隨時可用的受管快取，這就是合適的選擇。

### 獨立：僅使用你的節點 {#topology-standalone}

你的帳戶**沒有**執行任何受管快取區域。你的節點在你的基礎設施上形成各自的隔離網狀架構。Tuist 仍知道你的節點存在（因此會計量使用量），但**不會與任何 Tuist 受管網狀架構交換資料**，因為根本不存在這樣的網狀架構。對等成員關係與複製完全在你的節點之間進行。

```mermaid
graph LR
  subgraph Bridged
    direction LR
    M[Tuist-managed mesh] <-->|replicate| N1[Your node]
  end
  subgraph Standalone
    direction LR
    N2[Your node] <-->|replicate| N3[Your node]
  end
```

設定上的關鍵差異在於：**橋接**拓撲使用**註冊**流程，節點在啟動時產生金鑰組，Tuist 則簽發其網狀憑證；而**獨立**拓撲沒有 Tuist 簽發的網狀憑證。單一獨立節點可以在停用對等 TLS 的情況下執行；多節點獨立網狀架構則使用你提供的對等 TLS 材料。

## 設定 CLI 端點 {#cli-endpoint}

Tuist 受管快取使用 `https://<account>.cache.tuist.dev`。使用自行託管的 Tuist 伺服器時，CLI 會從伺服器的 `TUIST_CACHE_ENDPOINTS` 設定取得快取 URL。將其設為你的主要快取伺服器或負載平衡器的 URL。若包含多個 URL，則使用第一個。

將私人／自訂快取節點連線至**託管的 Tuist 伺服器**時，請在開發者殼層與 CI 中設定明確的端點：

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

此覆寫在任何伺服器類型上都具有優先權，對於自行託管的 Tuist 伺服器則是可選。針對 Xcode 快取守護程式，設定後請重新執行 `tuist setup cache`，讓 LaunchAgent 收到更新後的環境變數。若有多个節點，請使用你的負載平衡器或 DNS 路由名稱。

## 先決條件 {#prerequisites}


- Docker 與 Docker Compose（或任何容器執行環境）
- 正在執行的 Tuist 伺服器（託管或自行託管）
- 快取所需的磁碟空間。橋接節點在首次加入時會拉取帳戶的**整個**網狀架構，請據此調整資料卷的大小。

## 提供控制平面用戶端 {#control-plane-client}

節點使用控制平面用戶端憑證來驗證快取請求（權杖內省）、向儀表板回報，並傳送使用量。這**並非**在自行託管的 Tuist 伺服器上將用戶端路由到你的節點的方式（請參閱[用戶端如何連線到你的節點](#routing)）。

若要進行完全自行託管的部署，請產生一個**UUID 用戶端 ID**與隨機密鑰，然後在 Tuist 伺服器與每個 Kura 節點上設定相同的配對：

```bash
KURA_CONTROL_PLANE_CLIENT_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
KURA_CONTROL_PLANE_CLIENT_SECRET="$(openssl rand -base64 32)"
```

將這些值設為 Tuist 伺服器環境中的 `KURA_CONTROL_PLANE_CLIENT_ID` 與 `KURA_CONTROL_PLANE_CLIENT_SECRET`，然後在下方的 Kura 設定中使用相同的值。註冊心跳包含 `KURA_TENANT_ID`（帳戶的永久快取身分），因此即使帳戶更名，伺服器仍能將節點關聯到正確的帳戶。

> [!WARNING]
> 用戶端 ID 必須是不帶 `kura_` 前綴的 UUID。非 UUID 的 ID 會導致權杖內省以 HTTP `400` 失敗，即使兩個服務的憑證相符亦然。

若你連線至託管的 `tuist.dev` 伺服器，或希望取得可從 UI 輪換的每帳戶憑證，請開啟帳戶的 **Cache** 頁面，選擇 **Generate credential**，並複製 `client_id` 以及一次性 `secret`。在託管伺服器上，產生自行託管節點憑證需要 Enterprise 方案。

## 選擇永久租戶 {#permanent-tenant}

`KURA_TENANT_ID` 是永久的儲存與對等身分，最初衍生自帳戶的原始代號。若帳戶從未更名，它會與目前的代號相符。**帳戶更名後仍保留其原始值**，包括新增替換節點或將另一個節點加入同一網狀架構時。例如，將 `original` 更名為 `renamed` 後，每個節點上的 `KURA_TENANT_ID=original` 仍保持不變。變更它會選擇不同的物件鍵命名空間；帳戶更名不會遷移已儲存的構件或對等身分。

將下方範例中的 `<permanent-kura-tenant>` 替換為此值。重複使用現有正確設定節點的租戶，或使用註冊所回傳的 `tenant_id`。自行託管 Tuist 伺服器的營運者可檢查帳戶的 `kura_tenant_id` 資料庫欄位。不要從已更名帳戶的 URL 推斷該值。

使用有效的部署層級控制平面憑證時，若節點提供的目前或保留代號與其永久租戶不同，註冊與對等發現會回傳 **409 Conflict**，並附上 `error: "tenant_mismatch"` 與 `expected_tenant_id`。它們不會註冊該節點，也不會靜默替換為不同的儲存身分。無效的憑證與未知的租戶仍會回傳 **401 Unauthorized**，且不會揭露租戶資訊。若節點已使用不同的租戶寫入資料，請在變更前檢視其設定與儲存歷史；錯誤回應不會執行儲存遷移。

## 用戶端如何連線到你的節點 {#routing}

設定[上方](#cli-endpoint)的快取 URL，讓開發者機器與 CI 能夠連線到你的節點。若要在儀表板中回報每個節點的位址與就緒狀態，請在節點上設定 `KURA_REGISTRATION_URL` 與 `KURA_ADVERTISED_HTTP_URL`。

## 橋接設定 {#bridged-setup}

節點會在啟動時註冊：它在本地產生金鑰組（私鑰絕不會離開你的基礎設施），傳送憑證簽署請求，並接收已簽署的憑證、帳戶 CA，以及受管網狀架構的閘道位址。**你不需要提供任何 TLS 材料**。註冊程序會將其寫入掛載的磁碟區。

```yaml
# docker-compose.yml
services:
  kura:
    image: ghcr.io/tuist/kura:<version>
    restart: unless-stopped
    ports:
      - "4000:4000"   # HTTP cache: your developers and CI point here
      - "7443:7443"   # mesh peer port
    environment:
      # Enroll and join the managed mesh
      KURA_ENROLL_ON_BOOT: "1"
      KURA_CONTROL_PLANE_URL: "https://tuist.dev"
      KURA_CONTROL_PLANE_CLIENT_ID: "<client_id>"
      KURA_CONTROL_PLANE_CLIENT_SECRET: "<secret>"
      KURA_TENANT_ID: "<permanent-kura-tenant>"

      # Report the node’s address and readiness to the dashboard
      KURA_REGISTRATION_URL: "https://tuist.dev/_internal/kura/mesh/registrations"
      KURA_ADVERTISED_HTTP_URL: "https://kura.acme.internal"   # where your CLI/CI reach the cache
      KURA_NODE_URL: "https://kura.acme.internal:7443"         # this node's peer identity on your network
      KURA_REGION: "office"

      # Ports and storage. KURA_PORT serves both the HTTP cache API and REAPI
      # gRPC (h2c) on one listener. Enrollment writes the TLS files into
      # KURA_INTERNAL_TLS_* on first boot.
      KURA_PORT: "4000"
      KURA_INTERNAL_PORT: "7443"
      KURA_INTERNAL_TLS_CA_CERT_PATH: "/tls/ca.pem"
      KURA_INTERNAL_TLS_CERT_PATH: "/tls/tls.crt"
      KURA_INTERNAL_TLS_KEY_PATH: "/tls/tls.key"
      KURA_DATA_DIR: "/var/cache/kura"
      KURA_TMP_DIR: "/var/cache/kura/tmp"
      KURA_OTEL_SERVICE_NAME: "kura-acme"
      KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "onprem"

      # Authenticate the HTTP cache API. The Tuist hook ships in the image at
      # this path; it introspects each token against the control plane using the
      # control-plane client above, so only valid Tuist tokens for this account
      # can read or write. No JWT verifier secret is involved.
      KURA_AUTH_ENABLED: "1"
      KURA_AUTH_TUIST_URL: "https://tuist.dev"
    volumes:
      - kura-tls:/tls            # empty; enrollment populates it
      - kura-data:/var/cache/kura
volumes:
  kura-tls: {}
  kura-data: {}
```

你需要提供：控制平面用戶端、網路上的兩個位址（`KURA_NODE_URL`、`KURA_ADVERTISED_HTTP_URL`），以及兩個空的 writable 磁碟區。其他所有項目（金鑰組、憑證、帳戶 CA，以及受管網狀架構的位址）都會在啟動時自動佈建。

## 獨立設定 {#standalone-setup}

由於沒有受管區域，因此沒有 Tuist 簽發的網狀 CA，故不適用註冊流程（註冊端點會回傳 `503 ca_unavailable`）。節點會使用你的 Tuist 伺服器進行權杖驗證、儀表板註冊心跳，以及使用量回報。

```yaml
# docker-compose.yml for a single node connected to a self-hosted Tuist server
services:
  kura:
    image: ghcr.io/tuist/kura:<version>
    restart: unless-stopped
    ports:
      - "4000:4000"
      - "7443:7443"
    environment:
      KURA_TENANT_ID: "<permanent-kura-tenant>"
      KURA_NODE_URL: "http://kura-1.acme.internal:7443"
      KURA_PEERS: ""   # single node: disable static peer discovery
      KURA_REGION: "office"

      # Authenticate cache requests against the self-hosted Tuist server.
      # Use the same values configured on the Tuist server, or a per-account
      # credential from the Cache page.
      KURA_CONTROL_PLANE_CLIENT_ID: "<client_id>"
      KURA_CONTROL_PLANE_CLIENT_SECRET: "<secret>"
      KURA_AUTH_ENABLED: "1"
      KURA_AUTH_TUIST_URL: "https://tuist.acme.internal"

      # Register the client-facing cache URL with the Tuist server.
      KURA_REGISTRATION_URL: "https://tuist.acme.internal/_internal/kura/mesh/registrations"
      KURA_ADVERTISED_HTTP_URL: "https://kura.acme.internal"

      KURA_PORT: "4000"
      KURA_INTERNAL_PORT: "7443"
      KURA_DATA_DIR: "/var/cache/kura"
      KURA_TMP_DIR: "/var/cache/kura/tmp"
      KURA_OTEL_SERVICE_NAME: "kura-acme"
      KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "onprem"
    volumes:
      - kura-data:/var/cache/kura
volumes:
  kura-data: {}
```

對於單一節點，請保持對等 TLS 未設定，並將 `KURA_PEERS` 設為空字串。當 `KURA_PEERS` 未設定時，Kura 會從 `KURA_NODE_URL` 種子化靜態對等發現，並定期檢查該 URL 的 `/_internal/status` 端點。停用對等 TLS 時，即使透過私有網路名稱可連線至節點，`KURA_NODE_URL` 仍必須使用 `http://` 協定。

此範例中不需要 `KURA_CONTROL_PLANE_URL`，因為授權與使用量回報器皆使用 `KURA_AUTH_TUIST_URL` 作為 Tuist 基礎 URL。`KURA_ADVERTISED_HTTP_URL` 用於在儀表板中标識節點的用戶端 facing 位址。在 Tuist 伺服器上設定 `TUIST_CACHE_ENDPOINTS=https://kura.acme.internal`，讓 CLI 使用該位址進行快取請求。

### 使用 Helm 的 Kubernetes {#standalone-helm}

若你的自行託管 Tuist 伺服器執行於 Kubernetes 上，請使用獨立 Kura chart 安裝 Kura，並透過 `extraEnv` 傳遞相同的控制平面設定。Tuist 伺服器 chart 不會將此 Kura chart 安裝為子 chart。

首先，使用部署層級的 Kura 憑證設定 Tuist 伺服器 chart：

```yaml
# tuist-values.yaml
server:
  extraEnv:
    - name: KURA_CONTROL_PLANE_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: kura-control-plane
          key: client-id
    - name: KURA_CONTROL_PLANE_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: kura-control-plane
          key: client-secret
```

接著，在同一個命名空間中使用相同的 Secret 安裝 Kura：

```yaml
# kura-values.yaml
replicaCount: 1

config:
  tenantId: "<permanent-kura-tenant>"
  region: "office"

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: kura.acme.internal
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - kura.acme.internal
      secretName: kura-tls

extraEnv:
  - name: KURA_CONTROL_PLANE_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: kura-control-plane
        key: client-id
  - name: KURA_CONTROL_PLANE_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: kura-control-plane
        key: client-secret
  - name: KURA_AUTH_ENABLED
    value: "1"
  - name: KURA_AUTH_TUIST_URL
    value: "https://tuist.acme.internal"
  - name: KURA_REGISTRATION_URL
    value: "https://tuist.acme.internal/_internal/kura/mesh/registrations"
  - name: KURA_ADVERTISED_HTTP_URL
    value: "https://kura.acme.internal"
```

```bash
kubectl create namespace tuist
kubectl -n tuist create secret generic kura-control-plane \
  --from-literal=client-id="<client_id>" \
  --from-literal=client-secret="<secret>"

helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace tuist \
  -f kura-values.yaml
```

若 Kura 執行於與 Tuist 伺服器不同的命名空間，請建立或同步 `kura-control-plane` Secret 到這兩個命名空間。

使用映像中內建的 Tuist hook 時，請保持 `extension.enabled` 未設定；該 chart 值是用於從 ConfigMap 掛載自訂 hook。Chart 會為你渲染 `KURA_NODE_URL`、`KURA_PEERS`、headless service、持久化儲存與探針。當 `replicaCount: 1` 時，產生的對等 URL 是 Pod 自身的穩定 DNS 名稱，因此在叢集內仍可連線，且不會產生上述的單一節點警告。對於多個複本，chart 會從 StatefulSet DNS 產生對等清單；若希望在內部對等平面上使用 mTLS，請啟用 `peerTls` 並提供 TLS Secret。

若要執行多個獨立節點，請加入你自己的**對等 TLS**並掛載於 `/tls`（每個節點包含一個 CA 加上葉憑證與金鑰，共用同一個 CA 以便節點互相信任），將 `KURA_NODE_URL` 切換為 `https://...:<KURA_INTERNAL_PORT>`，並新增 `KURA_PEERS`：

```yaml
environment:
  KURA_NODE_URL: "https://kura-1.acme.internal:7443"
  KURA_PEERS: "https://kura-2.acme.internal:7443,https://kura-3.acme.internal:7443"
  KURA_INTERNAL_TLS_CA_CERT_PATH: "/tls/ca.pem"
  KURA_INTERNAL_TLS_CERT_PATH: "/tls/tls.crt"
  KURA_INTERNAL_TLS_KEY_PATH: "/tls/tls.key"
volumes:
  - ./tls:/tls:ro
```

## 每種拓撲所需項目 {#requirements-summary}

| 你需提供 | 橋接 | 獨立 |
|---|---|---|
| 控制平面用戶端（`client_id` / `secret`） | 是 | 是 |
| `KURA_NODE_URL` | 是 | 是 |
| `KURA_ADVERTISED_HTTP_URL` | 是 | 用於儀表板註冊；路由另行處理（見下文） |
| CLI 路由 | 自動（註冊） | 依據就緒的註冊心跳自動設定 |
| 資料 + 暫存磁碟區 | 是 | 是 |
| `KURA_ENROLL_ON_BOOT` | 是 | 否（會回傳 `ca_unavailable`） |
| 對等 TLS（`/tls` CA + 葉憑證） | 否，註冊程序會寫入 | 僅限多節點網狀架構 |
| `KURA_PEERS`（對等清單） | 否，註冊程序會為閘道器播種 | 單一節點時留空；多節點時填寫對等 URL |

## 必要設定 {#required-config}

這些變數會設定每個節點，不論拓撲為何（對等 TLS 是下述例外）：

| 變數 | 說明 |
|---|---|
| `KURA_TENANT_ID` | 你帳戶的永久 Kura 租戶。重新命名帳戶後請保留其原始值；請參閱[選擇永久租戶](#permanent-tenant)。 |
| `KURA_NODE_URL` | 此節點在你網路上的對等 URL。 |
| `KURA_PEERS` | 靜態對等發現清單。單一獨立節點請設為空字串；多節點網狀架構請設定可連線的對等 URL。 |
| `KURA_REGION` | 自由格式的區域標籤（例如 `office`、`ci`）。 |
| `KURA_PORT` / `KURA_INTERNAL_PORT` | 快取連接埠（HTTP 快取 API 與 REAPI gRPC 共用同一個監聽器）以及網狀對等連接埠（`4000` / `7443`）。 |
| `KURA_DATA_DIR` / `KURA_TMP_DIR` | 磁碟上的構件儲存與暫存目錄。 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` / `KURA_INTERNAL_TLS_CERT_PATH` / `KURA_INTERNAL_TLS_KEY_PATH` | 對等 TLS 檔案。由註冊程序寫入（橋接）或由你提供（多節點獨立）。單一節點不需要；省略它們並使用 `http://` `KURA_NODE_URL`。 |
| `KURA_OTEL_SERVICE_NAME` / `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | 遙測的服務名稱與環境標籤。 |

橋接節點還會設定 `KURA_ENROLL_ON_BOOT`、`KURA_CONTROL_PLANE_URL` 以及控制平面用戶端憑證。`KURA_REGISTRATION_URL` 與 `KURA_ADVERTISED_HTTP_URL` 會註冊節點，使其出現在 **快取** 頁面，並讓啟用 Kura 的 CLI 用戶端能夠路由至該節點（請參閱 [用戶端如何連線到你的節點](#routing)）。

## 儲存與淘汰 {#storage}

節點會在 `KURA_DATA_DIR` 下儲存構件，上限為 CAS 儲存預算，你可以透過選用變數設定：

| 變數 | 說明 |
|---|---|
| `KURA_CAS_CAPACITY_BYTES` | 節點的 CAS 儲存預算（位元組）。必須為正整數。未設定時，預算為持有 `KURA_DATA_DIR` 的檔案系統大小的 50%。 |

無論你是否設定，預算上限皆為持有 `KURA_DATA_DIR` 之檔案系統大小的 80%，這樣輪替機制在淘汰最舊區段前先寫入新區段時，不會填滿磁碟。預算會四捨五入為完整的 512 MiB 區段，最小值為 2.5 GiB。節點會在啟動時記錄解析後的預算（`resolved CAS segment ring limits`）。

淘汰是自動的。構件儲存在環狀區段中，一旦達到預算上限，最舊的區段就會被淘汰。從較舊區段讀取的構件會提升到當前區段，因此常用構件會被保留，淘汰行為接近最近最少使用（LRU）。

將 `KURA_DATA_DIR` 放在專用磁碟區上。預設預算與上限都是基於檔案系統的總大小百分比，而非可用空間，因此同一檔案系統上的其他資料可能會使實際可用空間低於預算假設。

## 快取請求的身份驗證 {#cache-auth}

預設情況下，節點會對網路上任何能連線到它的對象提供 HTTP 快取 API。若要求呼叫者出示有效的 Tuist 權杖，以便只有你組織中經過驗證的成員才能讀寫，請將節點指向你的 Tuist 伺服器。上述獨立設定即以此方式運作。

| 變數 | 值 |
|---|---|
| `KURA_AUTH_ENABLED` | `1` |
| `KURA_AUTH_TUIST_URL` | 你的 Tuist 伺服器 URL |

授權會重複使用你已設定的控制平面用戶端（`KURA_CONTROL_PLANE_CLIENT_ID` / `KURA_CONTROL_PLANE_CLIENT_SECRET`）來內省權杖，因此不需要額外憑證。自行託管的節點僅執行**內省**：它從未持有對稱的 Guardian JWT 驗證器密鑰，該密鑰可為任何租戶簽發權杖且絕不共享，因此每個請求都會向你的伺服器進行授權。無法連線到伺服器的節點會拒絕服務而非提供服務，且沒有設定可以改變此行為。Tuist 管理的節點執行相同的授權；唯一差別是它們也持有驗證金鑰，這讓它們能僅憑權杖就處理大多數請求。

## 網路 {#networking}

節點會根據你啟用的整合項目建立**出站**連線：

- 你的 Tuist 伺服器用於權杖內省（`KURA_AUTH_TUIST_URL`）、註冊心跳（`KURA_REGISTRATION_URL`）、用量（`KURA_CONTROL_PLANE_URL` 或 `KURA_AUTH_TUIST_URL`），以及在橋接拓撲中的註冊，以及
- 在橋接拓撲中，受管網狀架構的對等閘道器，用於複寫。

你的開發人員與 CI 會連線到節點的 `KURA_ADVERTISED_HTTP_URL`（對於多節點網狀架構，節點之間則透過對等連接埠互相連線）。這些地址只需在你的**網路內部**可達即可。無需暴露於公開網際網路。

## 行為方式 {#behavior}

- **橋接。** 啟動時節點會註冊、拉取受管網狀架構的完整快取，並轉換為環狀結構中的服務成員。初始拉取只會發生一次，在廣域網路上可能需要一段時間，規模取決於你的快取大小。此後，節點上的寫入會持續傳播到受管網狀架構。節點加入後，在受管網狀架構其他處寫入的新構件尚未持續傳播到該節點（這是計畫中的增強功能），因此請將加入時的拉取視為快照而非即時鏡像。
- **獨立。** 節點在你的基礎設施上作為隔離的網狀架構執行。若有複寫，僅發生在你自己的節點之間。設定後，Tuist 的角色限於控制平面：儀表板可見性、快取端點廣告、用量計量與權杖內省。它絕不會配置、升級、與你的節點建立對等關係，或深入存取你的節點。

## 驗證 {#verify}

```bash
curl --fail-with-body http://localhost:4000/ready   # 200 once the node has joined and is serving
curl --fail-with-body http://localhost:4000/up      # liveness + mesh membership
```

橋接節點在拉取網狀架構期間會回報 `state: joining`，追上進度後則回報 `state: serving`。一旦開始註冊心跳，你的節點也會出現在帳戶的 **快取** 頁面下的 **已註冊節點** 中。

若要驗證遠端快取，請使用未快取且可快取的目標執行 `tuist cache`，並在 Kura 日誌中確認上傳成功。僅憑零退出狀態並不能確認構件已儲存。

## 升級 {#upgrading}

```bash
docker compose pull
docker compose up -d
```

節點設計為可容忍一個版本的差異並平行執行，因此在多個節點上進行滾動升級是安全的。
