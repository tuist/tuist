---
{
  "title": "自托管缓存",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "部署自托管缓存节点并将其连接到 Tuist。"
}
---

# 自托管缓存 {#self-hosted-cache}

自托管缓存节点让你将构建产物和缓存元数据保留在生成和使用这些输出的机器附近。当 CI、开发者办公室、远程工作站或区域计算集群之间的缓存延迟至关重要时，请使用它们。

目标是在所有地方实现低延迟缓存，而不仅仅是在恰好靠近中央缓存的单一环境中。每个缓存节点从本地磁盘提供读写服务，同时网格在对等节点之间复制产物和元数据，以便其他位置随着时间的推移也能受益于同一缓存。

> [!NOTE]
> Tuist 的自托管缓存节点由 [Kura](https://github.com/tuist/tuist/tree/main/kura) 驱动，这是 Tuist 的去中心化缓存网格。Kura 是缓存节点的数据平面：它提供缓存读写服务，在磁盘上存储本地状态，并将产物和元数据复制到对等节点。

## 自托管缓存如何与 Tuist 配合使用 {#how-self-hosted-cache-fits-with-tuist}

Tuist 的托管缓存使用 `https://<account>.cache.tuist.dev`。对于自托管 Tuist 服务器，CLI 会从服务器的 `TUIST_CACHE_ENDPOINTS` 设置中检索缓存 URL。将其设置为主缓存服务器或负载均衡器的 URL。如果包含多个 URL，则使用第一个。

对于连接到 **托管 Tuist 服务器** 的私有/自定义缓存节点，请在开发者 shell 和 CI 中设置显式端点：

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

此覆盖在两种服务器类型上均优先，并且对于自托管 Tuist 服务器是可选的。对于 Xcode 缓存守护进程，设置后请重新运行 `tuist setup cache`，以便 LaunchAgent 接收更新后的环境变量。

自托管 Tuist 服务器从静态配置中获取端点。在 Tuist 托管服务器上，节点使用凭据进行身份验证并自行注册。首先使用下面两个部分之一部署节点，然后参阅 [将节点连接到 Tuist](#connect-nodes-to-tuist)。

## 在 Kubernetes 上部署 {#deploy-on-kubernetes}

Kura 通过 GitHub Container Registry 以 Helm chart 的形式分发。它将 Kura 部署为带有持久卷的 `StatefulSet`、用于对等发现无头服务，以及用于 HTTP 和 gRPC 流量的常规服务。

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

对于同一集群中的自托管 Tuist 服务器，配置其主缓存端点：

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

这会在服务器 Pod 中设置 `TUIST_CACHE_ENDPOINTS`。使用开发机器和 CI 可以访问的地址；上述集群内部服务名称适用于在集群内运行的客户端。

> [!IMPORTANT]
> 每个 Kura 节点必须拥有自己的 `KURA_DATA_DIR`。Kura 会对数据目录获取应用级写锁，并期望只有一个进程拥有它。在 Kubernetes 中，每个 Pod 使用一个持久卷。在 Kubernetes 之外，不要让多个进程指向同一个挂载目录。

## 不使用 Kubernetes 部署 {#deploy-without-kubernetes}

Kura 也可以作为普通容器在虚拟机或裸机主机上运行。在此模式下，你需要负责进程监督、持久存储、路由和对等发现。

至少，每个节点都需要一个持久数据目录、一个临时目录、一个公共缓存端口（一个监听器同时服务于 HTTP 缓存 API 和 REAPI gRPC）、一个内部对等 URL，以及静态对等列表或发现机制：

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

在自托管 Tuist 服务器上，配置开发机器和 CI 可以访问的主缓存 URL：

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## 将节点置于负载均衡器之后 {#load-balancers}

客户端对每个缓存端点 URL 同时使用 HTTP 和 gRPC：HTTP 用于健康检查和 HTTP 缓存 API，gRPC 用于模块缓存和 Bazel 的远程缓存。客户端与 Kura 之间的任何入口、负载均衡器或 CDN 都必须在相同的主机名和端口上转发两者。这适用于客户端收到的每个端点，因为 CLI 会选择响应最快的一个。如果 gRPC 无法到达 Kura，CLI 会警告远程模块缓存不可用，并仅使用本地模块缓存。

将这些路径前缀作为 HTTP/2 上的 gRPC 路由到 Kura，其余内容作为 HTTP 路由：

| 路径前缀 | 使用者 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | 模块缓存，Bazel |
| `/google.bytestream.` | 模块缓存，Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel 构建事件 |

Kura 在 `KURA_PORT` 上接受明文 HTTP/2 (h2c)，并在设置了 `KURA_PUBLIC_TLS_CERT_PATH` 和 `KURA_PUBLIC_TLS_KEY_PATH` 时在 `KURA_HTTPS_PORT` 上接受基于 TLS 的 HTTP/2。如果你的代理像 ingress-nginx 那样在请求间复用上游连接，请设置 `KURA_GATEWAY_GRPC_PORT` 并将 gRPC 流量发送到该端口。它仅提供 gRPC 服务，因此 HTTP/1.1 和 gRPC 请求永远不会共享连接。

按以下方式配置 gRPC 路由：

- 无请求体大小限制。上传会在单个请求中发送一个文件，最大可达 2 GiB。
- 关闭请求和响应缓冲。
- 读取、发送和空闲超时至少为 300 秒。

Kura 不提供 gRPC 健康检查服务。通过 HTTP 在 `/ready` 对节点进行健康检查。如果你的负载均衡器需要 gRPC 健康检查，请调用 `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` 并接受 gRPC 状态码 `0` 和 `16`。启用了授权的节点会用 `16` (`UNAUTHENTICATED`) 响应没有令牌请求。

### ingress-nginx {#load-balancers-ingress-nginx}

使用 Helm chart 时，保持 HTTP 入口在 `/` 上，并为同一主机添加 gRPC 入口。只有 HTTP 入口声明 TLS：

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

gRPC 目标组需要 HTTPS 监听器。在该监听器上：

1. 将默认规则转发到协议版本为 `HTTP1` 且位于 `KURA_PORT` 的目标组，并通过 HTTP 在 `/ready` 进行健康检查。
2. 创建第二个目标组，协议版本为 `gRPC`，在 `KURA_GATEWAY_GRPC_PORT`（或 `KURA_PORT`）上使用协议 `HTTP`，或在 `KURA_HTTPS_PORT` 上使用协议 `HTTPS`。按上述说明配置其健康检查。
3. 添加一条规则，将路径模式 `/build.bazel.remote.execution.v2.*`、`/google.bytestream.*`、`/build.bazel.remote.asset.v1.*` 和 `/google.devtools.build.v1.*` 转发到第二个目标组。
4. 将负载均衡器的空闲超时提高到至少 300 秒。

### CDN {#load-balancers-cdns}

位于节点前方的 CDN 必须支持 gRPC，且不得在其防火墙规则中阻止 gRPC 路径。客户端以最多 2 MiB 的分块上传大型构件，并由节点进行组装，因此任何请求都不需要大的请求体或长时间的上传。模块缓存和 Xcode 编译缓存都采用这种方式，Bazel 在使用 `--experimental_remote_cache_chunking` 构建时也如此（Bazel 8.7 以及 9.1 或更高版本）。如果没有该标志，Bazel 会在单个请求中上传每个输出，因此 CDN 还必须允许大的请求体，并允许上传耗时达到你的最慢链路上最大输出所需的时间。如果你的 CDN 无法满足这些要求，请为客户端提供一个绕过它的主机名，例如仅 DNS 记录。

#### Cloudflare {#load-balancers-cloudflare}

在任何套餐下，模块缓存都可以通过代理的 Cloudflare 主机名正常工作。在区域中：

1. 在 **网络** 下，开启 **gRPC**。
2. 在 **SSL/TLS** 下，将加密模式设置为 **完全** 或 **完全（严格）**。Cloudflare 通过 443 端口连接到源站，因此源站必须在该端口提供 TLS 并通过 ALPN 提供 HTTP/2。
3. 确保没有 WAF 自定义规则或托管规则阻止上述 gRPC 路径。

如果源站在大约两分钟后仍未开始响应，Cloudflare 会终止请求。不带 `--experimental_remote_cache_chunking` 的 Bazel 上传只有在最后一个字节到达后才会得到响应，因此在 Cloudflare 上，此类上传如果耗时超过该时间就会失败。

## 将节点连接到 Tuist {#connect-nodes-to-tuist}

配置客户端路由并将你的节点注册到 Tuist，以便它们的地址、就绪状态和使用情况显示在仪表板中。

在 **自托管 Tuist 服务器** 上，你使用 `TUIST_CACHE_ENDPOINTS` 静态声明端点，如上述部署部分所示。CLI 使用第一个配置的 URL。`TUIST_CACHE_ENDPOINT` 会为单个客户端覆盖该 URL。

在 **Tuist 托管服务器** 上，在开发者 shell 和 CI 中设置 `TUIST_CACHE_ENDPOINT`，以将缓存请求路由到你的节点。每个节点使用你生成的凭据进行身份验证，然后注册其地址并向仪表板报告其就绪状态。本节介绍节点注册。

> [!IMPORTANT]
> **企业版套餐**
>
> 自托管缓存节点仅在企业版套餐中提供。下面描述的 **自托管服务器** 部分仅对该套餐的账户显示。

### 生成节点凭据 {#generate-a-node-credential}

在 Tuist 仪表板中，打开你的账户，进入 **缓存**，找到 **自托管服务器**。选择 **生成凭据** 来创建客户端 ID 和密钥。

该凭据仅授权创建它的账户的流量。

密钥仅显示一次，关闭对话框后无法恢复，因此请将其直接复制到节点读取的密钥存储中。撤销凭据会立即停止使用该凭据的所有节点进行身份验证，因此在撤销正在使用的凭据之前，请先生成替换凭据。

### 在启动时注册节点 {#enroll-the-node-on-boot}

注册是启动节点的推荐方式。设置 `KURA_ENROLL_ON_BOOT` 并为节点提供其凭据和自身的对等 URL：

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

节点在本地生成其密钥对，因此私钥永远不会离开节点，并且它会接收签名的对等证书、账户 CA、其租户标识符和对等列表。这就是你否则需要手动配置的所有内容：已注册的节点不需要 `KURA_TENANT_ID`、不需要 `KURA_PEERS`，也不需要配置对等 TLS。

保持 `KURA_INTERNAL_TLS_*` 未设置：注册会将证书材料写入 `KURA_DATA_DIR` 下的 `tls` 目录。仅当你自行提供证书而不是通过注册时，才自行设置这些路径，如 [构建缓存网格](#build-a-cache-mesh) 中所述。

首次加入账户网格的节点在成为环的服务成员之前，会拉取账户的现有缓存。为整个缓存调整数据卷大小，并预期首次加入在广域链路上会花费一些时间。节点在追赶期间报告 `joining`，之后报告 `serving`。

### 公布端点 {#advertise-the-endpoint}

注册会加入网格。注册会向 Tuist 报告节点的客户端访问地址和就绪状态。设置注册变量：

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

节点每 60 秒针对 180 秒的租约发送一次心跳。当租约过期时，Tuist 会认为其注册不可用。Tuist 从不调用节点，因此它只需对你的客户端可达，而无需从互联网可达。

### 验证节点是否在服务中 {#verify-the-node-is-serving}

回到仪表板中的 **缓存**，节点会出现在 **已注册节点** 下，显示其端点、区域、状态和最后心跳。从未出现的节点未到达注册端点或身份验证失败。出现后又消失的节点已停止发送心跳或停止报告自身就绪。

### 将租户标识符与你的账户句柄匹配 {#match-the-tenant-identifier}

`KURA_TENANT_ID` 必须等于你的 Tuist 账户句柄。控制平面将心跳中的租户与从凭据解析出的账户进行比较，并以 `409 tenant_mismatch` 拒绝不匹配的情况，因此具有错误值的节点虽然能成功身份验证，但永远无法注册。

> [!IMPORTANT]
> 本指南前面的 Helm chart 和容器示例都将此默认值设为 `default`。该值对于自托管 Tuist 服务器是正确的，因为租户是一个本地标签；但对于 Tuist 托管服务器上的账户则是错误的，因为它必须命名账户。注册节点可以完全避免这个问题，因为控制平面会提供该值。

未设置 `KURA_TENANT_ID` 不会跳过检查。它会完全禁用注册：节点继续服务缓存流量，仪表板中不显示任何内容，也不报告错误。如果节点健康但缺失于 **已注册节点**，请首先检查此变量。

### 选择你的客户端可以访问的公布 URL {#choose-an-advertised-url}

为 `KURA_ADVERTISED_HTTP_URL` 以及在 Tuist 服务器或 CLI 上配置的缓存 URL 使用客户端可访问的地址。

当每个配置为使用它的客户端都能解析并访问该名称时，仅限内部的主机名是合适的。对于不同网络上的客户端，请使用共享的可访问地址，或为每个环境配置一个可访问的缓存节点。

## 构建缓存网格 {#build-a-cache-mesh}

缓存网格允许你将缓存容量部署在需要它的计算资源旁边。公司可以在其主要 CI 运行器附近运行一个节点，在欧洲开发人员附近运行另一个节点，在美国办公室或区域构建集群附近再运行一个节点。每个位置都读写最近的节点，而 Kura 会在后台复制工件和元数据，以便其他位置的后续构建可以重用相同的输出。

只有当节点能够通过 Kura 的内部对等端口相互访问时，网格才能正常工作。该对等平面与 Tuist 客户端使用的公共缓存端点是分离的。Kura 使用它来检查成员资格、回填新加入的节点，并在接受本地写入后复制工件。

我们强烈建议在节点跨区域、云、VPC、办公室或任何不完全私有于缓存部署的网络进行通信时，使用 [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) 保护对等平面。启用 mTLS 后，Kura 仅向提供由配置的 CA 签名的证书的对等方提供内部复制端点。对等证书必须涵盖节点用于相互调用的 DNS 名称，并且对等 URL 必须在内部端口上使用 `https://`。

> [!NOTE]
> 针对 Tuist 托管控制平面注册的节点会在注册期间接收其对等证书和账户 CA，因此以下手动步骤适用于未注册的网格。

例如，这会生成一个私有 CA 和一个对等证书，小型网格中的每个节点都可以挂载该证书。将 DNS 名称替换为你的节点在 `KURA_NODE_URL` 和 `KURA_PEERS` 中使用的内部名称。

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

### 节点间的追赶 {#catch-up-between-nodes}

加入或重新加入网格的节点会执行**回填**：它按最新优先的顺序遍历每个对等方的条目并拉取缺失的内容，而实时复制则覆盖在对等方可见期间进行的写入。回填过程从对等方的最新条目回溯到节点的段环视界与其上次完成回填中较早的那个，因此保证节点持有最近的数据，但不一定是所有数据。`KURA_BACKFILL_MARGIN_PERCENT` 设置视界的回溯深度。

在运行网格之前，有两点值得注意：

- 一旦节点的段环达到 `KURA_BACKFILL_READY_RING_PERCENT` 满度 **或** 其首次回填周期稳定，节点就会报告 `/ready`，并且就绪状态将在进程剩余生命周期内保持。随后的对等方波动永远不会使服务中的节点退出轮转。
- 当对等方长时间不可达时，周期也会稳定。因此，唯一对等方宕机的节点会在持有少量或无数据的情况下变为就绪状态。它会处理未命中而不是报错。如果你希望根据差异来控制发布，`/status/rollout` 会报告 `backfill_initial_cycle`（`pending`、`complete` 或 `degraded`）。

**跨回填变更升级网格。** 回填之前的 Kura 版本通过另一种现已移除的对等协议进行追赶。在采用仅支持回填的版本**之前**，先将每个节点滚动升级到运行回填的版本。使用这两种协议的节点无法相互追赶：热节点会继续从其卷提供服务但停止缩小差距，而在该窗口期内从空卷启动的节点永远不会变为就绪状态。Chart 为你设置了 `KURA_BACKFILL_ENABLED=true`，因此先升级 Chart 可以解决此问题。单独一次同时移动 Chart 和镜像的 `helm upgrade` 则不行。

除了 mTLS 之外，还要使用网络级限制。在 Kubernetes 中，将 Kura 作为 `StatefulSet` 运行，每个 Pod 配备一个持久卷，并使用无头服务进行对等发现，然后仅允许属于同一缓存部署的 Pod 之间访问内部对等端口，例如通过 `NetworkPolicy`。在 Kubernetes 之外，为每个节点分配稳定的 DNS 名称或 IP 地址，使用其他节点的内部 URL 初始化网格，并使用防火墙规则或安全组，确保只有缓存节点可以访问对等端口。公共缓存流量应通过公共 HTTP 或 gRPC 端点进入，而不是通过内部对等平面。

## 配置 {#configuration}

Helm chart 从 `values.yaml` 渲染常见的运行时设置。如果在没有 Kubernetes 的情况下运行 Kura，请直接在进程上设置相同的变量。Chart 未直接映射的变量可以通过 `extraEnv` 或 `extraEnvFrom` 注入。

| 环境变量 | 描述 | 必需 | 默认值 | Helm 值 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 公共缓存端口。一个监听器服务于 HTTP 缓存 API、健康端点以及 Bazel/Buck2 REAPI gRPC (h2c)。 | 是 | 无默认值 | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura 对等方使用的内部 HTTP 或 mTLS 端口。 | 是 | 无默认值 | `peerTls.internalPort` |
| `KURA_TENANT_ID` | 节点的默认租户标识符。 | 是 | 无默认值 | `config.tenantId` |
| `KURA_REGION` | 用于指标和复制状态的区域标签。 | 是 | 无默认值 | `config.region` |
| `KURA_TMP_DIR` | 用于暂存请求体和多部分组装的临时目录。 | 是 | 无默认值 | 固定为 `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | 在请求受到背压之前，允许进入 `KURA_TMP_DIR` 的最大暂存字节数。 | 否 | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | 用于元数据状态和段文件的持久目录。 | 是 | 无默认值 | 固定为 `/var/cache/kura` |
| `KURA_NODE_URL` | 其他对等方用于访问此节点的规范内部 URL。 | 是 | 无默认值 | 派生自 Pod DNS 名称和 `peerTls.internalPort` |
| `KURA_PEERS` | 在对等发现收敛之前使用的种子对等列表。 | 否 | `KURA_NODE_URL` | 派生自 StatefulSet 副本数 |
| `KURA_DISCOVERY_DNS_NAME` | 用于自动对等发现的 DNS 名称。 | 否 | 已禁用 | 由 `config.discovery.enabled` 启用 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | 用于验证对等 mTLS 的 CA 证书。 | 否 | 已禁用，或在节点注册时派生自 `KURA_DATA_DIR` 下 | `peerTls.enabled` 和 `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 内部对等 mTLS 监听器使用的证书。 | 否 | 已禁用，或在节点注册时派生自 `KURA_DATA_DIR` 下 | `peerTls.enabled` 和 `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 内部对等 mTLS 监听器使用的私钥。 | 否 | 已禁用，或在节点注册时派生自 `KURA_DATA_DIR` 下 | `peerTls.enabled` 和 `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 用于在托管的 HTTPS 监听器 (`KURA_HTTPS_PORT`) 上终止 TLS 的证书。 | 否 | 已禁用 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | 与 `KURA_PUBLIC_TLS_CERT_PATH` 配对的私钥。 | 否 | 已禁用 | `extraEnv` |
| `KURA_HTTPS_PORT` | 服务于同一托管 HTTP + gRPC 接口（通过 ALPN 协商）的 TLS 端口。仅在设置公共 TLS 路径时绑定。 | 否 | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 纯文本 HTTP/2 端口，仅服务于 gRPC API，适用于重用上游连接的代理。请参阅[将节点置于负载均衡器之后](#load-balancers)。 | 否 | 已禁用 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | 用于请求和后台 I/O 的文件描述符预算。 | 否 | 自动派生 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | 请求在 FD 背压导致检出失败前的等待时间。 | 否 | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | 最大固定段读取句柄数。 | 否 | 自动派生 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | 关闭期间为进行中的 HTTP 和 gRPC 工作提供的宽限期。 | 否 | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | 软内存水位线，Kura 在此开始减少可选内存使用。 | 否 | 自动派生 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | 硬内存水位线，Kura 在此暂停复制并清理热缓存。 | 否 | 自动派生 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | 内存中清单缓存的最大大小。 | 否 | 自动派生 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | 每个请求的键值负载最大大小。 | 否 | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | 为元数据存储保留的文件描述符预算。 | 否 | 自动派生 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | 元数据存储的后台刷新和压缩并发度。 | 否 | 自动派生 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | 元数据存储读取缓存的容量。 | 否 | 自动派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | 为元数据写入缓冲保留的总内存预算。 | 否 | 自动派生 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | 每次刷新前每个元数据写入缓冲区的大小。 | 否 | 自动派生 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | 内存中保留的最大元数据写入缓冲区数量。 | 否 | 自动派生 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 正在进行的多部分上传在过期前可停留的时间。 | 否 | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura 扫描过时多部分上传的频率。 | 否 | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 按最新顺序计算的段环份额，用于限制回填操作的回溯范围。 | 否 | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 节点在首次回填周期仍在运行时报告自身就绪的段环填充率。 | 否 | `KURA_BACKFILL_MARGIN_PERCENT` 的一半 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 构成单个回填主体批次的字节阈值，以及条目单独获取的大小上限。 | 否 | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio 工作线程数。 | 否 | 自动派生 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP 追踪端点。留空以禁用追踪。 | 否 | 已禁用 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry 服务名称。 | 是 | 无默认值 | Helm 中的 Pod 名称 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry 部署环境。 | 是 | 无默认值 | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | 用于恐慌和错误报告的 Sentry DSN。 | 否 | 已禁用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | 节点所在数据中心的 ISO 3166-1 alpha-2 国家代码，作为 `geo.country.iso_code` 标记在导出的追踪中。 | 否 | 当其前缀为国家代码时，从 `KURA_REGION` 派生 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | 该数据中心的 ISO 3166-2 分区（例如 `US-CA`），标记为 `geo.region.iso_code`。 | 否 | 未设置 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 要求调用方提供有效的 Tuist 令牌。设置 `KURA_AUTH_TUIST_URL` 即可启用授权，将此设置为 `false` 不会关闭授权——取消设置 URL 以运行未经授权的节点。 | 否 | 已禁用 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | 节点进行授权所针对的 Tuist 服务器。单独设置即可启用授权。 | 启用授权时必需 | 无默认值 | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | 对该服务器调用的连接超时时间。 | 否 | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | 对该服务器调用的请求超时时间。 | 否 | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | 节点可自行读取令牌的共享密钥，从而跳过往返。它既签名也验证，因此仅在节点和服务器处于同一信任边界时使用。自托管节点通常不设置此项。 | 否 | 已禁用 | `extraEnv` 或 `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | 服务器用于签署缓存令牌的密钥对的公钥部分，以一个或多个串联的 PEM 块形式提供。可读取这些令牌但无法生成新令牌，这符合可从互联网访问的节点应持有的权限。与 `KURA_AUTH_JWT_SECRET` 互斥。 | 否 | 已禁用 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | 该密钥的算法：使用共享密钥时为 `HS256`、`HS384` 或 `HS512`，使用公钥时为 `ES256`。 | 否 | 使用共享密钥时为 `HS256`，使用公钥时为 `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | 令牌必须包含的颁发者。 | 否 | 不检查 | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | 令牌必须包含的受众，以逗号分隔。 | 否 | 不检查 | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 身份验证和授权缓存中各自保留的最大条目数。 | 否 | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 每次启动时将节点注册到控制平面，配置其对等证书并提供 `KURA_TENANT_ID` 和 `KURA_PEERS`。 | 否 | 已禁用 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | 节点进行注册所针对的 Tuist 服务器。 | 注册时必需 | 无默认值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | 在仪表板中生成的节点凭证的客户端 ID。 | 注册或登记时必需 | 无默认值 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | 与 `KURA_CONTROL_PLANE_CLIENT_ID` 配对的客户端密钥。 | 注册或登记时必需 | 无默认值 | `extraEnv` |
| `KURA_REGISTRATION_URL` | 节点发送注册心跳的绝对 URL，用于通告其面向客户端的端点。 | 注册时必需 | 无默认值 | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | 控制平面提供给客户端的面向客户端的缓存 URL。账户下的每个客户端都必须能够访问此 URL。 | 注册时必需 | 无默认值 | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 注册心跳频率。租约容忍多次心跳丢失，因此单次心跳丢失不会导致端点失效。 | 否 | `60000` | `extraEnv` |

如果启用内部对等 mTLS，请同时设置 `KURA_INTERNAL_TLS_CA_CERT_PATH`、`KURA_INTERNAL_TLS_CERT_PATH` 和 `KURA_INTERNAL_TLS_KEY_PATH`。`KURA_NODE_URL` 以及 `KURA_PEERS` 中的每个值都必须使用带有内部对等端口的 `https://`。
