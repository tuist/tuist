---
{
  "title": "自託管快取",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "部署自託管快取節點並將其連接至 Tuist。"
}
---

# 自託管快取 {#self-hosted-cache}

自託管快取節點讓你可以將構建產物和快取元數據存放在靠近生產和消費構建輸出的機器附近。當 CI、開發者辦公室、遠程工作站或區域計算集群的快取延遲至關重要時，請使用它們。

目標是在所有地方實現低延遲快取，而不僅僅是在中央快取恰好鄰近的那個環境中。每個快取節點都從本地磁盤提供讀寫服務，而網格會在對等節點之間複製產物和元數據，以便其他位置隨時間推移也能受益於相同的快取。

> [!NOTE]
> Tuist 的自託管快取節點由 [Kura](https://github.com/tuist/tuist/tree/main/kura) 提供支持，這是 Tuist 的去中心化快取網格。Kura 是快取節點的數據平面：它提供快取讀寫服務，在磁盤上存儲本地狀態，並將產物和元數據複製到對等節點。

## 自託管快取如何與 Tuist 配合 {#how-self-hosted-cache-fits-with-tuist}

Tuist 的託管快取使用 `https://<account>.cache.tuist.dev`。對於自託管的 Tuist 服務器，CLI 會從服務器的 `TUIST_CACHE_ENDPOINTS` 設置中檢索快取 URL。將其設置為你的主快取服務器或負載均衡器的 URL。如果包含多個 URL，則使用第一個。

對於連接到 **託管 Tuist 服務器** 的私有/自定義快取節點，請在開發者 shell 和 CI 中設置明確的端點：

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

此覆蓋在兩種服務器類型上均優先，並且對於自託管 Tuist 服務器是可選的。對於 Xcode 快取守護進程，請在設置後重新運行 `tuist setup cache`，以便 LaunchAgent 接收更新後的環境。

自託管 Tuist 服務器從靜態配置中獲取端點。在 Tuist 託管的服務器上，節點使用憑證進行身份驗證並註冊自己。首先使用以下兩個部分之一部署節點，然後參閱 [將節點連接到 Tuist](#connect-nodes-to-tuist)。

## 在 Kubernetes 上部署 {#deploy-on-kubernetes}

Kura 通過 GitHub Container Registry 以 Helm chart 的形式分發。它將 Kura 部署為帶有持久卷的 `StatefulSet`、用於對等發現的無頭服務，以及用於 HTTP 和 gRPC 流量的常規服務。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

對於同一集群中的自託管 Tuist 服務器，配置其主快取端點：

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

這將在服務器 Pod 中設置 `TUIST_CACHE_ENDPOINTS`。使用開發者機器和 CI 可以訪問的地址；上述集群本地服務名稱適合在集群內運行的客戶端。

> [!IMPORTANT]
> 每個 Kura 節點必須擁有自己的 `KURA_DATA_DIR`。Kura 會對數據目錄採取應用級別的寫入鎖，並期望只有一個進程擁有它。在 Kubernetes 中，每個 Pod 使用一個持久卷。在 Kubernetes 之外，不要讓多個進程指向同一個掛載目錄。

## 不使用 Kubernetes 部署 {#deploy-without-kubernetes}

Kura 也可以作為常規容器在虛擬機或裸金屬主機上運行。在這種模式下，你負責進程監督、持久存儲、路由和對等發現。

至少，每個節點都需要一個持久數據目錄、一個臨時目錄、一個公共快取端口（一個監聽器同時服務 HTTP 快取 API 和 REAPI gRPC）、一個內部對等 URL，以及靜態對等列表或發現機制：

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

在自託管 Tuist 服務器上，配置開發者機器和 CI 可以訪問的主快取 URL：

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## 將節點置於負載均衡器後面 {#load-balancers}

客戶端對每個快取端點 URL 同時使用 HTTP 和 gRPC：HTTP 用於健康檢查和 HTTP 快取 API，gRPC 用於模塊快取和 Bazel 的遠程快取。客戶端和 Kura 之間的任何入口、負載均衡器或 CDN 必須在同一主機名和端口上轉發兩者。這適用於客戶端收到的每個端點，因為 CLI 會選擇響應最快的那個。如果 gRPC 無法到達 Kura，CLI 會警告遠程模塊快取不可用，並僅使用本地模塊快取。

將這些路徑前綴作為 HTTP/2 上的 gRPC 路由到 Kura，其他所有內容作為 HTTP：

| 路徑前綴 | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | 模塊快取，Bazel |
| `/google.bytestream.` | 模塊快取，Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel 構建事件 |

Kura 在 `KURA_PORT` 上接受明文 HTTP/2 (h2c)，並在設置了 `KURA_PUBLIC_TLS_CERT_PATH` 和 `KURA_PUBLIC_TLS_KEY_PATH` 時在 `KURA_HTTPS_PORT` 上接受基於 TLS 的 HTTP/2。如果你的代理像 ingress-nginx 那樣在請求間重用上游連接，請設置 `KURA_GATEWAY_GRPC_PORT` 並將 gRPC 流量發送到該端口。它僅服務 gRPC，因此 HTTP/1.1 和 gRPC 請求永遠不會共享連接。

使用以下配置 gRPC 路由：

- 無請求體大小限制。上傳在單個請求中發送一個文件，最多 2 GiB。
- 關閉請求和響應緩衝。
- 讀取、發送和空閒超時至少為 300 秒。

Kura 不提供 gRPC 健康檢查服務。通過 HTTP 在 `/ready` 對節點進行健康檢查。如果你的負載均衡器需要 gRPC 健康檢查，請調用 `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` 並接受 gRPC 狀態碼 `0` 和 `16`。啟用了授權的節點會以 `16` (`UNAUTHENTICATED`) 回應沒有令牌的請求。

### ingress-nginx {#load-balancers-ingress-nginx}

使用 Helm chart 時，將 HTTP 入口保持在 `/` 並為同一主機添加 gRPC 入口。只有 HTTP 入口聲明 TLS：

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

gRPC 目標組需要 HTTPS 監聽器。在該監聽器上：

1. 將默認規則轉發到協議版本為 `HTTP1` 且位於 `KURA_PORT` 的目標組，並通過 HTTP 在 `/ready` 進行健康檢查。
2. 創建第二個目標組，協議版本為 `gRPC`，在 `KURA_GATEWAY_GRPC_PORT`（或 `KURA_PORT`）上使用協議 `HTTP`，或在 `KURA_HTTPS_PORT` 上使用協議 `HTTPS`。按上述描述配置其健康檢查。
3. 添加一條規則，將路徑模式 `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*` 和 `/google.devtools.build.v1.*` 轉發到第二個目標組。
4. 將負載均衡器的空閒超時提高到至少 300 秒。

### CDN {#load-balancers-cdns}

位於節點前方的 CDN 必須支援 gRPC，且不得在其防火牆規則中封鎖 gRPC 路徑。客戶端以最多 2 MiB 的區塊上傳大型構件，並由節點組裝它們，因此沒有請求需要大型請求體或長時間上傳。模塊快取和 Xcode 編譯快取會這樣做，而 Bazel 在使用 `--experimental_remote_cache_chunking` 構建時也會這樣做（Bazel 8.7 及 9.1 或更高版本）。如果沒有該標誌，Bazel 會在單個請求中上傳每個輸出，因此 CDN 還必須允許大型請求體，以及在上傳時間取決於你最慢鏈路上最大輸出所需的時間。如果你的 CDN 無法滿足這些要求，請為客戶端提供一個繞過它的主機名，例如僅 DNS 記錄。

#### Cloudflare {#load-balancers-cloudflare}

在任何計劃上，模塊快取都可以通過代理的 Cloudflare 主機名運作。在區域中：

1. 在 **Network** 下，開啟 **gRPC**。
2. 在 **SSL/TLS** 下，將加密模式設置為 **Full** 或 **Full (strict)**。Cloudflare 通過端口 443 連接到源站，因此源站必須在該端口提供 TLS 並通過 ALPN 提供 HTTP/2。
3. 確保沒有 WAF 自定義規則或託管規則封鎖上述 gRPC 路徑。

如果源站在大約兩分鐘後仍未開始響應，Cloudflare 會終止請求。沒有 `--experimental_remote_cache_chunking` 的 Bazel 上傳只有在最後一個字節到達時才會得到響應，因此在 Cloudflare 上，如果上傳時間超過該時間，則會失敗。

## 將節點連接到 Tuist {#connect-nodes-to-tuist}

配置客戶端路由並在 Tuist 註冊你的節點，以便它們的地址、就緒狀態和使用情況顯示在儀表板中。

在 **自託管 Tuist 伺服器** 上，你使用 `TUIST_CACHE_ENDPOINTS` 靜態聲明端點，如上文的部署部分所示。CLI 使用第一個配置的 URL。`TUIST_CACHE_ENDPOINT` 會為單個客戶端覆蓋該 URL。

在 **Tuist 託管伺服器** 上，在開發者 shell 和 CI 中設置 `TUIST_CACHE_ENDPOINT`，以將快取請求路由到你的節點。每個節點使用你生成的憑證進行身份驗證，然後註冊其地址並向儀表板報告其就緒狀態。本節介紹節點註冊。

> [!IMPORTANT]
> **Enterprise 計劃**
>
> 自託管快取節點可在 Enterprise 計劃上使用。下文描述的 **Self-hosted servers** 部分僅適用於該計劃的帳戶。

### 生成節點憑證 {#generate-a-node-credential}

在 Tuist 儀表板中，打開你的帳戶，轉到 **Cache**，並找到 **Self-hosted servers**。選擇 **Generate credential** 以鑄造客戶端 ID 和密鑰。

該憑證僅授權創建它的帳戶的流量。

密鑰僅顯示一次，關閉對話框後無法恢復，因此請將其直接複製到節點讀取的密鑰存儲中。撤銷憑證會立即停止所有使用該憑證的節點進行身份驗證，因此在撤銷正在使用的憑證之前，請先生成替換憑證。

### 在啟動時註冊節點 {#enroll-the-node-on-boot}

註冊是啟動節點的推薦方式。設置 `KURA_ENROLL_ON_BOOT` 並為節點提供其憑證及其自身的對等 URL：

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

節點在本地生成其密鑰對，因此私鑰永遠不會離開節點，並且它會收到簽名的對等證書、帳戶 CA、其租戶標識符和對等列表。這就是你否則需要手動配置的所有內容：已註冊的節點不需要 `KURA_TENANT_ID`、不需要 `KURA_PEERS`，也不需要對等 TLS 設置。

保持 `KURA_INTERNAL_TLS_*` 未設置：註冊會將證書材料寫入 `KURA_DATA_DIR` 下的 `tls` 目錄。僅當你自行提供證書而不是進行註冊時，才自行設置這些路徑，如 [Build a cache mesh](#build-a-cache-mesh) 中所述。

首次加入帳戶網格的節點在成為環的服務成員之前，會拉取帳戶的現有快取。為整個快取調整數據卷的大小，並預期首次加入在廣域鏈路上需要一段時間。節點報告 `joining` 直到它趕上進度，然後報告 `serving`。

### 宣傳端點 {#advertise-the-endpoint}

註冊加入網格。註冊向 Tuist 報告節點的客戶端 facing 地址和就緒狀態。設置註冊變量：

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

節點每 60 秒針對 180 秒的租約發送一次心跳。當租約過期時，Tuist 認為其註冊不可用。Tuist 從不調用節點，因此它只需要可由你的客戶端訪問，而不需要從互聯網訪問。

### 驗證節點正在服務 {#verify-the-node-is-serving}

回到儀表板中的 **Cache**，節點出現在 **Registered nodes** 下，顯示其端點、區域、狀態和最後一次心跳。從未出現的節點無法到達註冊端點或授權失敗。出現後又消失的節點已停止發送心跳或停止報告其就緒狀態。

### 將租戶標識符與你的帳戶句柄匹配 {#match-the-tenant-identifier}

`KURA_TENANT_ID` 必須等於你的 Tuist 帳戶句柄。控制平面將心跳的租戶與從憑證解析的帳戶進行比較，並以 `409 tenant_mismatch` 拒絕不匹配的情況，因此具有錯誤值的節點雖然成功通過身份驗證，但永遠不會註冊。

> [!IMPORTANT]
> 本指南前面的 Helm chart 和容器示例都將此默認為 `default`。該值對於自託管 Tuist 伺服器（其中租戶是本地標籤）是正確的，但對於 Tuist 託管伺服器上的帳戶（其中它必須命名帳戶）是錯誤的。註冊節點完全避免了這個問題，因為控制平面提供了該值。

未設置的 `KURA_TENANT_ID` 不會跳過檢查。它會完全禁用註冊：節點繼續服務快取流量，儀表板中沒有任何顯示，也沒有報告錯誤。如果節點健康但缺失於 **Registered nodes**，請首先檢查此變量。

### 選擇你的客戶端可以訪問的宣傳 URL {#choose-an-advertised-url}

為 `KURA_ADVERTISED_HTTP_URL` 和在 Tuist 伺服器或 CLI 上配置的快取 URL 使用客戶端可訪問的地址。

當每個配置為使用它的客戶端都能解析並訪問該名稱時，僅內部主機名是合適的。對於不同網絡上的客戶端，使用共享的可訪問地址或為每個環境配置可訪問的快取節點。

## 構建快取網格 {#build-a-cache-mesh}

快取網格讓你可以將快取容量放置在需要它的運算資源旁邊。公司可以在主要 CI 執行器附近運行一個節點，在歐洲開發者附近運行另一個節點，並在美國辦公室或區域構建集群附近運行第三個節點。每個位置都讀寫最近的節點，而 Kura 會在後台複製構件和元數據，以便其他位置的後續構建可以重用相同的輸出。

只有當節點可以通過 Kura 的內部對等端口相互訪問時，網格才能正常工作。該對等平面與 Tuist 客戶端使用的公共快取端點是分開的。Kura 使用它來檢查成員資格、回填新加入的節點，並在接受本地寫入後複製構件。

我們強烈建議在節點跨區域、雲、VPC、辦公室或任何不完全私有於快取部署的網絡進行通信時，使用 [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) 保護對等平面。啟用 mTLS 後，Kura 僅向提供由配置的 CA 簽名的證書的對等方提供內部複製端點。對等證書必須涵蓋節點用於相互調用的 DNS 名稱，並且對等 URL 必須在內部端口上使用 `https://`。

> [!NOTE]
> 向 Tuist 託管的控制平面註冊的節點會在註冊期間接收其對等證書和帳戶 CA，因此以下手動步驟適用於未註冊的網格。

例如，這會生成一個私有 CA 和一個對等證書，可以由小型網格中的每個節點掛載。將 DNS 名稱替換為你的節點在 `KURA_NODE_URL` 和 `KURA_PEERS` 中使用的內部名稱。

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

### 節點之間的同步 {#catch-up-between-nodes}

加入或重新加入網格的節點會執行 **backfills**：它按最新優先順序遍歷每個對等方的條目並拉取缺失的內容，而實時複製則覆蓋對等方可見時進行的寫入。回填過程從對等方的最新條目回溯到節點的段環視野和其上次完成的重複過程中較舊的一個，因此保證節點持有最近的数据，但不一定是所有数据。`KURA_BACKFILL_MARGIN_PERCENT` 設置視野回溯的深度。

在運行網格之前，有兩個後果值得了解：

- 一旦節點的段環達到 `KURA_BACKFILL_READY_RING_PERCENT` 滿 **或** 其第一個回填週期穩定，節點就會報告 `/ready`，並且就緒狀態將在進程剩餘的生命週期內保持。後續的對等方波動永遠不會將服務中的節點移出輪詢。
- 當對等方長時間無法訪問時，週期也會穩定。因此，唯一對等方下線的節點會在持有少量或沒有數據的情況下變為 Ready。它服務的是未命中而不是錯誤。如果你希望根據差異來控制發布，`/status/rollout` 會報告 `backfill_initial_cycle`（`pending`、`complete` 或 `degraded`）。

**在回填變更期間升級網格。** 回填之前的 Kura 版本通過不同的、現已移除的對等協議進行同步。在你採用僅支持回填的版本**之前**，請將每個節點滾動升級到運行回填的版本。使用這兩種協議的節點無法相互同步：一個熱節點會繼續從其卷提供服務，但停止縮小其差距，而在該窗口期間從空卷啟動的節點永遠不會變為 Ready。Chart 為你設置了 `KURA_BACKFILL_ENABLED=true`，因此優先升級 Chart 可以解決此問題。單個 `helm upgrade` 同時移動 Chart 和鏡像則不行。

除了 mTLS 之外，還應使用網絡級別的限制。在 Kubernetes 中，將 Kura 作為 `StatefulSet` 運行，每個 Pod 配備一個持久卷，並使用無頭服務進行對等發現，然後僅允許屬於同一快取部署的 Pod 之間訪問內部對等端口，例如使用 `NetworkPolicy`。在 Kubernetes 之外，為每個節點分配穩定的 DNS 名稱或 IP 地址，使用其他節點的內部 URL 種子化網格，並使用防火牆規則或安全組，以便只有快取節點可以訪問對等端口。公共快取流量應通過公共 HTTP 或 gRPC 端點進入，而不是通過內部對等平面。

## 配置 {#configuration}

Helm chart 從 `values.yaml` 渲染常見的運行時設置。如果你在沒有 Kubernetes 的情況下運行 Kura，請直接在進程上設置相同的變量。Chart 未直接映射的變量可以通過 `extraEnv` 或 `extraEnvFrom` 注入。

| 環境變量 | 描述 | 必填 | 默認值 | Helm 值 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 公共快取端口。一個監聽器提供 HTTP 快取 API、健康端點和 Bazel/Buck2 REAPI gRPC (h2c)。 | 是 | 無默認值 | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura 對等方使用的內部 HTTP 或 mTLS 端口。 | 是 | 無默認值 | `peerTls.internalPort` |
| `KURA_TENANT_ID` | 節點的默認租戶標識符。 | 是 | 無默認值 | `config.tenantId` |
| `KURA_REGION` | 用於指標和複製狀態的區域標籤。 | 是 | 無默認值 | `config.region` |
| `KURA_TMP_DIR` | 用於暫存請求正文和多部分組裝的臨時目錄。 | 是 | 無默認值 | 固定為 `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | 在請求收到背壓之前，允許進入 `KURA_TMP_DIR` 的最大暫存字節數。 | 否 | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | 用於元數據狀態和段文件的持久目錄。 | 是 | 無默認值 | 固定為 `/var/cache/kura` |
| `KURA_NODE_URL` | 其他對等方用來連接此節點的標準內部 URL。 | 是 | 無默認值 | 衍生自 Pod DNS 名稱和 `peerTls.internalPort` |
| `KURA_PEERS` | 在發現收斂之前使用的種子對等方列表。 | 否 | `KURA_NODE_URL` | 衍生自 StatefulSet 副本 |
| `KURA_DISCOVERY_DNS_NAME` | 用於自動對等發現的 DNS 名稱。 | 否 | 已停用 | 由 `config.discovery.enabled` 啟用 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | 用於驗證對等方 mTLS 的 CA 證書。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 和 `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 內部對等方 mTLS 監聽器使用的證書。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 和 `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 內部對等方 mTLS 監聽器使用的私鑰。 | 否 | 已停用，或在節點註冊時於 `KURA_DATA_DIR` 下衍生 | `peerTls.enabled` 和 `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 用於在託管的 HTTPS 監聽器（`KURA_HTTPS_PORT`）上終止 TLS 的證書。 | 否 | 已停用 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | 與 `KURA_PUBLIC_TLS_CERT_PATH` 配對的私鑰。 | 否 | 已停用 | `extraEnv` |
| `KURA_HTTPS_PORT` | 提供相同託管 HTTP + gRPC 介面（ALPN 協商）的 TLS 端口。僅在設置公共 TLS 路徑時綁定。 | 否 | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 純文本 HTTP/2 端口，僅提供 gRPC API，適用於重用上游連接的代理。請參閱 [將節點置於負載平衡器後面](#load-balancers)。 | 否 | 已停用 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | 用於請求和後台 I/O 的文件描述符預算。 | 否 | 自動衍生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | 請求在 FD 背壓導致檢出失敗之前等待的時間。 | 否 | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | 最大固定段讀取句柄數。 | 否 | 自動衍生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | 關閉期間處理進行中 HTTP 和 gRPC 工作的寬限期。 | 否 | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura 開始減少可選記憶體使用的軟性記憶體水位。 | 否 | 自動衍生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura 暫停複製並清理熱門快取的硬性記憶體水位。 | 否 | 自動衍生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | 記憶體中清單快取的最大大小。 | 否 | 自動衍生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | 每個請求的鍵值負載最大大小。 | 否 | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | 為元數據存儲保留的文件描述符預算。 | 否 | 自動衍生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | 元數據存儲的後台刷新和壓縮併發度。 | 否 | 自動衍生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | 元數據存儲讀取快取的容量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | 為元數據寫入緩衝保留的總記憶體預算。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | 每次刷新前每個元數據寫入緩衝區的大小。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | 記憶體中保留的元數據寫入緩衝區最大數量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 進行中的多部分上傳在過期前可以停留的時間。 | 否 | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura 掃描過時多部分上傳的頻率。 | 否 | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 按年齡排序的段環中從最新開始計算的比例，用於限制回填操作向後追溯的範圍。 | 否 | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 節點仍在執行首個回填週期時，段環達到此滿載度即回報為就緒。 | 否 | `KURA_BACKFILL_MARGIN_PERCENT` 的一半 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 組成單一批次回填主體的位元組閾值，以及超過此大小的項目會單獨抓取。 | 否 | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio 工作執行緒數量。 | 否 | 自動衍生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP 追蹤端點。留空以停用追蹤。 | 否 | 已停用 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry 服務名稱。 | 是 | 無預設值 | Helm 中的 Pod 名稱 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry 部署環境。 | 是 | 無預設值 | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | 用於恐慌和錯誤報告的 Sentry DSN。 | 否 | 已停用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | 節點所在資料中心的 ISO 3166-1 alpha-2 國家代碼，會作為 `geo.country.iso_code` 標記在匯出的追蹤記錄上。 | 否 | 當 `KURA_REGION` 的前綴為國家代碼時由此衍生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | 該資料中心的 ISO 3166-2 行政區劃（例如 `US-CA`），標記為 `geo.region.iso_code`。 | 否 | 未設定 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 要求呼叫者提供有效的 Tuist 令牌。設定 `KURA_AUTH_TUIST_URL` 即可啟用授權，而將此設為 `false` 不會關閉授權 — 請取消設定 URL 以在無授權的情況下運行節點。 | 否 | 已停用 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | 節點進行授權對接的 Tuist 伺服器。可獨立啟用授權。 | 啟用授權時必填 | 無預設值 | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | 連線至該伺服器的逾時時間。 | 否 | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | 向該伺服器發出請求的逾時時間。 | 否 | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | 節點可自行讀取令牌的共享密鑰，省去往返驗證。它既能簽署也能驗證，因此僅在節點與伺服器處於同一信任邊界時使用。自託管節點通常不設定此項。 | 否 | 已停用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | 伺服器簽署快取令牌所用金鑰對的公鑰部分，以一個或多個串連的 PEM 區塊表示。可讀取這些令牌但無法簽發新令牌，這正是可從網際網路存取的節點應持有的設定。與 `KURA_AUTH_JWT_SECRET` 互斥。 | 否 | 已停用 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | 該金鑰的演算法：使用密鑰時為 `HS256`、`HS384` 或 `HS512`；使用公鑰時為 `ES256`。 | 否 | 使用密鑰時為 `HS256`，使用公鑰時為 `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | 令牌必須包含的發行者。 | 否 | 不檢查 | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | 令牌必須包含的受眾，以逗號分隔。 | 否 | 不檢查 | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 身份驗證和授權快取中各自保留的最大項目數。 | 否 | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 每次啟動時將節點註冊至控制平面，配置其對等證書並提供 `KURA_TENANT_ID` 和 `KURA_PEERS`。 | 否 | 已停用 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | 節點進行註冊對接的 Tuist 伺服器。 | 註冊時必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | 在儀表板中產生的節點憑證的客戶端 ID。 | 註冊或登記時必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | 與 `KURA_CONTROL_PLANE_CLIENT_ID` 配對的客戶端密鑰。 | 註冊或登記時必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_URL` | 節點發送註冊心跳的絕對 URL，用於宣傳其面向客戶的端點。 | 登記時必填 | 無預設值 | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | 控制平面提供給客戶的面向客戶的快取 URL。帳戶中的每個客戶都必須能夠存取此 URL。 | 登記時必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 註冊心跳頻率。租約寬限涵蓋多次錯過的心跳，因此單次心跳丟失不會導致端點失效。 | 否 | `60000` | `extraEnv` |

如果啟用內部對等 mTLS，請同時設定 `KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH` 和 `KURA_INTERNAL_TLS_KEY_PATH`。`KURA_NODE_URL` 和 `KURA_PEERS` 中的每個值都必須使用 `https://` 搭配內部對等端口。
