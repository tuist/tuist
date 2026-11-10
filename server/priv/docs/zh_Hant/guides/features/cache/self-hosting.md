---
{
  "title": "自託管快取",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "部署自託管快取節點並將其連接至 Tuist。"
}
---

# 自建快取 {#self-hosted-cache}

自建快取節點可讓建置產物與快取中繼資料緊鄰產生並消耗建置輸出的機器。當 CI、開發者辦公室、遠端工作站或區域運算叢集之間的快取延遲至關重要時，請使用這些節點。

目標是在各處實現低延遲快取，而不僅限於中央快取恰好鄰近的單一環境。每個快取節點從本機磁碟提供讀寫服務，同時網格會在對等節點之間複製產物與中繼資料，讓其他位置隨時間也能受益於相同的快取。

> [!NOTE]
> Tuist 的自建快取節點由 [Kura](https://github.com/tuist/tuist/tree/main/kura)（Tuist 的去中心化快取網格）驅動。Kura 是快取節點的資料平面：它提供快取讀寫服務、將本機狀態儲存於磁碟，並將產物與中繼資料複製到對等節點。

## 自建快取如何與 Tuist 搭配使用 {#how-self-hosted-cache-fits-with-tuist}

Tuist 的受管快取使用 `https://<account>.cache.tuist.dev`。使用自建的 Tuist 伺服器時，CLI 會從伺服器的 `TUIST_CACHE_ENDPOINTS` 設定取得快取 URL。將其設為你的主要快取伺服器或負載平衡器的 URL。若包含多個 URL，則使用第一個。

對於連線至 **託管 Tuist 伺服器** 的私人／自訂快取節點，請在開發者 Shell 與 CI 中設定明確的端點：

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

此覆寫在兩種伺服器類型上皆具優先順序，且對於自建的 Tuist 伺服器為選用項目。針對 Xcode 快取常駐程式，設定後請重新執行 `tuist setup cache`，以便 LaunchAgent 接收更新後的環境變數。

自建的 Tuist 伺服器從靜態設定取得端點。在 Tuist 託管的伺服器上，節點會使用憑證進行驗證並註冊自身。先依照下方兩個章節之一部署節點，然後參閱 [將節點連線至 Tuist](#connect-nodes-to-tuist)。

## 在 Kubernetes 上部署 {#deploy-on-kubernetes}

Kura 以 Helm Chart 的形式透過 GitHub Container Registry 發布。它將 Kura 部署為具備持續性磁碟區的 `StatefulSet`、用於對等發現的無頭服務，以及用於 HTTP 與 gRPC 流量的常规服務。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

若在同一叢集中有自建的 Tuist 伺服器，請設定其主要快取端點：

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

這會在伺服器 Pod 中設定 `TUIST_CACHE_ENDPOINTS`。請使用開發者機器與 CI 能夠存取的位址；上述叢集內部的服務名稱適合在叢集內部執行的用戶端。

> [!IMPORTANT]
> 每個 Kura 節點必須擁有自己的 `KURA_DATA_DIR`。Kura 會對資料目錄取得應用程式層級的寫入鎖，並預期只有一個程序擁有該目錄。在 Kubernetes 中，請為每個 Pod 使用一個持續性磁碟區。在 Kubernetes 之外，請勿讓多個程序指向同一個掛載目錄。

## 不在 Kubernetes 上部署 {#deploy-without-kubernetes}

Kura 也可以作為一般容器在虛擬機器或裸機主機上執行。在此模式下，你需負責程序監控、持續性儲存、路由與對等發現。

至少，每個節點都需要一個持續性資料目錄、一個暫存目錄、一個公開快取連接埠（單一接聽器同時提供 HTTP 快取 API 與 REAPI gRPC）、一個內部對等 URL，以及靜態對等清單或發現機制：

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/var/cache/kura/tmp \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

在自建的 Tuist 伺服器上，設定開發者機器與 CI 能夠存取的主要快取 URL：

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## 將節點置於負載平衡器後方 {#load-balancers}

用戶端對每個快取端點 URL 同時使用 HTTP 與 gRPC：HTTP 用於健康檢查與 HTTP 快取 API，gRPC 用於模組快取與 Bazel 的遠端快取。用戶端與 Kura 之間的任何入口、負載平衡器或 CDN 都必須在同一主機名稱與連接埠上轉發兩者。這適用於用戶端收到的每個端點，因為 CLI 會選擇回應最快的端點。若 gRPC 無法到達 Kura，CLI 會警告遠端模組快取不可用，並僅使用本機模組快取。

將這些路徑前綴以 HTTP/2 上的 gRPC 路由至 Kura，其餘則以 HTTP 路由：

| 路徑前綴 | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | 模組快取、Bazel |
| `/google.bytestream.` | 模組快取、Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel 建置事件 |

Kura 在 `KURA_PORT` 上接受明文 HTTP/2（h2c），並在設定 `KURA_PUBLIC_TLS_CERT_PATH` 與 `KURA_PUBLIC_TLS_KEY_PATH` 時於 `KURA_HTTPS_PORT` 上接受透過 TLS 的 HTTP/2。若你的代理伺服器會跨請求重複使用上游連線（例如 ingress-nginx），請設定 `KURA_GATEWAY_GRPC_PORT` 並將 gRPC 流量傳送至該連接埠。它仅提供 gRPC 服務，因此 HTTP/1.1 與 gRPC 請求不會共用同一條連線。

使用以下設定來組態 gRPC 路由：

- 無請求主體大小限制。上傳會在單一請求中傳送一個檔案，最多 2 GiB。
- 關閉請求與回應緩衝。
- 讀取、傳送與閒置逾時至少為 300 秒。

Kura 不提供 gRPC 健康檢查服務。請透過 HTTP 在 `/ready` 對節點進行健康檢查。若你的負載平衡器需要 gRPC 健康檢查，請呼叫 `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` 並接受 gRPC 狀態碼 `0` 與 `16`。啟用授權的節點會以 `16`（`UNAUTHENTICATED`）回應沒有權杖的請求。

### ingress-nginx {#load-balancers-ingress-nginx}

使用 Helm Chart 時，請將 HTTP Ingress 保留在 `/`，並為相同主機新增 gRPC Ingress。只有 HTTP Ingress 宣告 TLS：

```yaml
service:
  gatewayGrpcPort: 4001

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - kura.example.com
      secretName: kura-tls

grpcIngress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /build\.bazel\.remote\.execution\.v2\.
          pathType: ImplementationSpecific
        - path: /google\.bytestream\.
          pathType: ImplementationSpecific
        - path: /build\.bazel\.remote\.asset\.v1\.
          pathType: ImplementationSpecific
        - path: /google\.devtools\.build\.v1\.
          pathType: ImplementationSpecific
```

### AWS Application Load Balancer {#load-balancers-aws-alb}

gRPC 目標群組需要 HTTPS 接聽器。在該接聽器上：

1. 將預設規則轉送至協定版本為 `HTTP1` 且位於 `KURA_PORT` 的目標群組，並透過 HTTP 在 `/ready` 進行健康檢查。
2. 建立第二個目標群組，協定版本為 `gRPC`，在 `KURA_GATEWAY_GRPC_PORT`（或 `KURA_PORT`）上使用協定 `HTTP`，或在 `KURA_HTTPS_PORT` 上使用協定 `HTTPS`。依上述說明組態其健康檢查。
3. 新增一條規則，將路徑模式 `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*` 與 `/google.devtools.build.v1.*` 轉送至第二個目標群組。
4. 將負載平衡器的閒置逾時提高至至少 300 秒。

### CDN {#load-balancers-cdns}

位於節點前方的 CDN 必須支援 gRPC，且不得在其防火牆規則中封鎖 gRPC 路徑。用戶端會以最多 2 MiB 的區塊上傳大型構件，並由節點進行組裝，因此沒有任何請求需要大型主體或長時間的上傳。模組快取與 Xcode 編譯快取皆採用此方式，而 Bazel 在使用 `--experimental_remote_cache_chunking` 建置時也會如此（Bazel 8.7 及 9.1 以上版本）。若未使用該旗標，Bazel 會在單一請求中上傳每個輸出檔案，因此 CDN 也必須允許大型請求主體，以及在上傳時間等於你最慢連線傳輸最大輸出檔案所需時間的情況下仍能完成上傳。若你的 CDN 無法符合這些需求，請提供用戶端一個可繞過 CDN 的主機名稱，例如僅含 DNS 的記錄。

#### Cloudflare {#load-balancers-cloudflare}

在任何方案中，模組快取皆可透過已代理的 Cloudflare 主機名稱運作。在區域中：

1. 在 **網路** 下，開啟 **gRPC**。
2. 在 **SSL/TLS** 下，將加密模式設定為 **完整** 或 **完整（嚴格）**。Cloudflare 會透過連接埠 443 連線至來源伺服器，因此來源伺服器必須在該處提供 TLS 服務，並透過 ALPN 提供 HTTP/2。
3. 確認沒有任何 WAF 自訂規則或受管理規則封鎖上述 gRPC 路徑。

若來源伺服器在大約兩分鐘後仍未開始回應，Cloudflare 會終止請求。未使用 `--experimental_remote_cache_chunking` 的 Bazel 上傳只有在最後一個位元組送達後才會收到回應，因此在 Cloudflare 上，若上傳時間超過該期限，這類上傳就會失敗。

## 將節點連線至 Tuist {#connect-nodes-to-tuist}

組態用戶端路由並將你的節點註冊至 Tuist，以便在儀表板中顯示其位址、就緒狀態與使用情況。

在 **自行託管的 Tuist 伺服器** 上，你需使用 `TUIST_CACHE_ENDPOINTS` 靜態宣告端點，如上述部署章節所示。CLI 會使用第一個設定的 URL。`TUIST_CACHE_ENDPOINT` 會為個別用戶端覆寫該 URL。

在 **Tuist 託管的伺服器** 上，於開發者 shell 與 CI 中設定 `TUIST_CACHE_ENDPOINT`，以將快取請求路由至你的節點。每個節點會使用你產生的憑證進行驗證，然後註冊其位址並向儀表板回報其就緒狀態。本節說明節點註冊。

> [!IMPORTANT]
> **Enterprise 方案**
>
> 自行託管的快取節點僅限 Enterprise 方案使用。下方所述的 **自行託管伺服器** 區段僅對屬於該方案的帳戶顯示。

### 產生節點憑證 {#generate-a-node-credential}

在 Tuist 儀表板中，開啟你的帳戶，前往 **快取**，並找到 **自行託管伺服器**。選擇 **產生憑證** 以鑄造客戶端 ID 與密鑰。

該憑證僅授權建立它的帳戶之流量。

密鑰僅顯示一次，關閉對話框後即無法復原，因此請將其直接複製到節點讀取的密鑰儲存庫中。撤銷憑證會立即停止所有使用該憑證的節點進行驗證，因此在撤銷正在使用的憑證前，請先產生替代憑證。

### 在開機時註冊節點 {#enroll-the-node-on-boot}

註冊是啟動節點的建議方式。設定 `KURA_ENROLL_ON_BOOT` 並提供節點其憑證與自身的對等 URL：

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

節點會在本地產生其金鑰組，因此私鑰絕不會離開節點，並會接收簽署過的對等憑證、帳戶 CA、其租戶識別碼與對等清單。這就是你原本需要手動組態的所有內容：已註冊的節點不需要 `KURA_TENANT_ID`、不需要 `KURA_PEERS`，也不需要對等 TLS 設定。

不要設定 `KURA_INTERNAL_TLS_*`：註冊過程會將憑證資料寫入 `KURA_DATA_DIR` 下的 `tls` 目錄。僅在你自行提供憑證而非透過註冊取得時，才自行設定這些路徑，如 [建置快取網格](#build-a-cache-mesh) 所述。

首次加入帳戶網格的節點，在成為環中的服務成員之前，會先提取帳戶現有的快取。請為整個快取調整資料卷大小，並預期首次joining 在廣域網路上會花費一段時間。節點會回報 `joining`，直到同步完成，之後則回報 `serving`。

### 通告端點 {#advertise-the-endpoint}

註冊會加入網格。註冊會向 Tuist 回報節點的用戶端可見位址與就緒狀態。設定註冊變數：

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

節點每 60 秒針對 180 秒的租約發送心跳。當租約到期時，Tuist 會將其註冊視為不可用。Tuist 從不呼叫節點，因此節點只需讓你的用戶端可存取，無需從網際網路存取。

### 驗證節點是否正在服務 {#verify-the-node-is-serving}

回到儀表板中的 **快取**，節點會出現在 **已註冊節點** 下方，並顯示其端點、區域、狀態與最後心跳時間。從未出現的節點表示未到達註冊端點或授權失敗。出現後又消失的節點表示已停止發送心跳或停止回報就緒狀態。

### 使用帳戶的永久租戶識別碼 {#match-the-tenant-identifier}

`KURA_TENANT_ID` 是帳戶的永久快取身分識別。對於從未重新命名的帳戶，它等於帳戶控制代碼。重新命名後，請在所有節點（包括替換節點）上保留原始值：變更它會選擇不同的儲存命名空間，而重新命名帳戶不會遷移已儲存的構件。請重複使用現有節點的租戶或由註冊回傳的 `tenant_id`，而非從帳戶目前的 URL 推斷。

控制平面會將心跳中的租戶與從憑證解析出的帳戶進行比較，並以 `409 tenant_mismatch` 拒絕不相符的情況，因此具有錯誤值的節點雖能成功驗證，卻永遠無法註冊。

> [!IMPORTANT]
> 本指南前文的 Helm Chart 與容器範例均預設此值為 `default`。在註冊節點前，請將其替換為帳戶的租戶識別碼。透過註冊節點可完全避免此問題，因為控制平面會提供該值。

未設定 `KURA_TENANT_ID` 並不會跳過檢查。它會完全停用註冊：節點會繼續服務快取流量，但儀表板中不會顯示任何內容，也不會回報錯誤。若節點運作正常但未出現在 **已註冊節點** 中，請先檢查此變數。

### 選擇用戶端可存取的通告 URL {#choose-an-advertised-url}

為 `KURA_ADVERTISED_HTTP_URL` 以及在 Tuist 伺服器或 CLI 上組態的快取 URL 使用用戶端可存取的位址。

當所有組態為使用該名稱的用戶端都能解析並存取時，僅限內部使用的主機名稱即屬合適。對於位於不同網路的用戶端，請使用共用的可存取位址，或為每個環境組態一個可存取的快取節點。

## 建置快取網格 {#build-a-cache-mesh}

快取網格讓你將快取容量部署在需要運算資源的旁邊。公司可能在主要 CI 執行器附近運行一個節點，在歐洲開發者附近運行另一個節點，並在美國辦公室或區域建置叢集附近運行第三個節點。每個位置都會讀取和寫入最近的節點，而 Kura 會在背景複製構件與中繼資料，讓其他位置後續的建置能夠重複使用相同的輸出。

只有在節點能透過 Kura 的內部對等連接埠互相存取時，網格才能運作。該對等平面與 Tuist 用戶端使用的公開快取端點是分開的。Kura 使用它來檢查成員資格、回填新加入的節點，以及在接受本機寫入後複製構件。

當節點跨區域、雲端、VPC、辦公室或任何非完全私有於快取部署的網路進行通訊時，我們強烈建議使用 [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) 保護對等平面。啟用 mTLS 後，Kura 僅向提供由已組態 CA 簽署之憑證的對等節點服務內部複製端點。對等憑證必須涵蓋節點用於互相呼叫的 DNS 名稱，且對等 URL 必須在內部連接埠上使用 `https://`。

> [!NOTE]
> 向 Tuist 託管的控制平面註冊的節點會在註冊期間接收其對等憑證與帳戶 CA，因此以下手動步驟適用於未進行註冊的網格。

例如，這會產生一個私有 CA 與一個對等憑證，可供小型網格中的每個節點掛載。請將 DNS 名稱替換為你的節點在 `KURA_NODE_URL` 與 `KURA_PEERS` 中使用的內部名稱。

```bash
mkdir -p kura-peer-tls
cd kura-peer-tls

openssl ecparam -genkey -name prime256v1 -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=kura-peer-ca" \
  -out ca.pem

openssl ecparam -genkey -name prime256v1 -noout -out tls.key
openssl req -new -key tls.key \
  -subj "/CN=kura-peer" \
  -out peer.csr

cat > peer.ext <<'EOF'
subjectAltName = DNS:kura-0.kura-headless.kura.svc.cluster.local,DNS:kura-1.kura-headless.kura.svc.cluster.local,DNS:kura-2.kura-headless.kura.svc.cluster.local,DNS:kura-1.internal,DNS:kura-2.internal
extendedKeyUsage = serverAuth,clientAuth
keyUsage = digitalSignature,keyEncipherment
EOF

openssl x509 -req -in peer.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 730 \
  -sha256 \
  -extfile peer.ext
```

### 節點間的同步 {#catch-up-between-nodes}

加入或重新加入網格的節點會進行 **回填**：它會依最新優先順序走訪每個對等節點的項目並拉取缺少的內容，而即時複製則涵蓋對等節點可見期間所做的寫入。回填過程會從對等節點的最新項目回溯至節點區段環視野與其上次完成回合中較舊者，因此保證節點持有近期資料，但不一定是全部資料。`KURA_BACKFILL_MARGIN_PERCENT` 設定視野回溯的範圍。

在運行網格前，有兩項後果值得了解：

- 一旦節點的區段環達到 `KURA_BACKFILL_READY_RING_PERCENT` 滿載 **或** 其首次回填週期穩定下來，節點就會回報 `/ready`，且就緒狀態將在程序剩餘生命週期中保持。後續的對等節點波動絕不會將服務中的節點移出輪轉。
- 當對等節點長時間無法存取時，週期也會穩定下來。因此，若唯一對等節點宕機，節點會在持有少量或無資料的情況下變更為就緒狀態。它會服務快取未命中而非錯誤。若你想根據差異來管控發布，`/status/rollout` 會回報 `backfill_initial_cycle`（`pending`、`complete` 或 `degraded`）。

**在回填變更期間升級網格。** 回填前的 Kura 版本透過另一種現已移除的對等協定進行同步。在採用僅支援回填的版本之前，請先將每個節點滾動更新至執行回填的版本 **。** 使用兩種協定的節點無法互相同步：溫暖節點會繼續從其磁碟區服務，但停止縮小差距；而在該視窗期間從空磁碟區啟動的節點永遠不會變更為就緒狀態。Chart 會為你設定 `KURA_BACKFILL_ENABLED=true`，因此優先升級 Chart 即可涵蓋此情況。單一 `helm upgrade` 同時移動 Chart 與映像檔則無法涵蓋。

除了 mTLS 之外，請使用網路層級的限制。在 Kubernetes 中，將 Kura 作為 `StatefulSet` 運行，每個 Pod 配備一個持久性磁碟區，並使用無頭服務進行對等發現，然後僅允許屬於同一快取部署的 Pod 之間存取內部對等連接埠，例如透過 `NetworkPolicy`。在 Kubernetes 之外，為每個節點賦予穩定的 DNS 名稱或 IP 位址，使用其他節點的內部 URL 初始化網格，並使用防火牆規則或安全群組，確保只有快取節點能存取對等連接埠。公開快取流量應透過公開 HTTP 或 gRPC 端點進入，而非透過內部對等平面。

## 組態 {#configuration}

Helm Chart 會從 `values.yaml` 渲染常見的執行階段設定。若你在沒有 Kubernetes 的情況下運行 Kura，請直接在程序上設定相同的變數。Chart 未直接對應的變數可以透過 `extraEnv` 或 `extraEnvFrom` 注入。

| 環境變數 | 說明 | 必要 | 預設值 | Helm 值 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 公開快取連接埠。單一監聽器服務 HTTP 快取 API、健康狀態端點，以及 Bazel/Buck2 REAPI gRPC (h2c)。 | 是 | 無預設值 | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura 對等節點使用的內部 HTTP 或 mTLS 連接埠。 | 是 | 無預設值 | `peerTls.internalPort` |
| `KURA_TENANT_ID` | 節點的預設租戶識別碼。 | 是 | 無預設值 | `config.tenantId` |
| `KURA_REGION` | 用於指標與複製狀態的區域標籤。 | 是 | 無預設值 | `config.region` |
| `KURA_TMP_DIR` | 用於暫存請求主體與多部分組裝的臨時目錄。 | 是 | 無預設值 | 固定為 `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | 在請求收到背壓之前，允許進入 `KURA_TMP_DIR` 的最大暫存位元組數。 | 否 | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | 用於中繼資料狀態與區段檔案的持久性目錄。 | 是 | 無預設值 | 固定為 `/var/cache/kura` |
| `KURA_NODE_URL` | 其他對等節點用來存取此節點的標準內部 URL。 | 是 | 無預設值 | 衍生自 Pod DNS 名稱與 `peerTls.internalPort` |
| `KURA_PEERS` | 在發現收斂前使用的種子對等節點清單。 | 否 | `KURA_NODE_URL` | 衍生自 StatefulSet 複本 |
| `KURA_DISCOVERY_DNS_NAME` | 用於自動對等節點發現的 DNS 名稱。 | 否 | 已停用 | 由 `config.discovery.enabled` 啟用 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | 用於驗證對等節點 mTLS 的 CA 憑證。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 與 `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 內部對等節點 mTLS 監聽器使用的憑證。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 與 `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 內部對等節點 mTLS 監聽器使用的私鑰。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 與 `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 用於在共置 HTTPS 監聽器（`KURA_HTTPS_PORT`）上終止 TLS 的憑證。 | 否 | 已停用 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | 與 `KURA_PUBLIC_TLS_CERT_PATH` 配對的私鑰。 | 否 | 已停用 | `extraEnv` |
| `KURA_HTTPS_PORT` | 服務相同共置 HTTP + gRPC 介面（ALPN 協商）的 TLS 連接埠。僅在設定公開 TLS 路徑時繫結。 | 否 | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 純文字 HTTP/2 連接埠，僅服務 gRPC API，供重複使用上游連線的 Proxy 使用。請參閱[將節點置於負載平衡器後方](#load-balancers)。 | 否 | 已停用 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | 請求與背景 I/O 的檔案描述元預算。 | 否 | 自動衍生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | 請求在檔案描述元背壓導致簽出失敗前的等待時間。 | 否 | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | 固定區段讀取控制代碼的最大數量。 | 否 | 自動衍生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | 關閉期間處理進行中 HTTP 與 gRPC 工作的寬限期。 | 否 | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura 開始減少非必要記憶體使用的軟性記憶體水位。 | 否 | 自動衍生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura 暫停複製並清理熱門快取的硬性記憶體水位。 | 否 | 自動衍生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | 記憶體內 manifest 快取的最大大小。 | 否 | 自動衍生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | 每個請求的 keyvalue 負載最大大小。 | 否 | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | 保留給中繼資料存放區的檔案描述元預算。 | 否 | 自動衍生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | 中繼資料存放區背景刷寫與壓縮的並行度。 | 否 | 自動衍生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | 中繼資料存放區讀取快取的容量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | 保留給中繼資料寫入緩衝的總記憶體預算。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | 每次刷寫前各中繼資料寫入緩衝的大小。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | 保留在記憶體中的中繼資料寫入緩衝最大數量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 進行中的多部分上傳在過期前可停留的時間。 | 否 | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura 掃描過時多部分上傳的頻率。 | 否 | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 依區段年齡排序的環狀結構中，從最新區段開始計算、用於限制回填作業回溯範圍的比例。 | 否 | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 節點在執行首次回填週期時，將自身回報為就緒所需的區段環飽和度。 | 否 | `KURA_BACKFILL_MARGIN_PERCENT` 的一半 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 組成單一批次回填主體的位元組閾值，以及超過此大小時會單獨抓取的項目大小。 | 否 | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio 工作執行緒數量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP 追蹤端點。留空以停用追蹤功能。 | 否 | 已停用 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry 服務名稱。 | 是 | 無預設值 | Helm 中的 Pod 名稱 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry 部署環境。 | 是 | 無預設值 | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | 用於當機與錯誤回報的 Sentry DSN。 | 否 | 已停用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | 節點所在資料中心的 ISO 3166-1 alpha-2 國家代碼，會以 `geo.country.iso_code` 標記於匯出的追蹤記錄中。 | 否 | 當其前綴為國家代碼時，由 `KURA_REGION` 衍生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | 該資料中心的 ISO 3166-2 行政區劃（例如 `US-CA`），會以 `geo.region.iso_code` 標記。 | 否 | 未設定 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 要求呼叫者提供有效的 Tuist 權杖。設定 `KURA_AUTH_TUIST_URL` 即可單獨啟用授權功能；將此項設為 `false` 並不會關閉授權—若要讓節點在不進行授權的情況下執行，請取消設定該 URL。 | 否 | 已停用 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | 節點用於授權的 Tuist 伺服器。可單獨啟用授權功能。 | 啟用授權時為必填 | 無預設值 | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | 對該伺服器發出呼叫的連線逾時時間。 | 否 | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | 對該伺服器發出呼叫的請求逾時時間。 | 否 | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | 節點可自行讀取權杖的共用密鑰，可省去往返驗證。此密鑰同時用於簽署與驗證，因此僅在節點與伺服器位於相同信任邊界時使用。自託管節點通常不設定此值。 | 否 | 已停用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | 伺服器用來簽署快取權杖的金鑰對公鑰部分，以一個或多個串連的 PEM 區塊表示。可讀取這些權杖但無法簽發新權杖，這正是可從網際網路存取的節點應持有的設定。與 `KURA_AUTH_JWT_SECRET` 互斥。 | 否 | 已停用 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | 該金鑰使用的演算法：搭配密鑰時為 `HS256`、`HS384` 或 `HS512`；搭配公鑰時為 `ES256`。 | 否 | 搭配密鑰時為 `HS256`，搭配公鑰時為 `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | 權杖必須包含的發行者。 | 否 | 未檢查 | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | 權杖必須包含的受眾，以逗號分隔。 | 否 | 未檢查 | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 身份驗證與授權快取中各自保留的最大項目數。 | 否 | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 每次啟動時將節點註冊至控制平面，佈建其對等憑證並提供 `KURA_TENANT_ID` 與 `KURA_PEERS`。 | 否 | 已停用 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | 節點用於註冊的 Tuist 伺服器。 | 註冊時為必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | 在儀表板中產生的節點憑證用戶端 ID。 | 註冊或登記時為必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | 與 `KURA_CONTROL_PLANE_CLIENT_ID` 配對的用戶端密鑰。 | 註冊或登記時為必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_URL` | 節點傳送註冊心跳的絕對 URL，用於公告其面向客戶的端點。 | 登記時為必填 | 無預設值 | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | 控制平面提供給客戶的面向客戶快取 URL。帳戶中的每個客戶都必須能存取此 URL。 | 登記時為必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 註冊心跳頻率。租約容許錯過多次心跳，因此單次心跳遺失不會導致端點被移除。 | 否 | `60000` | `extraEnv` |

若啟用內部對等 mTLS，請同時設定 `KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH` 與 `KURA_INTERNAL_TLS_KEY_PATH`。`KURA_NODE_URL` 及 `KURA_PEERS` 中的每個值都必須使用 `https://` 並搭配內部對等埠。
