---
{
  "title": "自託管快取",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "部署自託管快取節點，並將其連接至 Tuist。"
}
---

# 自行託管快取 {#self-hosted-cache}

自行託管快取節點讓你將建構產物同快取元數據放喺產生同消耗建構輸出嘅機器附近。當 CI、開發者辦公室、遠程工作站或區域計算集群之間嘅快取延遲好重要時，就使用佢哋。

目標係喺所有地方實現低延遲快取，而唔係只係喺中央快取剛好喺附近嗰個環境。每個快取節點都從本地磁盤提供讀寫服務，而網格會喺對等節點之間複製產物同元數據，令其他位置隨時間推移都能受惠於同一個快取。

> [!NOTE]
> Tuist 嘅自行託管快取節點由 [Kura](https://github.com/tuist/tuist/tree/main/kura) 提供支持，Kura 係 Tuist 嘅去中心化快取網格。Kura 係快取節點嘅數據平面：佢提供快取讀寫服務，將本地狀態儲存喺磁盤上，並將產物同元數據複製到對等節點。

## 自行託管快取點樣配合 Tuist {#how-self-hosted-cache-fits-with-tuist}

Tuist 嘅受管快取使用 `https://<account>.cache.tuist.dev`。對於自行託管嘅 Tuist 伺服器，CLI 會從伺服器嘅 `TUIST_CACHE_ENDPOINTS` 設定中檢索快取 URL。將其設定為你主要快取伺服器或負載均衡器嘅 URL。如果包含多個 URL，則使用第一個。

對於連接到 **託管 Tuist 伺服器** 嘅私人/自定義快取節點，請喺開發者 shell 同 CI 中設定明確嘅端點：

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

此覆蓋喺兩種伺服器類型上都優先生效，並且對於自行託管嘅 Tuist 伺服器係可選嘅。對於 Xcode 快取守護進程，設定之後請重新運行 `tuist setup cache`，以便 LaunchAgent 接收更新後嘅環境變量。

自行託管嘅 Tuist 伺服器從靜態配置中獲取端點。喺 Tuist 託管嘅伺服器上，節點使用憑證進行身份驗證並註冊自己。首先使用下面兩個部分之一部署節點，然後參閱 [將節點連接到 Tuist](#connect-nodes-to-tuist)。

## 喺 Kubernetes 上部署 {#deploy-on-kubernetes}

Kura 通過 GitHub Container Registry 以 Helm chart 形式分發。它將 Kura 部署為 `StatefulSet`，帶有持久卷、用於對等發現嘅無頭服務，以及用於 HTTP 同 gRPC 流量嘅常規服務。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

對於同一集群中嘅自行託管 Tuist 伺服器，配置其主要快取端點：

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

這會喺伺服器 Pod 中設定 `TUIST_CACHE_ENDPOINTS`。使用開發者機器同 CI 可以訪問嘅地址；上面嘅集群本地服務名稱適合喺集群內部運行嘅客戶端。

> [!IMPORTANT]
> 每個 Kura 節點必須擁有自己嘅 `KURA_DATA_DIR`。Kura 會對數據目錄採取應用級別嘅寫入鎖，並期望只有一個進程擁有它。喺 Kubernetes 中，每個 Pod 使用一個持久卷。喺 Kubernetes 之外，唔好讓多個進程指向同一個掛載目錄。

## 無需 Kubernetes 部署 {#deploy-without-kubernetes}

Kura 亦可以作為常規容器喺 VM 或裸機主機上運行。喺呢種模式下，你需要負責進程監督、持久存儲、路由同對等發現。

最少情況下，每個節點都需要一個持久數據目錄、一個臨時目錄、一個公共快取端口（一個監聽器同時服務 HTTP 快取 API 同 REAPI gRPC）、一個內部對等 URL，以及靜態對等列表或發現機制之一：

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

喺自行託管嘅 Tuist 伺服器上，配置開發者機器同 CI 可以訪問嘅主要快取 URL：

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## 將節點置於負載均衡器後面 {#load-balancers}

客戶端對每個快取端點 URL 都同時使用 HTTP 同 gRPC：HTTP 用於健康檢查同 HTTP 快取 API，gRPC 用於模塊快取同 Bazel 嘅遠程快取。客戶端同 Kura 之間嘅任何入口、負載均衡器或 CDN 都必須喺同一主機名同端口上轉發兩者。這適用於客戶端收到嘅每個端點，因為 CLI 會選擇響應最快嘅那個。如果 gRPC 無法到達 Kura，CLI 會警告遠程模塊快取不可用，並只使用本地模塊快取。

將呢啲路徑前綴作為通過 HTTP/2 嘅 gRPC 路由到 Kura，其他所有內容作為 HTTP：

| 路徑前綴 | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | 模塊快取，Bazel |
| `/google.bytestream.` | 模塊快取，Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel 建構事件 |

Kura 喺 `KURA_PORT` 上接受明文 HTTP/2 (h2c)，並且當設定咗 `KURA_PUBLIC_TLS_CERT_PATH` 同 `KURA_PUBLIC_TLS_KEY_PATH` 時，喺 `KURA_HTTPS_PORT` 上接受通過 TLS 嘅 HTTP/2。如果你嘅代理像 ingress-nginx 那樣跨請求重用上游連接，請設定 `KURA_GATEWAY_GRPC_PORT` 並將 gRPC 流量發送到該端口。它只提供 gRPC 服務，所以 HTTP/1.1 同 gRPC 請求永遠唔會共享連接。

使用以下配置 gRPC 路由：

- 無請求主體大小限制。一次上傳喺單個請求中發送一個文件，最多 2 GiB。
- 關閉請求同響應緩衝。
- 讀取、發送同空閒超時時間至少為 300 秒。

Kura 不提供 gRPC 健康檢查服務。通過 HTTP 喺 `/ready` 對節點進行健康檢查。如果你嘅負載均衡器需要 gRPC 健康檢查，請調用 `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` 並接受 gRPC 狀態碼 `0` 同 `16`。啟用了授權嘅節點會用 `16` (`UNAUTHENTICATED`) 回應無令牌嘅請求。

### ingress-nginx {#load-balancers-ingress-nginx}

使用 Helm chart 時，將 HTTP 入口保持喺 `/`，並為同一主機添加 gRPC 入口。只有 HTTP 入口聲明 TLS：

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

gRPC 目標組需要 HTTPS 監聽器。喺該監聽器上：

1. 將默認規則轉發到協議版本為 `HTTP1` 並位於 `KURA_PORT` 嘅目標組，通過 HTTP 喺 `/ready` 進行健康檢查。
2. 創建第二個目標組，協議版本為 `gRPC`，喺 `KURA_GATEWAY_GRPC_PORT`（或 `KURA_PORT`）上使用協議 `HTTP`，或者喺 `KURA_HTTPS_PORT` 上使用協議 `HTTPS`。按照上述描述配置其健康檢查。
3. 添加一條規則，將路徑模式 `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*` 同 `/google.devtools.build.v1.*` 轉發到第二個目標組。
4. 將負載均衡器嘅空閒超時時間提高至至少 300 秒。

### CDN {#load-balancers-cdns}

位於節點前面嘅 CDN 必須支援 gRPC，並且唔得喺其防火牆規則中阻止 gRPC 路徑。客戶端以最多 2 MiB 嘅分塊上傳大型構件，並由節點將佢哋組合，所以無請求需要大主體或長時間上傳。模塊快取同 Xcode 編譯快取都係咁做，而 Bazel 喺使用 `--experimental_remote_cache_chunking` 建構時亦會咁做（Bazel 8.7 及 9.1 或更高版本）。如果無該標誌，Bazel 會喺單個請求中上傳每個輸出，所以 CDN 亦必須允許大請求主體，以及喺你最慢鏈路上完成最大輸出所需嘅長時間上傳。如果你嘅 CDN 無法滿足呢啲要求，請提供一個可以繞過它嘅主機名畀客戶端，例如僅 DNS 記錄。

#### Cloudflare {#load-balancers-cloudflare}

模塊快取可以通過任何計劃上嘅代理 Cloudflare 主機名運作。喺區域中：

1. 喺 **網絡** 下，開啟 **gRPC**。
2. 喺 **SSL/TLS** 下，將加密模式設定為 **完整** 或 **完整（嚴格）**。Cloudflare 通過端口 443 連接到源站，所以源站必須喺該處提供 TLS 並通過 ALPN 提供 HTTP/2。
3. 確保無 WAF 自定義規則或託管規則阻止上述列出嘅 gRPC 路徑。

如果源站喺大約兩分鐘後仍未開始響應，Cloudflare 會終止請求。無 `--experimental_remote_cache_chunking` 嘅 Bazel 上傳只有喺最後一個字節到達時才會得到響應，所以喺 Cloudflare 上，如果上傳時間超過該時間就會失敗。

## 將節點連接到 Tuist {#connect-nodes-to-tuist}

配置客戶端路由並將你嘅節點註冊到 Tuist，以便它們嘅地址、就緒狀態和使用情況顯示喺儀表板中。

喺 **自託管 Tuist 伺服器** 上，你使用 `TUIST_CACHE_ENDPOINTS` 靜態聲明端點，如上面部署部分所示。CLI 使用第一個配置嘅 URL。`TUIST_CACHE_ENDPOINT` 會覆蓋單個客戶端嘅該 URL。

喺 **Tuist 託管伺服器** 上，喺開發人員 shell 和 CI 中設定 `TUIST_CACHE_ENDPOINT`，以將快取請求路由到你嘅節點。每個節點使用你生成嘅憑證進行身份驗證，然後註冊其地址並向儀表板報告其就緒狀態。本節介紹節點註冊。

> [!IMPORTANT]
> **企業計劃**
>
> 自託管快取節點喺企業計劃中可用。下面描述嘅 **自託管伺服器** 部分只對該計劃上嘅帳戶顯示。

### 生成節點憑證 {#generate-a-node-credential}

喺 Tuist 儀表板中，打開你嘅帳戶，前往 **快取**，並找到 **自託管伺服器**。選擇 **生成憑證** 以鑄造客戶端 ID 和密鑰。

該憑證只授權創建它嘅帳戶嘅流量。

密鑰只顯示一次，關閉對話框後無法恢復，所以請直接將其複製到節點讀取嘅密鑰存儲中。撤銷憑證會立即停止所有使用它嘅節點進行身份驗證，所以喺撤銷正在使用中嘅憑證之前，請先生成替換憑證。

### 喺啟動時註冊節點 {#enroll-the-node-on-boot}

註冊係推薦嘅節點啟動方式。設定 `KURA_ENROLL_ON_BOOT` 並給予節點其憑證及其自身嘅對等 URL：

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

節點喺本地生成其密鑰對，所以私鑰永遠唔會離開節點，並接收簽名嘅對等證書、帳戶 CA、其租戶標識符和對等列表。這就係你否則需要手動配置嘅所有內容：已註冊嘅節點無需 `KURA_TENANT_ID`、無需 `KURA_PEERS`，也無需對等 TLS 設置。

保持 `KURA_INTERNAL_TLS_*` 未設定：註冊會將證書材料寫入 `KURA_DATA_DIR` 下嘅 `tls` 目錄。只有當你自行提供證書而不是進行註冊時，才自行設定這些路徑，如 [構建快取網格](#build-a-cache-mesh) 中所述。

首次加入帳戶網格嘅節點喺成為環中服務成員之前，會拉取帳戶現有嘅快取。為整個快取調整數據卷大小，並預期首次加入喺廣域鏈路上需要一段時間。節點會報告 `joining` 直到趕上進度，然後報告 `serving`。

### 通告端點 {#advertise-the-endpoint}

註冊會加入網格。註冊會向 Tuist 報告節點面向客戶端嘅地址和就緒狀態。設定註冊變量：

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

節點每 60 秒針對 180 秒嘅租約發送一次心跳。當租約過期時，Tuist 會認為其註冊不可用。Tuist 永遠唔會調用節點，所以它只需要被你嘅客戶端訪問到，而無需從互聯網訪問。

### 驗證節點是否正在服務 {#verify-the-node-is-serving}

返回儀表板中嘅 **快取**，節點會顯示喺 **已註冊節點** 下，包含其端點、區域、狀態和最後一次心跳。從未出現嘅節點表示無法到達註冊端點或授權失敗。出現後又消失嘅節點表示已停止發送心跳或停止報告自身就緒。

### 將租戶標識符匹配到你嘅帳戶句柄 {#match-the-tenant-identifier}

`KURA_TENANT_ID` 必須等於你嘅 Tuist 帳戶句柄。控制平面將心跳中嘅租戶與從憑證解析出嘅帳戶進行比較，並用 `409 tenant_mismatch` 拒絕不匹配，所以具有錯誤值嘅節點雖然能成功通過身份驗證，但永遠唔會註冊。

> [!IMPORTANT]
> 本指南前面嘅 Helm chart 和容器示例都將此默認為 `default`。該值對於自託管 Tuist 伺服器（其中租戶係本地標籤）係正確嘅，但對於 Tuist 託管伺服器上嘅帳戶（其中必須命名帳戶）係錯誤嘅。註冊節點可以完全避免這個問題，因為控制平面會提供該值。

未設定嘅 `KURA_TENANT_ID` 唔會跳過檢查。它會完全禁用註冊：節點繼續服務快取流量，儀表板中無任何內容顯示，也無錯誤報告。如果節點健康但喺 **已註冊節點** 中缺失，請首先檢查此變量。

### 選擇你嘅客戶端可以訪問嘅通告 URL {#choose-an-advertised-url}

為 `KURA_ADVERTISED_HTTP_URL` 和喺 Tuist 伺服器或 CLI 上配置嘅快取 URL 使用客戶端可訪問嘅地址。

當每個配置為使用內部主機名嘅客戶端都能解析並訪問該名稱時，僅內部主機名係合適嘅。對於位於不同網絡上嘅客戶端，請使用共享可訪問地址或為每個環境配置可訪問嘅快取節點。

## 構建快取網格 {#build-a-cache-mesh}

快取網格讓你可以將快取容量放置喺需要它嘅運算資源旁邊。一間公司可能會喺其主要 CI 執行器附近運行一個節點，另一個靠近歐洲嘅開發人員，再有一個靠近美國辦公室或區域構建集群。每個位置都讀寫最近嘅節點，而 Kura 會喺後台複製構件和元數據，以便其他位置後續嘅構建可以重用相同嘅輸出。

只有當節點可以通過 Kura 嘅內部對等端口互相訪問時，網格才能正常工作。該對等平面與 Tuist 客戶端使用嘅公共快取端點係分開嘅。Kura 使用它來檢查成員資格、回填新加入嘅節點，並喺接受本地寫入後複製構件。

我哋強烈建議當節點跨區域、雲、VPC、辦公室或任何唔完全私有於快取部署嘅網絡進行通信時，使用 [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) 保護對等平面。啟用 mTLS 後，Kura 只會向出示由配置嘅 CA 簽署證書嘅對等節點提供內部複製端點。對等證書必須涵蓋節點用於互相調用嘅 DNS 名稱，並且對等 URL 必須喺內部端口上使用 `https://`。

> [!NOTE]
> 向 Tuist 託管控制平面註冊嘅節點會喺註冊期間收到其對等證書和帳戶 CA，因此下面嘅手動步驟適用於未註冊嘅網格。

例如，這會生成一個私有 CA 和一個對等證書，可以由小型網格中嘅每個節點掛載。將 DNS 名稱替換為你嘅節點喺 `KURA_NODE_URL` 和 `KURA_PEERS` 中使用嘅內部名稱。

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

### 節點之間嘅同步 {#catch-up-between-nodes}

加入或重新加入網格嘅節點會**回填**：它按最新優先順序遍歷每個對等節點嘅條目並拉取缺失嘅內容，而實時複製則覆蓋對等節點可見期間產生嘅寫入。一次回填過程會從對等節點最新嘅條目回溯到節點段環視界和其最後一次完成迴圈中較舊嘅那個，因此保證節點持有最近嘅數據，但不一定係全部。`KURA_BACKFILL_MARGIN_PERCENT` 設定視界回溯嘅深度。

喺運行網格之前，有兩個後果值得了解：

- 一旦節點嘅段環達到 `KURA_BACKFILL_READY_RING_PERCENT` 滿 **或** 其第一次回填週期穩定，節點就會報告 `/ready`，並且就緒狀態會喺進程剩餘壽命期間保持。後續嘅對等節點波動永遠唔會將服務中嘅節點移出輪詢。
- 當對等節點長時間無法訪問時，週期也會穩定。因此，唯一對等節點宕機嘅節點會變成 Ready 狀態，但持有少量或無數據。它會服務未命中而不是錯誤。如果你想根據差異來控制發布，`/status/rollout` 會報告 `backfill_initial_cycle`（`pending`、`complete` 或 `degraded`）。

**跨回填變更升級網格。** 回填之前嘅 Kura 版本通過一種不同且現已移除嘅對等協議進行同步。喺採用僅支持回填嘅版本之前，請先將每個節點滾動升級到運行回填嘅版本 **之前**。使用兩種協議嘅節點無法互相同步：一個熱節點會繼續從其卷提供服務，但停止縮小其差距，而喺該窗口期內從空卷啟動嘅節點永遠唔會變成 Ready。Chart 會為你設置 `KURA_BACKFILL_ENABLED=true`，所以先升級 Chart 可以解決這個問題。單個 `helm upgrade` 同時移動 Chart 和鏡像則不行。

除 mTLS 外，還應使用網絡級別限制。喺 Kubernetes 中，將 Kura 作為 `StatefulSet` 運行，每個 Pod 配備一個持久卷，並使用無頭服務進行對等發現，然後只允許屬於同一快取部署嘅 Pod 之間訪問內部對等端口，例如使用 `NetworkPolicy`。喺 Kubernetes 之外，為每個節點分配穩定嘅 DNS 名稱或 IP 地址，使用其他節點嘅內部 URL 初始化網格，並使用防火牆規則或安全組，以便只有快取節點可以訪問對等端口。公共快取流量應通過公共 HTTP 或 gRPC 端點進入，而不是通過內部對等平面。

## 配置 {#configuration}

Helm chart 從 `values.yaml` 渲染常見嘅運行時設置。如果你喺無 Kubernetes 嘅情況下運行 Kura，請直接喺進程上設置相同嘅變量。Chart 未直接映射嘅變量可以通過 `extraEnv` 或 `extraEnvFrom` 注入。

| 環境變量 | 描述 | 必需 | 默認值 | Helm 值 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 公共快取端口。一個監聽器服務 HTTP 快取 API、健康端點和 Bazel/Buck2 REAPI gRPC (h2c)。 | 是 | 無默認值 | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura 對等節點使用嘅內部 HTTP 或 mTLS 端口。 | 是 | 無默認值 | `peerTls.internalPort` |
| `KURA_TENANT_ID` | 節點嘅默認租戶標識符。 | 是 | 無默認值 | `config.tenantId` |
| `KURA_REGION` | 用於指標和複製狀態嘅區域標籤。 | 是 | 無默認值 | `config.region` |
| `KURA_TMP_DIR` | 用於暫存請求正文和多部分組裝嘅臨時目錄。 | 是 | 無默認值 | 固定為 `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | 喺請求受到背壓之前，允許進入 `KURA_TMP_DIR` 嘅最大暫存字節數。 | 否 | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | 用於元數據狀態和段文件嘅持久目錄。 | 是 | 無默認值 | 固定為 `/var/cache/kura` |
| `KURA_NODE_URL` | 其他對等節點用來訪問此節點嘅規範內部 URL。 | 是 | 無默認值 | 從 Pod DNS 名稱和 `peerTls.internalPort` 派生 |
| `KURA_PEERS` | 喺發現收斂之前使用嘅種子對等節點列表。 | 否 | `KURA_NODE_URL` | 從 StatefulSet 副本派生 |
| `KURA_DISCOVERY_DNS_NAME` | 用於自動對等發現嘅 DNS 名稱。 | 否 | 已禁用 | 由 `config.discovery.enabled` 啟用 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | 用於驗證對等 mTLS 嘅 CA 證書。 | 否 | 已禁用，或喺節點註冊時喺 `KURA_DATA_DIR` 下派生 | `peerTls.enabled` 和 `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 內部對等 mTLS 監聽器使用嘅證書。 | 否 | 已禁用，或喺節點註冊時喺 `KURA_DATA_DIR` 下派生 | `peerTls.enabled` 和 `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 內部對等 mTLS 監聽器使用嘅私鑰。 | 否 | 已禁用，或喺節點註冊時喺 `KURA_DATA_DIR` 下派生 | `peerTls.enabled` 和 `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 用於喺託管 HTTPS 監聽器 (`KURA_HTTPS_PORT`) 上終止 TLS 嘅證書。 | 否 | 已禁用 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | 與 `KURA_PUBLIC_TLS_CERT_PATH` 配對嘅私鑰。 | 否 | 已禁用 | `extraEnv` |
| `KURA_HTTPS_PORT` | 服務相同託管 HTTP + gRPC 表面（ALPN 協商）嘅 TLS 端口。僅喺設置公共 TLS 路徑時綁定。 | 否 | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 純文本 HTTP/2 端口，僅服務 gRPC API，適用於重用上游連接嘅代理。請參閱 [將節點置於負載均衡器後面](#load-balancers)。 | 否 | 已禁用 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | 用於請求和後台 I/O 嘅文件描述符預算。 | 否 | 自動派生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | 請求喺 FD 背壓導致檢出失敗之前等待嘅時間。 | 否 | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | 固定段讀取句柄嘅最大數量。 | 否 | 自動派生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | 關閉期間處理進行中 HTTP 和 gRPC 工作嘅寬限期。 | 否 | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura 開始減少可選內存使用嘅軟內存水位線。 | 否 | 自動派生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura 暫停複製並清理熱快取嘅硬內存水位線。 | 否 | 自動派生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | 內存清單快取嘅最大大小。 | 否 | 自動派生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | 每個請求嘅鍵值負載最大大小。 | 否 | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | 預留給元數據存儲嘅文件描述符預算。 | 否 | 自動派生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | 元數據存儲嘅後台刷新和壓縮併發數。 | 否 | 自動派生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | 元數據存儲讀快取嘅容量。 | 否 | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | 預留給元數據寫入緩衝嘅總內存預算。 | 否 | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | 每次刷新前每個元數據寫入緩衝區嘅大小。 | 否 | 自動派生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | 內存中保留嘅元數據寫入緩衝區最大數量。 | 否 | 自動派生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 進行中嘅多部分上傳喺過期之前可以停留嘅時間。 | 否 | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura 掃描陳舊多部分上傳嘅頻率。 | 否 | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 按年齡排序嘅段環份額，從最新開始計算，限定回填操作可以回溯嘅範圍。 | 否 | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 節點喺運行第一個回填週期時，段環達到幾滿就會報告自己已準備好。 | 否 | `KURA_BACKFILL_MARGIN_PERCENT` 嘅一半 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 組成一個回填主體批次嘅字節閾值，以及超過該大小時單獨獲取條目嘅臨界值。 | 否 | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio 工作線程數量。 | 否 | 自動派生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP 追蹤端點。留空以禁用追蹤。 | 否 | 已禁用 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry 服務名稱。 | 是 | 無預設值 | Helm 中嘅 Pod 名稱 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry 部署環境。 | 是 | 無預設值 | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | 用於崩潰和錯誤報告嘅 Sentry DSN。 | 否 | 已禁用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | 節點運行所在數據中心嘅 ISO 3166-1 alpha-2 國家代碼，會作為 `geo.country.iso_code` 標記喺導出嘅追蹤記錄上。 | 否 | 當 `KURA_REGION` 嘅前綴係國家代碼時從其派生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | 該數據中心嘅 ISO 3166-2 行政區劃（例如 `US-CA`），標記為 `geo.region.iso_code`。 | 否 | 未設置 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 要求調用者提供有效嘅 Tuist 令牌。設置 `KURA_AUTH_TUIST_URL` 會單獨啟用授權，而將其設置為 `false` 並不會關閉授權 — 要運行未經授權嘅節點，請取消設置 URL。 | 否 | 已禁用 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | 節點進行授權對接嘅 Tuist 伺服器。單獨設置即可啟用授權。 | 啟用授權時必填 | 無預設值 | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | 連接到該伺服器嘅連接超時時間。 | 否 | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | 向該伺服器發出請求嘅請求超時時間。 | 否 | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | 節點可自行讀取令牌嘅共享密鑰，從而避免往返請求。它既用於簽名也用於驗證，因此僅喺節點和伺服器處於同一信任邊界時使用。自託管節點通常不設置此項。 | 否 | 已禁用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | 伺服器用於簽署快取令牌嘅金鑰對公鑰部分，以一個或多個連接嘅 PEM 區塊形式提供。可以讀取這些令牌但無法生成新令牌，這正係可從互聯網訪問嘅節點應該持有嘅配置。與 `KURA_AUTH_JWT_SECRET` 互斥。 | 否 | 已禁用 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | 該金鑰嘅算法：使用密鑰時為 `HS256`、`HS384` 或 `HS512`，使用公鑰時為 `ES256`。 | 否 | 使用密鑰時為 `HS256`，使用公鑰時為 `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | 令牌必須包含嘅簽發者。 | 否 | 不檢查 | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | 令牌必須包含嘅受眾列表，以逗號分隔。 | 否 | 不檢查 | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 身份驗證和授權快取中各自保留嘅最大條目數。 | 否 | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 每次啟動時將節點註冊到控制平面，配置其對等證書並提供 `KURA_TENANT_ID` 和 `KURA_PEERS`。 | 否 | 已禁用 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | 節點進行註冊對接嘅 Tuist 伺服器。 | 註冊時必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | 喺儀表板中生成嘅節點憑證嘅客戶端 ID。 | 註冊或登記時必填 | 無預設值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | 與 `KURA_CONTROL_PLANE_CLIENT_ID` 配對嘅客戶端密鑰。 | 註冊或登記時必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_URL` | 節點發送註冊心跳嘅絕對 URL，用於宣告其面向客戶嘅端點。 | 登記時必填 | 無預設值 | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | 控制平面提供給客戶嘅面向客戶嘅快取 URL。帳戶上嘅每個客戶都必須能夠訪問此 URL。 | 登記時必填 | 無預設值 | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 註冊心跳頻率。租約允許錯過多次心跳，因此單次心跳丟失不會導致端點失效。 | 否 | `60000` | `extraEnv` |

如果啟用內部對等 mTLS，請同時設置 `KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH` 和 `KURA_INTERNAL_TLS_KEY_PATH`。`KURA_NODE_URL` 和 `KURA_PEERS` 中嘅每個值都必須使用帶有內部對等端口嘅 `https://`。
