---
{
  "title": "Server",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "了解如何在你的基础设施上部署 Tuist server。"
}
---
# 服务器 {#server}

我们为需要对基础设施拥有更多控制权的组织提供 Tuist 服务器的自托管版本。该版本允许你在自己的基础设施上托管 Tuist，确保你的数据保持安全和私密。

> [!WARNING]
> **需要许可证**
>
> 自托管 Tuist 需要具有法律效力的付费许可证。Tuist 的本地部署版本仅面向 Enterprise 计划的组织提供。如果你对该版本感兴趣，请联系 [contact@tuist.dev](mailto:contact@tuist.dev)。

> [!WARNING]
> **旧版缓存服务**
>
> 旧的自托管缓存节点技术已弃用，不再用于新安装。请使用<.localized_link href="/guides/features/cache/self-hosting">自托管缓存指南</.localized_link>了解当前的自托管缓存基础设施。
>
> 现有部署仍可在 GitHub 的 Markdown 查看器中参考旧版源文档：[缓存节点](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md)和[缓存架构](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md)。

## 发布节奏 {#release-cadence}

Tuist 服务器和 Kura 缓存服务器通过三个 GHCR 镜像渠道发布：**canary**（每次提交到 `main`）、**release candidate**（每周一切出，观察一周）和**stable**（下周一提升）。只有稳定版会移动 `:latest` 并作为默认解析版本；canary 和 release candidate 是 GitHub 预发布版本，你需要通过固定其标签来选择使用。服务器和 Kura 遵循相同的每周发布列车，与<.localized_link href="/cli/release/channels">Tuist CLI 的发布计划</.localized_link>同步。

我们遵循[语义化版本控制](https://semver.org/)以确保版本号和兼容性可预测。主版本号用于标记 Tuist 服务器中的破坏性变更，这类变更需要与自托管用户协调；你不应期望我们会频繁使用它，如果确实需要，请放心，我们将与你合作以确保过渡顺利。

请参阅<.localized_link href="/guides/server/self-host/release/channels">发布渠道</.localized_link>页面，了解如何切出每个渠道、如何在部署中固定某个渠道，以及推荐的策略：让生产环境停留在更新较慢的稳定线，同时让预发环境观察即将发布的版本。

## 浏览器会话升级 {#browser-session-upgrade}

如果七天内没有经过身份验证的页面请求或 LiveView 交互，浏览器会话将过期，且最迟在身份验证后 30 天过期。“记住我”会恢复相同的服务器端会话，但无法延长任一截止时间。活动状态每分钟检查一次，因此空闲会话可能提前最多 59 秒过期。WebSocket 心跳、自动重连和后台更新不会刷新活动状态。这些截止时间不会更改机器凭证或 API 令牌的有效期。

在启动升级后的应用进程之前，运行增量式 `users_tokens` 迁移。现有行不会回填：其创建时间限定了不活跃期和绝对过期时间，并且在访问强制要求 SSO 的组织之前必须重新进行身份验证。回调的提供商、颁发者或已验证的工作区，以及自定义 SSO 连接存储在服务器端，并与组织的当前设置进行比较。关联的账户不能作为会话身份验证的证明。

在将该策略视为已强制执行之前，请升级每个提供服务的 Web 副本。较旧的二进制文件仍可接受其原有的 60 天会话，并且不强制执行新的 LiveView 边界；混合版本在模式上兼容，但在策略上不等效。预计用户需要重新登录。回滚到较旧的二进制文件会削弱这些控制；如果需要进行模式回滚，请在删除新字段之前停止所有读取这些字段的二进制文件。切勿延长旧会话或通过推断来源来避免重新身份验证。

## 认证器应用 MFA {#authenticator-app-mfa}

服务器包含原生的认证器应用（TOTP）双因素身份验证。仪表板尚未提供入口；后续版本将添加设置入口点。它不需要激活标志、托管服务依赖项或身份提供商凭据：只需要 PostgreSQL、下述迁移、一个 TOTP 认证器，以及由所有服务副本共享的稳定加密密钥（`TUIST_SECRET_KEY_ENCRYPTION`，回退到 `TUIST_SECRET_KEY_BASE`）。保持服务器和认证器的时钟同步。MFA 验证及其每五分钟五次失败代码的共享配额使用 PostgreSQL 行锁，而非 Redis。

设置需要在过去五分钟内登录，将设置密钥输入 TOTP 认证器应用，并确认应用生成的代码。系统会一次性显示十个单次使用的恢复代码；请安全存储它们。禁用该因素也需要近期登录以及未使用的认证器或恢复代码。更改因素会使其他浏览器会话失效。重置密码不会移除 MFA，且此实现不提供仅通过电子邮件或管理员绕过丢失因素的方式。

一旦注册，每次新的浏览器登录（包括联合登录）在获得会话或完成基于浏览器的 CLI/设备授权之前，都需要原生第二因素。直接密码登录和 Apple API 登录会拒绝已注册用户，并指示他们使用浏览器登录。已注册用户的新邮箱代理声明需要经过 MFA 验证的浏览器会话；仅邮箱的旧版声明将被拒绝。现有的 API 令牌、机器凭证、工作负载身份及其续订规则保持不变。这是可选的每用户支持，并非组织范围的 MFA 强制要求，也不验证身份提供商自身的 MFA 策略。组织 SSO 除了需要原生因素外，仍然需要正确配置的提供商/颁发者。

注册、登录、使用恢复代码或禁用 MFA 均不需要电子邮件。因素变更通知为尽力而为；投递失败不会撤销已完成的变更。

在部署新二进制文件之前，运行独立的增量迁移 `user_mfa`/`users_tokens.mfa_verified_at`。TOTP 密钥使用现有的 Vault 加密密钥；请保留该密钥及其备份。在允许 MFA 注册之前，完成**所有身份验证服务副本的升级**。旧版二进制文件可以绕过原生 MFA，因此在注册后它们不是策略兼容的回滚目标。删除 MFA 架构会破坏注册和恢复状态；请先停止读取器并保留加密备份。混合版本架构兼容性并不能证明 MFA 或浏览器会话控制已强制执行。

## OAuth 升级和回滚边界 {#oauth-upgrade-and-rollback-boundary}

移除 OAuth 实体缓存需要对现有安装进行分阶段升级。在部署停止 OAuth 缓存失效的版本之前，首先将来自 [#14040](https://github.com/tuist/tuist/pull/14040) 的权威读取兼容版本部署到**每个 OAuth 读取器和写入器**。此兼容阶段首次出现在 **1.355** 发布系列中：`ghcr.io/tuist/tuist:1.355.0-rc.1` 包含它；一旦提升，生产部署应使用稳定的 `1.355.x` 版本。安装在 1.354 或更早版本的系统必须在升级到包含移除功能的后续版本之前完成此阶段。保持 1.355 系列仅用于兼容性：不要将失效移除反向移植到其中。

原始兼容提交也可作为 `ghcr.io/tuist/tuist:sha-c8e54471a425` 获取。另一个镜像仅在保留权威读取**并保留旧版失效**（同时存在旧版消费者时）的情况下才适合作为兼容阶段。在服务流量之前运行该阶段的常规数据库迁移，包括刷新令牌查找索引。

检查每个环境中的所有 Web 副本、后台工作器、计划任务以及单独固定的处理器镜像。等待兼容性推出完成，并在移除失效之前验证没有剩余的缓存读取二进制文件。不要让浮动镜像标签在自动升级期间跳过此阶段。没有旧版消费者的全新安装不需要中间部署。

> [!WARNING]
> **保留权威读取回滚目标**
>
> 移除失效后，普通的滚动回滚必须针对 #14040 或另一个权威读取版本。即使每个无失效进程都已停止，保留的 OAuth 缓存条目仍可能过时，并且重新启动的缓存读取副本可以从对等节点导入它们。
>
> 进一步回滚需要停止并排空**所有**无失效 OAuth 消费者，然后在启动任何缓存读取消费者之前清除或替换**每个**保留的 Boruta 缓存参与者。防止保留的参与者重新加入。仅排空入口或仅重启 Web 副本是不够的；请与你的 Tuist 支持联系人协调此恢复过程，而不是自动清除缓存或回滚数据库迁移。

## 多副本集群 {#multi-replica-clustering}

支持的多副本 Web 部署需要 Erlang 集群来实现跨副本的 Phoenix PubSub 和 Oban PG 通知，而不是作为身份验证的权威机构。当 `server.cluster.enabled` 为 false 时，Chart 会拒绝多个副本，包括可以增长超过一个副本的自动缩放器。以前接受的未集群部署必须计划此升级，而不是绕过保护。在更改成员资格之前，完成<.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 升级序列</.localized_link>，包括移除失效。

使用你的密钥管理器在发布命名空间中创建一个私有 Cookie Secret，然后配置其名称和密钥：

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Cookie 必须具有高熵并由所有参与的 Web 副本共享。切勿使用嵌入在已发布镜像中的 Cookie：拥有分发 Cookie 即授予在其节点上远程执行的权限。分布式发布启动现在拒绝缺失的私有 `RELEASE_COOKIE` 或无效端口，包括显式配置的 `RELEASE_DISTRIBUTION=name` 或 `sname` 且无 DNS 发现的情况。非 Chart 部署还必须一致地配置 `TUIST_CLUSTER_DNS_SERVICE`、`TUIST_CLUSTER_APP_NAME` 以及 Pod IP/节点名称。发现目前使用 IPv4 A 记录。

使用普通的服务器连接 `helm upgrade` 时，将 `cookieExistingSecret` 留空会创建一个 Cookie Secret，并在后续升级中重用其当前值。离线 `helm template`、Argo CD 和其他没有实时 Secret 查找功能的 GitOps 渲染器无法保留该生成的值；它们必须使用由单独管理的稳定 Secret 支持的 `cookieExistingSecret`。不要更改 Cookie 密钥以隐式轮换活动集群。Cookie 轮换需要协调每个参与者的迁移/重启；仅更新 Secret 不会更新现有进程。

从镜像内置 Cookie 进行的首次推出会形成单独的旧/新成员孤岛，直到所有 Web 副本都使用私有 Secret。为实时更新规划迁移窗口。后续的滚动部署会形成混合版本集群，因此要根据实际的旧/新版本限定 PubSub、Oban 通知和对等替换。这些通知不是持久交付保证。在回滚兼容版本时，保留权威读取回滚镜像并保持相同的私有 Cookie。

仅允许受信任的服务器对等点之间访问 EPMD（TCP 4369）和配置的分发端口，绝不允许来自租户工作负载或公共网络的访问。验证你环境中的实际入口/出口隔离；渲染 NetworkPolicy 并不能证明强制执行或后端可达性。在持续负载下的双副本金丝雀必须在提升之前通过加入、滚动替换和故障/恢复测试。DNS 用于发现对等点，而不是在瞬态失败或部分响应时断开健康节点；真正的节点丢失和 OTP 分区预防仍然适用。libcluster 可能仍会为保留回调记录成功的“断开连接”操作而不关闭连接；从节点上线/下线事件或 `Node.list()` 建立实际成员资格，而不仅仅依赖该日志行。

## 持续部署 {#continuous-deployment}

我们建议将生产环境固定在一个稳定的次要版本线上（例如 `ghcr.io/tuist/tuist:1.351`），这样日常升级只会交付向后移植的修复。稳定版本线会在发布候选频道上经过一周的浸泡测试后，于每周一 06:00 UTC 提升；在金丝雀或当前发布候选标签上的暂存环境可以在回归问题影响用户之前将其捕获。有关推荐的固定策略，请参阅<.localized_link href="/guides/server/self-host/release/channels">发布频道</.localized_link>。

如果你希望在不修改清单文件的情况下吸收新发布的稳定功能，请固定使用 `:latest`。该标签每周一早上更新一次，因此请相应安排你的部署窗口。以下是一个 GitHub Actions 工作流示例，它会按此节奏检查并部署最新的稳定镜像：

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

## 网络可信访问 {#network-trusted-access}

自托管安装可以允许受信任网络上的开发者无需登录即可提交洞察数据、使用缓存，或两者兼用。仪表板和管理功能仍然需要身份验证。

仅启用你所需的功能：

| 服务器环境变量 | 允许无需登录执行的操作 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 提交构建和测试洞察数据 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 读写缓存的构建输出 |

这两个设置默认均为**关闭**，相互独立，并适用于实例范围内的所有账户和项目，包括私有项目。它们在托管版 Tuist 上不可用，也不能替代自托管许可证。

当未设置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` 时，原有的 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 名称仍作为兼容性回退保留。

> [!WARNING]
> 仅在强制实施的办公网络或 VPN 边界后方启用这些设置。任何能够访问已启用端点的人都可以提交报告，或者在启用缓存访问时读取和覆盖缓存输出。这可能导致伪造遥测数据、缓存投毒和资源耗尽。报告响应还可能泄露私有项目句柄和构建系统信息。Tuist 不会验证 VPN 成员资格，也不会将转发的 IP 头信息视为成员资格的证明。

### 配置实例 {#network-trusted-instance-configuration}

1. 使用防火墙或私有入口，将 Tuist 服务器、每个 Kura HTTP/gRPC 监听器以及任何 Bazel BES 入口限制在你的受信任网络内。
2. 在升级客户端之前，先升级每个服务器和 Kura 副本。保持 Kura 身份验证启用，并使用 `KURA_AUTH_TUIST_URL` 及其控制平面凭据；禁用它会绕过这些限制。使用<.localized_link href="/guides/features/cache/self-hosting">自托管缓存指南</.localized_link>配置你的缓存端点。
3. 在每个相关的 Tuist 服务器副本上设置上述所需的变量，然后重启或重新部署它们。只有确切值 `true` 才能启用设置。没有仪表板切换开关或单独的 Kura 标志。

### 配置客户端 {#network-trusted-client-configuration}

在每个兼容的客户端上配置最终的自托管服务器 URL 和项目。当缺少凭据时，客户端会自动发现哪些功能已启用；无需客户端主动选择加入。发现过程不遵循重定向。现有凭据会继续使用，无效或刷新失败的凭据会导致错误，而不是回退到匿名模式。重新登录或显式注销以恢复。

在启用洞察访问之前，将所有共享凭据的工具升级到能够保留损坏或被拒绝的凭据、拒绝不可读的凭据目录，并在未签名报告中省略 Git 来源的版本。旧版工具可能会删除凭据并无意中允许匿名回退；仅升级服务器无法修复此问题。如果服务器缺乏发现支持或回滚到旧版本，客户端必须进行身份验证。原有的 `TUIST_NETWORK_TRUSTED_PUBLISHING` 客户端设置不再适用。

- **洞察：** 仅提交已完成的 Xcode、Gradle、Elixir/Mix 和 Bazel 报告，不包含归档、附件、覆盖率、分片规划或现有报告访问权限。参与者声明未经过验证；未签名的遥测数据不能作为可信测试证据或自动化依据。有关客户端设置和隐私详情，请参阅<.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>、<.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 和 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 指南。
- **缓存：** 支持 CLI 编译/模块缓存、Bazel 缓存和 Gradle 任务缓存。缓存清除和远程资产下载仍然需要凭据。不支持的客户端必须继续进行身份验证。
- **Bazel：** 报告需要显式的 `TUIST_BAZEL_BES_BACKEND` 和兼容的 Kura。缓存和报告选项是独立启用的。更改凭据或任一设置后，重新运行 `tuist bazel setup`；更改编译缓存配置后，重新运行 `tuist cache config`。

报告请求限制为每个项目 8 MB、每分钟 60 个请求和每天 10,000 个请求。对于具有多个副本的部署，配置共享 Valkey 以实现部署范围的配额；否则限制针对每个进程。如果配置的共享配额后端不可用，未签名的报告将被拒绝。同时添加入口连接、正文和速率限制。

### 禁用网络可信访问 {#disable-network-trusted-publishing}

将相关变量设置为 `false`，然后重启**每个相关的服务器副本**。旧副本在被替换之前可以继续接受无需凭据的请求。在最后一个副本切换后的 60 秒内，新请求的缓存访问将停止；进行中的传输不会被取消。如果需要立即撤销，请先在入口处阻止流量。现有报告保留其通常的可见性和保留策略，经过身份验证的客户端继续正常工作。

## 运行时要求 {#runtime-requirements}

本节概述了在你的基础设施上托管 Tuist 服务器的要求。

### 兼容性矩阵 {#compatibility-matrix}

Tuist 服务器已经过测试，并与以下最低版本兼容：

| 组件 | 最低版本 | 备注 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 分析功能必需 |

### 运行 Docker 虚拟化镜像 {#running-dockervirtualized-images}

我们通过 [GitHub 容器注册表](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) 以 [Docker](https://www.docker.com/) 镜像的形式分发服务器。

要运行它，你的基础设施必须支持运行 Docker 镜像。请注意，大多数基础设施提供商都支持它，因为它已成为在生产环境中分发和运行软件的标准容器。

### Postgres 数据库 {#postgres-database}

除了运行 Docker 镜像外，你还需要一个[Postgres 数据库](https://www.postgresql.org/)来存储关系数据。大多数基础设施提供商在其服务中都包含 Postgres 数据库（例如，[AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google Cloud](https://cloud.google.com/sql/docs/postgres)）。

> [!NOTE]
> **迁移**
>
> Docker 镜像的入口点在启动服务之前会自动运行所有待处理的架构迁移。


### ClickHouse 数据库 {#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 来存储和查询大量分析数据。构建洞察等功能**必需** ClickHouse。你可以选择自行托管 ClickHouse，或使用其托管服务。

> [!NOTE]
> **迁移**
>
> Docker 镜像的入口点在启动服务之前会自动运行所有待处理的 ClickHouse 架构迁移。

捆绑的 Docker Compose 和 Helm 嵌入式 ClickHouse 配置将 ClickHouse 文本日志级别从镜像默认的 `trace` 降低到 `information`，`system.text_log` 的大部分体积即来源于此。两者还可以限制 ClickHouse 自身的 `system.*` 操作日志表的大小，否则这些表是无上限的，但该功能默认处于关闭状态——见下文。外部 ClickHouse 部署应直接在 ClickHouse 服务中配置这些操作日志。

#### ClickHouse 复制拓扑 {#clickhouse-replication-topology}

Tuist 后方的多副本 ClickHouse 仅在 ClickHouse Cloud 上受支持。自管理的 ClickHouse 为单副本。

摄入迁移会发出一个普通的 `MergeTree` 引擎。在 Cloud 上，这会透明地变为 `SharedMergeTree`，因此写入会落入共享对象存储，且任何副本数量均可工作。在自管理的 ClickHouse 上，`MergeTree` 仅写入单个副本的本地磁盘；多副本设置要么会在副本间静默拆分摄入，要么会根据连接用户的 `database_replicated_allow_only_replicated_engine` 设置方式，以 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` 拒绝 CREATE 语句。

在自管理的 ClickHouse 上运行一个分片和一个副本，并定期备份 ClickHouse 数据目录。如果节点丢失，没有第二个副本可供回退。

#### 限制操作日志保留期 {#capping-operational-log-retention}

保留期可应用于 `system.text_log`、`system.query_log`、`system.query_thread_log`、`system.query_views_log`、`system.trace_log`、`system.metric_log`、`system.asynchronous_metric_log` 和 `system.part_log`。

在已有数据的实例上启用它是一个一次性且不可逆的步骤，这就是为什么两个捆绑包都不会为你执行此操作。任何保留窗口都会导致这些表定义不再与其配置匹配，因此 ClickHouse 会将每个表重命名搁置并启动一个新表，如[被取代的日志表](#superseded-log-tables)所述。留下的旧代包含迄今为止积累的所有数据，且自身不带有任何保留策略，因此除非你在同一步骤中回收它，否则它将永久留在磁盘上，而新窗口仅限制从那时起写入的行。同时启用两者：

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

该单个 `helm upgrade` 是自包含的，因为将 `ttlDays` 从空白设置为具体值会添加即用型挂载并滚动 ClickHouse Pod：它会重启、取代这些表，然后升级后作业会将它们删除。使用 `helm upgrade --wait` 进行部署，以便在作业运行之前滚动 Pod；否则，旧代表会在作业检查之后出现，而下一次 `helm upgrade` 则会回收它们。

使用 Docker Compose 时，取消注释 `docker-compose.yml` 中 `clickhouse` 服务上的 `clickhouse-log-ttl.xml` 卷，并在 `.env` 中设置这两个变量：

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

一旦空间被回收，你可以将 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` 改回 `ignore`，这样后续的 ClickHouse 升级就不会自行丢弃历史记录。

#### 被取代的日志表 {#superseded-log-tables}

ClickHouse 在启动时会检查每个系统日志表是否仍与其配置匹配。如果不匹配，它会将现有表重命名为 `system.<name>_0`，然后是 `_1`、`_2` 等，并启动一个新表。当你更改保留窗口，或在任何更改系统日志架构的 ClickHouse 升级时，都会发生这种情况。

重命名表不会复制其数据，因此这不会消耗额外的磁盘空间。被取代的表后续会发生什么取决于它来自哪个表，因为它会保留在被取代那一刻活动表所拥有的任何保留策略。首次启用保留时，被取代的表没有任何保留策略，因此它会保存迄今为止积累的所有历史记录并无限期保留。随后对窗口的更改会取代已带有 TTL 的表，因此这些表会自行过期并留下一个空表。ClickHouse 永远不会删除表本身，因此在长期运行的实例上，它们无论如何都会积累。

默认情况下会保留被取代的表，以便升级永远不会自行丢弃操作历史记录。将策略设置为 `delete` 以改为删除它们，这会在 `docker compose up` 和每次 `helm upgrade` 时发生：

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

使用 Helm Chart 时，将该策略配置为一个值：

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

删除被取代的表会回收其磁盘空间。活动表永远不会受到影响，自被取代以来写入的行也不会受到影响。

若要在不更改策略的情况下一次性回收空间，请手动删除表：

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 数据库使用 `Atomic` 引擎，这会将普通的 `DROP TABLE` 延迟 `database_atomic_delay_before_drop_table_sec`（默认为八分钟）。`SYNC` 会立即删除数据，当因磁盘已满而删除这些表时，这正是你所需要的。


### 存储 {#storage}

你还需要一个解决方案来存储文件（例如框架和库二进制文件）。Tuist 服务器支持用于服务器自有工件的 S3 兼容存储和 Azure Blob Storage。

> [!TIP]
> **优化缓存**
>
> 如果你的主要目标是降低缓存延迟，你可能不需要自行托管整个服务器。你可以在靠近你的 CI 或开发者网络的地方部署自托管的 Kura 节点，并将它们连接到托管的 Tuist 服务器或你的自托管服务器。
>
> 请参阅<.localized_link href="/guides/cache/self-host">自托管缓存指南</.localized_link>。


### 自托管 Kura 节点 {#self-hosted-cache-nodes}

要将自托管 Kura 节点与自托管 Tuist 服务器配合使用：

1. 在 Tuist 服务器上配置 `KURA_CONTROL_PLANE_CLIENT_ID` 和 `KURA_CONTROL_PLANE_CLIENT_SECRET`。客户端 ID **必须是 UUID**。使用<.localized_link href="/guides/cache/self-host#control-plane-client">自托管缓存指南</.localized_link>中的命令生成 UUID 和随机密钥，并将它们存储在你的部署密钥中。
2. 按照<.localized_link href="/guides/cache/self-host">自托管缓存指南</.localized_link>部署 Kura 节点，使用相同的控制平面凭据。
3. 使用 `KURA_REGISTRATION_URL` 和 `KURA_ADVERTISED_HTTP_URL` 配置每个 Kura 节点。注册心跳会告知服务器哪些就绪的、面向客户端的 Kura 端点可以向 CLI 公布。

## 配置 {#configuration}

服务的配置在运行时通过环境变量完成。鉴于这些变量的敏感性，我们建议对其进行加密并存储在安全的密码管理解决方案中。请放心，Tuist 会极其谨慎地处理这些变量，确保它们永远不会显示在日志中。

> [!NOTE]
> **启动检查**
>
> 必要的变量会在启动时进行验证。如果缺少任何变量，启动将失败，错误消息将详细说明缺失的变量。


### 许可证配置 {#license-configuration}

作为本地部署用户，你将收到一个需要作为环境变量公开的许可证。该许可证用于验证部署并确保服务在协议条款范围内运行。

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 签署服务级别协议后提供的许可证。接受标准许可证密钥或用于隔离环境（服务器无法联系外部服务）的 base64 编码证书。 | 是 | | `******` |

> [!WARNING]
> **过期日期**
>
> 许可证有到期日期。如果许可证在不到 30 天内到期，用户在使用与服务器交互的 Tuist 命令时将收到警告。如果你有兴趣续订许可证，请联系 [contact@tuist.dev](mailto:contact@tuist.dev)。


### 基础环境配置 {#base-environment-configuration}

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 从互联网访问实例的基础 URL | 是 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 用于加密信息的密钥（例如 cookie 中的会话） | 是 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 用于生成哈希密码的盐值 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 用于生成随机令牌的密钥 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 用于对敏感数据进行 AES-GCM 加密的 32 字节密钥 | 否 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | 当为 `1` 时，它会将应用配置为使用 IPv6 地址 | 否 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 应用使用的日志级别 | 否 | `info` | [日志级别](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | 你的 GitHub 应用的 slug，取自 `https://github.com/apps/<slug>`。安装应用时需要。请参阅<.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | 否 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用于 GitHub 应用的 base64 编码私钥，以解锁额外功能，例如发布自动 PR 评论 | 否 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 用于 GitHub 应用的私钥，以解锁额外功能，例如发布自动 PR 评论。**我们建议使用 base64 编码版本以避免特殊字符问题** | 否 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 邮箱地址以 `@<this-domain>` 结尾且已证明控制该地址的用户可以访问运维 URL（`/ops/*`）。未设置时，任何人都无法访问。请参阅[运维](#operations) | 否 | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 在仪表板导航栏中显示为徽章的标签，用于标识服务器实例（例如版本号或分支名称） | 否 | 开发环境中的 Git 分支 | `v1.2.3` |
| `TUIST_WEB` | 启用 Web 服务器端点 | 否 | `1` | `1` 或 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 允许在不登录的情况下提交构建和测试洞察。有关设置和安全要求，请参阅[网络信任访问](#network-trusted-access)。 | 否 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 允许在不登录的情况下读取和写入缓存。有关设置和安全要求，请参阅[网络信任访问](#network-trusted-access)。 | 否 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry Collector 的 gRPC 端点，用于发送追踪数据 | 否 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 兼容 Loki 的端点的基础 URL，用于推送日志（例如 Grafana Alloy 或 Loki） | 否 | | `http://localhost:3100` |

> [!WARNING]
> **通过 HTTPS 提供服务**
>
> 会话 Cookie 标记为 `Secure`，因此浏览器会在纯 `http://` 连接中丢弃它们，导致用户无法登录。在服务器前端终止 TLS（使用来自内部 CA 证书的逆向代理即可），并将 `TUIST_APP_URL` 设置为 `https://` URL，即使是内部或仅限 VPN 的部署也是如此。

### 数据库配置 {#database-configuration}

以下环境变量用于配置数据库连接：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | 访问 Postgres 数据库的 URL。请注意，URL 应包含身份验证信息 | 是 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist 应用表使用的 PostgreSQL 模式。当你的数据库策略不允许使用 `public` 模式时，请设置此项。模式名称必须是未加引号的 PostgreSQL 标识符。 | 否 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | 仅由 `Tuist.Release.migrate` 使用的可选 Postgres URL。当 `DATABASE_URL` 指向权限较窄的运行时角色时，将其设置为所有者角色 URL。 | 否 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 迁移完成后应授予应用表权限的运行时 Postgres 角色。当 Web 服务器不应以模式所有者身份连接时，请与 `TUIST_MIGRATION_DATABASE_URL` 一起使用。 | 否 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | 访问 ClickHouse 数据库的 URL。请注意，URL 应包含身份验证信息 | 否 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | 当为 true 时，它使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 连接到数据库。除非启用 `TUIST_DATABASE_SSL_VERIFY`，否则不会验证服务器证书 | 否 | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | 当为 true 时，数据库服务器证书必须链接到受信任的 CA 并与 `DATABASE_URL` 主机匹配。需要 `TUIST_USE_SSL_FOR_DATABASE`。我们建议启用它 | 否 | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | 包含用于验证数据库服务器的 CA 证书的 PEM 文件路径。未设置时，将使用操作系统的信任存储 | 否 | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | 在连接池中保持打开的连接数 | 否 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 检查从池中检出的所有连接是否超过队列间隔的时间间隔（以毫秒为单位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 池中用于确定是否应开始丢弃新连接的队列阈值时间（以毫秒为单位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 缓冲区刷新之间的时间间隔（以毫秒为单位） | 否 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 强制刷新前的最大 ClickHouse 缓冲区大小（以字节为单位） | 否 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 要运行的 ClickHouse 缓冲区进程数 | 否 | `5` | `5` |

默认情况下，Tuist 会加密数据库连接，但不会验证服务器证书，因此网络路径上的攻击者可以冒充数据库。设置 `TUIST_DATABASE_SSL_VERIFY=1` 以进行验证。如果你的提供商（如 Amazon RDS 和 Google Cloud SQL）使用自己的 CA 签署证书，请下载其 CA 捆绑包，将其挂载到容器中，并将 `TUIST_DATABASE_SSL_CA_CERT_FILE` 指向它。`DATABASE_URL` 中的主机必须与证书中的名称或 IP 地址匹配。启用验证后，未通过这些检查的证书会导致所有数据库连接失败，因此请在启用后检查服务器日志中是否有 `Bad Certificate` 或 `Unknown CA`。

当 `TUIST_DATABASE_SCHEMA` 不是 `public` 时，如果模式尚不存在，发布迁移会在运行 Ecto 迁移链之前创建该模式。如果迁移角色无法创建模式，请预先创建模式并使迁移角色成为其所有者。

Tuist 通过设置会话 `search_path` 将连接指向自定义模式。某些池化或代理的 Postgres 设置（例如 PgBouncer，或限制启动参数的托管数据库）不应用此设置，会话会回退到 `public`，这在迁移期间表现为 `permission denied for schema public`。通过此类设置连接时，请在角色本身上固定模式，以便无论代理如何，每个会话都从该模式开始：

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 身份验证环境配置 {#authentication-environment-configuration}

我们通过 [身份提供商 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 促进身份验证。要使用此功能，请确保所选提供商的所有必要环境变量都存在于服务器环境中。**缺少变量** 将导致 Tuist 绕过该提供商。

#### 电子邮件和密码 {#email-and-password}

电子邮件和密码登录以及自助注册是内置的，默认启用。在需要强制使用身份提供商的实例上（例如，强制执行 SSO 时），你可以完全关闭它们。这将从登录体验中移除电子邮件/密码表单、注册链接和密码重置流程，并关闭所有匹配的服务器端端点，包括 CLI 使用的电子邮件/密码端点（`tuist auth`）。

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 是否可以使用电子邮件和密码进行登录和注册。设置为 `0` 以从登录页面移除电子邮件/密码表单、注册链接和密码重置流程，并关闭匹配的服务器端端点 | 否 | `1` | `0` |

#### 禁用已配置的身份提供商 {#disabling-a-configured-identity-provider}

默认情况下，只要配置了提供商，它就会显示为登录选项。要在保持提供商配置（其凭据保持不变）的同时将其从登录和注册页面中移除，请将相应的开关设置为 `0`。对于 GitHub、Google 和 Apple，这也会关闭登录回调，因此该方法将完全不可用。

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 进行登录（有关应用为何共享其凭据用于登录的信息，请参阅 [GitHub](#github) 部分） | 否 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | 是否可以使用 Google 进行登录 | 否 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 已配置的 Okta 提供商是否显示为登录选项 | 否 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | 是否可以使用 Apple 进行登录 | 否 | `1` | `0` |

#### GitHub {#github}

我们建议使用 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) 进行身份验证，但你也可以使用 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。请确保在服务器环境中包含 GitHub 指定的所有必要环境变量。缺少变量将导致 Tuist 忽略 GitHub 身份验证。要正确设置 GitHub 应用：
- 在 GitHub 应用的常规设置中：
    - 复制 `Client ID` 并将其设置为 `TUIST_GITHUB_APP_CLIENT_ID`
    - 创建并复制一个新的 `client secret` 并将其设置为 `TUIST_GITHUB_APP_CLIENT_SECRET`
    - 将 `Callback URL` 设置为 `http://YOUR_APP_URL/users/auth/github/callback`。`YOUR_APP_URL` 也可以是你的服务器 IP 地址。
- 需要以下权限：
  - 仓库：
    - 拉取请求：读写
  - 账户：
    - 电子邮件地址：只读

在 `Permissions and events` 的 `Account permissions` 部分，将 `Email addresses` 权限设置为 `Read-only`。

然后，你需要在 Tuist 服务器运行的环境中公开以下环境变量：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 应用的客户端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 应用的客户端密钥 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | 是否可以使用 GitHub 进行登录。你为平台集成（PR 评论等）配置的 GitHub App 会与登录共享其客户端凭据，因此它会显示为登录选项。设置为 `0` 以保留应用同时从登录页面移除 GitHub | 否 | `1` | `0` |

#### Google {#google}

你可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 设置 Google 身份验证。为此，你需要创建一个类型为 OAuth 客户端 ID 的新凭据。创建凭据时，选择“Web 应用程序”作为应用程序类型，将其命名为 `Tuist`，并将重定向 URI 设置为 `{base_url}/users/auth/google/callback`，其中 `base_url` 是你托管服务运行的 URL。创建应用后，复制客户端 ID 和密钥，并分别将它们设置为环境变量 `GOOGLE_CLIENT_ID` 和 `GOOGLE_CLIENT_SECRET`。

> [!NOTE]
> **同意屏幕范围**
>
> 你可能需要创建同意屏幕。创建时，请确保添加 `userinfo.email` 和 `openid` 范围，并将应用标记为内部应用。


#### Okta {#okta}

你可以通过 [OAuth 2.0](https://oauth.net/2/) 协议启用 Okta 身份验证。你需要按照 <.localized_link href="/guides/integrations/authentication/sso#okta">这些说明</.localized_link> 在 Okta 上 [创建应用](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在设置 Okta 应用期间获取客户端 ID 和密钥后，你需要设置以下环境变量：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | 用于向 Okta 进行身份验证的客户端 ID。该数字应为你的组织 ID | 是 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用于向 Okta 进行身份验证的客户端密钥 | 是 | | |

需要将数字 `1` 替换为你的组织 ID。这通常为 1，但请检查你的数据库。

### 存储环境配置 {#storage-environment-configuration}

 Tuist 需要存储空间来存放通过 API 上传的构建产物。**必须配置一种受支持的存储解决方案**，Tuist 才能有效运行。

设置 `TUIST_OBJECT_STORAGE_PROVIDER` 以选择服务器构建产物后端：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 服务器构建产物存储后端。对于 S3 兼容存储使用 `s3`，对于 Azure Blob Storage 使用 `azure_blob` | 否 | `s3` | `azure_blob` |

#### S3 兼容存储 {#s3compliant-storages}

你可以使用任何 S3 兼容的存储提供商来存储构建产物。以下环境变量是进行身份验证和配置与存储提供商集成所必需的：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 或 `AWS_ACCESS_KEY_ID` | 用于向存储提供商进行身份验证的访问密钥 ID | 是 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 或 `AWS_SECRET_ACCESS_KEY` | 用于向存储提供商进行身份验证的私有访问密钥 | 是 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或 `AWS_REGION` | 存储桶所在的区域 | 否 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 或 `AWS_ENDPOINT` | 存储提供商的端点 | 是 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 用于存储构建产物的存储桶名称 | 是 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | 用于验证 S3 HTTPS 连接的 PEM 编码 CA 证书。适用于具有自签名证书或内部证书颁发机构的隔离环境。 | 否 | 系统 CA 捆绑包 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 建立与存储提供商连接的超时时间（毫秒） | 否 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 从存储提供商接收数据的超时时间（毫秒） | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 与存储提供商的连接池超时时间（毫秒）。使用 `infinity` 表示无超时 | 否 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 池中连接的最大空闲时间（毫秒）。使用 `infinity` 可保持连接永久活跃 | 否 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 每个池的最大连接数 | 否 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 要使用的连接池数量 | 否 | 系统调度器数量 | `4` |
| `TUIST_S3_PROTOCOL` | 连接到存储提供商时使用的协议（`http1` 或 `http2`） | 否 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | 是否将 URL 构造为以存储桶名称作为子域（虚拟主机） | 否 | `false` | `1` |

> [!NOTE]
> **来自环境变量的 AWS Web 身份验证**
>
> 如果你的存储提供商是 AWS，并且希望使用 Web 身份令牌进行身份验证，可以将环境变量 `TUIST_S3_AUTHENTICATION_METHOD` 设置为 `aws_web_identity_token_from_env_vars`，Tuist 将使用该方法并通过常规的 AWS 环境变量进行身份验证。


#### Google Cloud Storage {#google-cloud-storage}
对于 Google Cloud Storage，请按照 [这些文档](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) 获取 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` 对。`AWS_ENDPOINT` 应设置为 `https://storage.googleapis.com`。其他环境变量与任何其他 S3 兼容存储相同。

#### Azure Blob Storage {#azure-blob-storage}

对于 Azure Blob Storage，设置 `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` 并配置 Azure 存储帐户凭据：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 存储帐户名称 | 是 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | 用于签署 Azure Blob REST 请求和 SAS URL 的存储帐户访问密钥 | 是 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 存储服务器构建产物的容器 | 是 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 服务端点。省略则使用 `https://<account>.blob.core.windows.net` | 否 | 从帐户名称派生 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 用于签名请求和 SAS URL 的 Azure Blob REST API 版本 | 否 | `2020-12-06` | `2020-12-06` |

使用 Helm Chart 时，设置 `server.storage.provider=azure_blob` 并填写 `server.azureBlob.*`。Chart 的顶层 `objectStorage` 设置仍保持 S3 兼容，因为可选的缓存和注册表镜像工作负载仍然需要 S3 兼容存储。如果禁用这些工作负载且服务器使用 Azure Blob，请设置 `objectStorage.mode=external` 并将外部对象存储端点和凭据留空，以避免部署嵌入式 MinIO 服务。

#### 构建产物保留 {#artifact-retention}

自托管实例默认禁用构建产物清理。每种受支持的构建产物类型都有各自的环境变量。将变量设置为正整数天数即可启用该类型的清理。不设置或留空变量仅会禁用对应类型的清理。

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

使用 Helm Chart 时，可将相同的保留窗口配置为映射：

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

全部六个键均为可选。此示例为每种受支持的构建产物类型启用独立的保留窗口。省略某个键或将其值留空可保持该类型的清理处于禁用状态。自托管保留窗口没有 30 天的上限。配置的值如果不是正整数，会导致服务器在启动时失败。

更改保留变量后重启服务器。每个排队的自托管清理批次在删除文件前都会检查当前配置，因此取消设置或留空变量，或者增加其窗口，也能在重启后保护文件免受待处理作业的影响。

| 环境变量 | 从对象存储中移除的构建产物文件 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 缓存、旧版内容寻址存储缓存、模块缓存以及 Gradle 缓存文件 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | 应用预览构建和图标 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 当前和旧版构建归档 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 存储在已过期的运行构建产物前缀下的所有对象，包括结果包、调用记录和会话归档 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 测试运行附件 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 测试分片包 |

计划清理仅移除构建产物数据块。它会保留相应的 PostgreSQL 和 ClickHouse 行记录，因此在下载过期后，构建、测试、运行、预览和分片的元数据仍可在仪表板中可见。此配置不会更改 ClickHouse 表的保留规则。

### 电子邮件配置 {#email-configuration}

Tuist 需要电子邮件功能用于用户身份验证和事务性通知（例如密码重置、帐户通知）。目前，**仅支持 Mailgun** 作为电子邮件提供商。

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | 用于通过 Mailgun 进行身份验证的 API 密钥 | 是* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 发送电子邮件的域名 | 是* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | 将显示在“发件人”字段中的电子邮件地址 | 是* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用于用户回复的可选回复地址 | 否 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 跳过新用户的电子邮件确认。启用后，用户会自动确认并可在注册后立即登录 | 否 | 如果未配置电子邮件则为 `true`，如果已配置电子邮件则为 `false` | `true`, `false`, `1`, `0` |

\* 仅在你希望发送电子邮件时才需要电子邮件配置变量。如果未配置，电子邮件确认会自动跳过

> [!NOTE]
> **SMTP 支持**
>
> 目前不提供通用 SMTP 支持。如果你需要在本地部署中使用 SMTP 支持，请联系 [contact@tuist.dev](mailto:contact@tuist.dev) 讨论你的需求。


> [!NOTE]
> **隔离网络部署**
>
> 对于无法访问互联网或未配置电子邮件提供商的本地安装，默认会自动跳过电子邮件确认。用户可在注册后立即登录。如果你已配置电子邮件但仍希望跳过确认，请设置 `TUIST_SKIP_EMAIL_CONFIRMATION=true`。若要在配置电子邮件时要求电子邮件确认，请设置 `TUIST_SKIP_EMAIL_CONFIRMATION=false`。

> [!NOTE]
> **电子邮件配额和密码重置链接**
>
> 配置电子邮件后，邀请邮件（新建、批量或重发）限制为每位收件人每五分钟一封，并且每次突发最多 50 封，按每个组织和每位邀请者每小时补充 50 封的速率恢复。取消邀请不会恢复配额，当配额耗尽时，邀请 API 会返回 `429` 和 `Retry-After`。在有多个副本的情况下，配置共享 Valkey 以实现整个部署范围的配额；如果已配置但不可用，邀请邮件将被拒绝。密码重置链接在 15 分钟后过期。


### Git 平台配置 {#git-platform-configuration}

Tuist 可以 <.localized_link href="/guides/server/authentication">与 Git 平台集成</.localized_link>，以提供额外功能，例如在你的拉取请求中自动发布评论。

#### GitHub {#platform-github}

自托管的 Tuist 服务器无法安装在 `https://tuist.dev` 上运行的 GitHub App。GitHub App 绑定到注册它们的服务器，因此你的部署需要在 github.com 上拥有自己的 App。

##### 注册 App {#platform-github-registering-the-app}

[创建一个由你的 GitHub 组织拥有的 GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。你可以复用为身份验证创建的 App，除非你创建的是 OAuth App。使用以下配置进行设置，将 `YOUR_APP_URL` 替换为 `TUIST_APP_URL` 的值：

| 设置 | 值 |
| --- | --- |
| 回调 URL | `YOUR_APP_URL/users/auth/github/callback` 和 `YOUR_APP_URL/integrations/github/authorize` |
| 设置 URL | `YOUR_APP_URL/integrations/github/setup` |
| 更新时重定向 | 已启用 |
| Webhook URL | `YOUR_APP_URL/webhooks/github` |
| Webhook 密钥 | 任意随机字符串。你将把它设置为 `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

授予以下仓库权限：

| 权限 | 访问级别 |
| --- | --- |
| 内容 | 只读 |
| 元数据 | 只读 |
| 议题 | 读写 |
| 拉取请求 | 读写 |
| 检查 | 读写 |

同时授予 **成员：只读** 的组织权限。在 github.com 设置期间，Tuist 会检查连接组织安装的人员是否为活跃的 GitHub 组织所有者，而不仅仅是拥有其某个仓库访问权限的人。

订阅 App 的 `Check run`、`Pull request` 和 `Issue comment` 事件。

保持 **在安装期间请求用户授权（OAuth）** 处于禁用状态，以便 GitHub 将安装程序发送到设置 URL。Tuist 使用额外的 `/integrations/github/authorize` 回调启动单独的身份验证步骤以验证安装所有权。当在 GitHub 上开始安装时，安装者随后选择一个 Tuist 组织；在 Tuist 中开始的安装会保留其组织。

##### 配置服务器 {#platform-github-configuring-the-server}

设置以下环境变量，然后重启服务器：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | App 的 slug，即其公共页面 URL `https://github.com/apps/<slug>` 的最后一个路径组件 | 是 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 数字 App ID，用于验证安装所有权 | 是 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 应用的客户端 ID | 是 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 应用的客户端密钥 | 是 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 应用的 Base64 编码私钥。优先于 `TUIST_GITHUB_APP_PRIVATE_KEY`，后者对平台处理换行符的方式敏感 | 是 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | 在 GitHub 应用上配置的 Webhook 密钥 | 否 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **配置所有必需的 App 凭据**
>
> 组织的集成页面上的 **安装 GitHub App** 按钮将保持禁用状态，直到设置了 `TUIST_GITHUB_APP_NAME`、`TUIST_GITHUB_APP_CLIENT_ID`、`TUIST_GITHUB_APP_CLIENT_SECRET` 和私钥。还需要数字 `TUIST_GITHUB_APP_ID` 来验证安装所有权。安装 URL 嵌入了 App slug，因此缺少 `TUIST_GITHUB_APP_NAME` 尤其会导致 GitHub 返回 404 的链接。

服务器重启后，组织管理员按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 安装 App 并将仓库连接到项目。

##### OIDC 身份验证依赖于此 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link> 会根据连接到项目的仓库解析 CI 令牌中的仓库声明，而连接只能通过已安装的 GitHub App 创建。在 CI 工作流在没有令牌的情况下运行 `tuist auth login` 之前，请完成上述设置。

你的 Tuist 服务器还需要出站访问你的 CI 提供商的 OIDC 颁发者以获取其签名密钥：

| CI 提供商 | 主机 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

上述环境变量仅配置 Tuist 的 github.com App。要将 Tuist 与 GitHub Enterprise Server (GHES) 实例集成，组织管理员需切换到集成页面上的 **企业服务器** 选项卡并输入 GHES 基础 URL — Tuist 会引导他们通过 GitHub 的 [App 清单流程](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) 在其 GHES 实例上注册一个新的 Tuist App。新 App 的凭据按安装加密存储；不需要额外的 `TUIST_GITHUB_APP_*` 环境变量。

#### Origin {#platform-origin}

自托管的 Tuist 服务器需要自己的 Origin 应用，并使用你部署的 URL 和签名密钥进行配置。为每个 Tuist 环境注册单独的应用，以便安装和凭据保持独立。

##### 注册 App {#platform-origin-registering-the-app}

1. 使用支持 Ed25519 的 OpenSSL 生成 Ed25519 签名密钥对：

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. 在 [Origin 应用设置](https://cursor.com/codebase/settings/apps) 中创建应用。将 `origin-app-public.pem` 的内容注册为其公共签名密钥。保密 `origin-app-private.pem`；你将把它提供给 Tuist 服务器，而不是上传到 Cursor。
3. 配置以下设置，将 `YOUR_APP_URL` 替换为你的 Tuist 部署的 HTTPS 基础 URL：

   | 设置 | 值 |
   | --- | --- |
   | 主页 URL | `YOUR_APP_URL` |
   | 重定向 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL | `YOUR_APP_URL/webhooks/origin` |

4. 复制注册的 App ID，它以 `app_` 开头。

Tuist 在安装期间请求以下权限：

| 范围 | 用途 |
| --- | --- |
| `repository:pull_requests:read` | 查找拉取请求及其当前的头部提交。 |
| `repository:pull_requests:reviews:write` | 读取、发布和更新报告评论。Origin 包含相应的审查读取权限。 |
| `repository:metadata:read` | 发现仓库并读取其默认分支。由 Origin 自动授予。 |

不要选择可选的仓库 Webhook 事件。安装生命周期通知已足够；不需要源代码访问、合并权限和检查运行权限。

##### 配置服务器 {#platform-origin-configuring-the-server}

设置以下环境变量，然后重启服务器：

| 环境变量 | 描述 | 必需 | 默认值 | 示例 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | 从 Origin 应用设置中复制的 App ID。 | 是 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `origin-app-private.pem` 的完整内容，包括 `BEGIN PRIVATE KEY` 和 `END PRIVATE KEY` 行以及所有换行符。 | 是 | | `-----BEGIN PRIVATE KEY-----...` |

将私钥存储在你部署的密钥管理器中。保留其多行 PEM 格式；此设置不接受 base64 编码的替代方案。切勿将密钥提交到源代码控制或在日志中暴露。两个变量必须属于同一个注册的应用。

你的 Tuist 服务器需要对 `api.cursor.com` 的出站 HTTPS 访问权限。Cursor 必须能够将请求发送到 webhook URL，并且管理员必须能够在浏览器中返回重定向 URI。两个注册的 URL 都必须与你部署的 HTTPS 基础 URL 匹配。

##### 安装 App {#platform-origin-installing-the-app}

服务器重启后，管理员打开 **设置 → 集成**，在 Origin 下选择 **连接**，并批准应用对相应 Origin 账户和仓库的访问权限。在此流程中会保留 Tuist 组织。直接从 Origin 发起的安装则会提示管理员登录并选择要连接的 Tuist 组织。然后他们选择 **添加新项目连接** 将 Tuist 项目链接到原生仓库。

按照 <.localized_link href="/guides/integrations/gitforge/origin">Origin 集成指南</.localized_link> 进行项目连接和结果上传要求。安装应用不会启动构建或测试工作流；这些工作流会继续向你的 Tuist 服务器报告结果。

## 本地测试 {#testing-locally}

我们提供了一个全面的 Docker Compose 配置，其中包含在部署到基础设施之前在本地机器上测试 Tuist 服务器所需的所有依赖项：

- PostgreSQL 15
- 用于分析的 ClickHouse 26.5
- 用于协调的 ClickHouse Keeper
- 用于 S3 兼容存储的 MinIO
- 用于本地自托管缓存测试的 Kura
- 用于数据库管理的 pgweb

> [!CAUTION]
> **需要许可证**
>
> 运行 Tuist 服务器（包括本地开发实例）在法律上需要有效的 `TUIST_LICENSE` 环境变量。如果你需要许可证，请联系 [contact@tuist.dev](mailto:contact@tuist.dev)。


**快速入门：**

1. 下载配置文件：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 配置环境变量：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   捆绑的 ClickHouse 服务接受以下可选的操作日志控制：

   | 环境变量 | 描述 | 默认值 | 示例 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 日志表（如 `text_log`、`query_log`、`trace_log`、`metric_log` 和 `part_log`）的保留窗口（以天为单位） | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 服务器记录器和 `system.text_log` 级别 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 当 ClickHouse 替换系统日志表时，如何处理它留下的 `<name>_N` 表。`ignore` 保留它们，`delete` 删除它们 | `ignore` | `delete` |

3. 启动所有服务：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   在 Apple Silicon 上，Docker Desktop 会自动拉取 Tuist 和依赖镜像的 `linux/arm64` 变体。要强制使用 amd64 模拟进行调试，请使用 `DOCKER_DEFAULT_PLATFORM=linux/amd64` 运行 Compose。

   捆绑的 Compose 文件使用命名 Docker 卷来存储持久化数据。如果你将其替换为主机绑定挂载，请先创建主机目录，并确保容器用户（尤其是 ClickHouse 和 ClickHouse Keeper 的数据目录）具有写入权限。

4. 在 http://localhost:8080 访问服务器

**服务端点：**
- Tuist 服务器：http://localhost:8080
- Kura 缓存（HTTP + REAPI gRPC 共用一个端口）：http://localhost:4000
- MinIO 控制台：http://localhost:9003（凭据：`tuist` / `tuist_dev_password`）
- MinIO API：http://localhost:9002
- pgweb（PostgreSQL UI）：http://localhost:8081
- Prometheus 指标：http://localhost:9091/metrics
- ClickHouse HTTP：http://localhost:8124

**常用命令：**

检查服务状态：
```bash
docker compose ps
# or: podman compose ps
```

查看日志：
```bash
docker compose logs -f tuist
```

停止服务：
```bash
docker compose down
```

重置所有内容（删除所有数据）：
```bash
docker compose down -v
```

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 环境变量示例文件

## 使用 Helm 部署 Kubernetes {#kubernetes-with-helm}

Tuist 提供了用于在 Kubernetes 上部署的官方 Helm Chart。该 Chart 打包了 Tuist 服务器和缓存服务，以及可随需替换为外部提供商的嵌入式基础设施依赖项。

### 安装 Chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

要锁定特定的 Chart 版本：

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### 许可证 {#helm-license}

`server.license.key` 值既接受标准许可证密钥，也接受用于隔离环境安装的 Base64 编码许可证证书；服务器会自动检测是哪一种。

通过 `--set` 传递许可证适用于快速安装。如果你将值保存在版本控制中，请将许可证存储在由 Helm 外部管理的 Kubernetes Secret 中（例如使用 Vault、Sealed Secrets 或 SOPS），并在 Chart 中指向它：

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 下的条目指定了你的 Secret 中保存许可证值的字段，该值可以是许可证密钥，也可以是用于隔离环境安装的 Base64 编码许可证证书。`existingSecretKeys` 下的每个条目默认使用 Chart 自身的键名，因此请将你的 Secret 中不包含的条目设置为空字符串，如上面的 `certificateBase64` 所示。否则，Pod 会引用不存在的键并导致启动失败。在安装或升级 Chart 之前，请在发布命名空间中创建该 Secret。

仅通过一个来源配置许可证：`server.license.key` 或 `server.license.existingSecret`。如果未设置任何来源或组合了多个来源，Chart 将无法渲染。通过 `server.extraEnv` 传递的许可证不计作来源，因此请改用 `existingSecret`。

### 基础设施依赖项 {#helm-infrastructure-dependencies}

该 Chart 管理三个基础设施依赖项：`postgresql`、`clickhouse` 和 `objectStorage`。每个依赖项默认处于 **嵌入式** 模式，这意味着 Chart 会在集群内部署它们。若要指向你自己的外部实例，请将依赖项的 `mode` 设置为 `external`，并在你的 `values.yaml` 中填写连接详细信息。例如，要使用外部 PostgreSQL 数据库：

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

如果你在 Helm 外部管理 PostgreSQL 凭据，请改为将 Chart 指向现有的 Kubernetes Secret：

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

Chart 会从 Secret 中读取主机名、用户名和密码，并通过 Kubernetes 环境变量替换组成 `DATABASE_URL`，因此密码不会渲染到 Helm 清单中。由于密码会被插入到数据库 URL 中，Secret 中的密码值应当是 URL 安全的。

同样的模式也适用于 `clickhouse` 和 `objectStorage`。请参阅 Chart 的 `values.yaml` 中每个部分下的 `external` 块，以获取完整的可配置字段集。

### 共享调度和标签 {#helm-shared-scheduling-and-labels}

该 Chart 在 `global` 下公开了一小组共享的 Pod 设置，以便运维人员可以调整部署以适应其集群，而无需为每个工作负载重复相同的值：

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

在需要执行以下操作时使用这些设置：

- 为每个 Pod 添加特定于集群的标签
- 从私有注册表拉取镜像副本
- 定位专用的节点池
- 允许将 Pod 调度到为 Tuist 工作负载保留的污点节点上

### 工作负载身份和服务账户 {#helm-workload-identity}

该 Chart 按应用工作负载限定服务账户的范围，以便你仅在需要的地方授予身份：

- `server.serviceAccount` 适用于 Tuist 服务器部署和迁移任务
- `cache.serviceAccount` 适用于缓存部署

例如，当缓存在 EKS 上使用外部 S3 存储桶时，你可以为缓存工作负载启用 IRSA，而无需将相同的 IAM 角色附加到嵌入式数据库：

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 兼容性覆盖 {#helm-compatibility-overrides}

该 Chart 将存储和网格特定的调整设为可选，以保持默认值的可移植性：

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

仅在你的集群需要时才使用这些覆盖：

- `cache.podSecurityContext` 默认为空。如果你的存储类或 CSI 驱动程序需要在挂载卷上共享组所有权，请设置 `fsGroup`。
- `clickhouse.embedded.service.nativePort` 默认为 ClickHouse 的标准 `9000` 原生服务端口，当服务网格或平台保留与该端口冲突时可以更改。
- `clickhouse.embedded.systemLogs.ttlDays` 默认为空，这使得 ClickHouse 对嵌入式内部日志表（如 `system.text_log`、`system.query_log`、`system.trace_log`、`system.metric_log` 和 `system.part_log`）保持无限制的保留策略。设置它会一次性取代这些表，因此请结合 `supersededTables: delete` 一起使用——参见 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">限制操作日志保留</.localized_link>。
- `clickhouse.embedded.systemLogs.level` 对于嵌入式 ClickHouse 服务器日志记录和 `system.text_log` 默认为 `information`。与 `ttlDays` 不同，它不属于任何表定义的一部分，因此更改它永远不会取代表。
- `clickhouse.embedded.systemLogs.supersededTables` 默认为 `ignore`，并决定当 ClickHouse 取代系统日志表时如何处理留下的 `<name>_N` 表。将其设置为 `delete` 以在每次 `helm upgrade` 时删除它们。
- 对 `ttlDays` 和 `level` 的编辑将在 ClickHouse Pod 下次重启时生效，因为两者都是 `subPath` 挂载，且 Chart 在其 ConfigMap 更改时不会滚动更新 StatefulSet。

### 可观测性 {#helm-observability}

该 Chart 包含一个可选的可观测性栈（OpenTelemetry Collector、Prometheus、Grafana、Loki 和 Tempo）。它**默认禁用**。要在你的 `values.yaml` 中启用它：

```yaml
# values.yaml
observability:
  enabled: true
```

启用后，Grafana 将提供预配置的日志、追踪和指标下钻功能。对于外部可观测性，请保持此选项禁用，并通过 `server.extraEnv` 配置端点：

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### 值参考 {#helm-values-reference}

有关可配置值的完整列表，请参阅 Chart 的 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

## 部署 {#deployment}

官方 Tuist Docker 镜像可在以下位置获取：
```
ghcr.io/tuist/tuist
```

发布的镜像包含用于 `.xcactivitylog` 归档文件的嵌入式 Linux 构建处理功能，因此自托管部署可以在不运行任何额外服务的情况下处理构建——`ProcessBuildWorker` Oban 作业在每个服务器 Pod 内进程中运行。如果你希望将构建处理卸载到专用的副本集（例如，独立于 Web 层扩展解析吞吐量），请在 Helm Chart 中设置 `processor.enabled: true`：Chart 会将同一镜像部署为仅队列消费者（`TUIST_PROCESSOR_MODE=true`）。有关完整的配置项，请参阅 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)。

> [!NOTE]
> `.xcresult` 解析依赖于 Xcode 中的 `xcresulttool`，因此只能在 macOS 上运行。CLI 为自托管部署透明地处理此问题：`tuist test` 针对任何非 `tuist.dev` 服务器默认为 **本地** 处理模式，在开发者机器上解析 xcresult（该机器已具备用于构建本身的 Xcode）并上传结构化结果。测试结果无需任何额外基础设施即可摄入。

### 拉取 Docker 镜像 {#pulling-the-docker-image}

你可以通过执行以下命令来获取镜像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

该镜像同时发布了 `linux/amd64` 和 `linux/arm64` 版本，因此 Docker 会自动为主机选择原生的 Linux 架构。

或者拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 镜像 {#deploying-the-docker-image}

Docker 镜像的部署过程将根据你选择的云提供商和你组织的持续部署方法而有所不同。由于大多数云解决方案和工具（如 [Kubernetes](https://kubernetes.io/)）都使用 Docker 镜像作为基本单元，因此本节中的示例应与你的现有设置很好地契合。

> [!WARNING]
> 如果你的部署流水线需要验证服务器是否已启动并运行，你可以向 `/ready` 发送 `GET` HTTP 请求，并断言响应中的状态码为 `200`。


#### Fly {#fly}

若要在 [Fly](https://fly.io/) 上部署应用，你需要一个 `fly.toml` 配置文件。考虑在你的持续部署 (CD) 流水线中动态生成它。以下是一个供你参考的示例：

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

然后你可以运行 `fly launch --local-only --no-deploy` 来启动应用。在后续部署中，你需要运行 `fly deploy --local-only` 而不是 `fly launch --local-only`。Fly.io 不允许拉取私有 Docker 镜像，这就是我们需要使用 `--local-only` 标志的原因。


## Prometheus 指标 {#prometheus-metrics}

Tuist 在 `/metrics` 处公开 Prometheus 指标，以帮助你监控自托管实例。这些指标包括：

### Finch HTTP 客户端指标 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作为其 HTTP 客户端，并公开有关 HTTP 请求的详细指标：

#### 请求指标
- `tuist_prom_ex_finch_request_count_total` - Finch 请求总数（计数器）
  - 标签：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 请求持续时间（直方图）
  - 标签：`finch_name`、`method`、`scheme`、`host`、`port`、`status`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s、10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 请求异常总数（计数器）
  - 标签：`finch_name`、`method`、`scheme`、`host`、`port`、`kind`、`reason`

#### 连接池队列指标
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在连接池队列中等待的时间（直方图）
  - 标签：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 连接在使用前处于空闲状态的时间（直方图）
  - 标签：`finch_name`、`scheme`、`host`、`port`、`pool`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、5s、10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 队列异常总数（计数器）
  - 标签：`finch_name`、`scheme`、`host`、`port`、`kind`、`reason`

#### 连接指标
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立连接所花费的时间（直方图）
  - 标签：`finch_name`、`scheme`、`host`、`port`、`error`
  - 桶：10ms、50ms、100ms、250ms、500ms、1s、2.5s、5s
- `tuist_prom_ex_finch_connect_count_total` - 连接尝试总数（计数器）
  - 标签：`finch_name`、`scheme`、`host`、`port`

#### 发送指标
- `tuist_prom_ex_finch_send_duration_milliseconds` - 发送请求所花费的时间（直方图）
  - 标签：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms、1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 连接在发送前处于空闲状态的时间（直方图）
  - 标签：`finch_name`、`method`、`scheme`、`host`、`port`、`error`
  - 桶：1ms、5ms、10ms、25ms、50ms、100ms、250ms、500ms

所有直方图指标都提供 `_bucket`、`_sum` 和 `_count` 变体，以便进行详细分析。

### 其他指标

除了 Finch 指标外，Tuist 还公开以下指标：
- BEAM 虚拟机性能
- 自定义业务逻辑指标（存储、账户、项目等）
- 数据库性能（使用 Tuist 托管的基础设施时）

## 运维 {#operations}

Tuist 在 `/ops/` 下提供一组实用工具，你可以用来管理你的实例。

> [!WARNING]
> **授权**
>
> 只有电子邮件域名与 `TUIST_OPERATOR_EMAIL_DOMAIN` 匹配的用户才能访问 `/ops/` 端点。如果未设置该变量，则任何人都无法访问。请将其设置为你控制的邮箱所属的域名。
>
> 用户还必须证明其对地址的控制权：通过点击确认或密码重置邮件、使用 Google、GitHub 或 Apple 登录，或者输入一次性代码或出示代理登录的已验证电子邮件。在没有邮件提供商的情况下，默认自动确认的账户在完成此操作之前不符合条件。创建账户后，仅当地址位于 `TUIST_OPERATOR_EMAIL_DOMAIN` 中时才会记录证明，因此在你设置或更改变量后，尚未在此变量下证明其地址的管理员需要再次执行此操作。通过使用这些提供商之一登录或通过代理登录创建的账户，从创建时就带有证明。如果没有邮件提供商，使用密码注册的账户无法关联这些提供商之一，因此请通过使用 Google、GitHub 或 Apple 登录来创建管理员账户，或者配置邮件提供商。
>
> 在此检查存在之前创建的账户尚未记录该证明，因此现有管理员在重置密码或使用这些提供商之一登录一次后即可重新获得访问权限。
>
> 当操作员域中尚未提供该证明的账户首次通过这种方式证明其地址时，Tuist 会移除其密码、通行密钥以及到组织单点登录提供商的链接，并将其从浏览器和 CLI 中登出，因为注册该地址的人可能并非其所有者。对此类账户执行密码重置也会产生相同效果，只是会设置新密码。账户上配置的身份验证器应用会保留；如果它不属于所有者，请为其移除。操作员域之外已确认的账户会保留其凭据。所有者可以继续使用提供商登录，或者通过重置设置新密码。
>
> 由 SCIM 预配创建或重命名的账户在所有者提供证明之前没有任何证明。


- **错误（`/ops/errors`）：** 你可以查看应用程序中发生的意外错误。这有助于调试和了解问题所在，如果你遇到问题，我们可能会要求你与我们分享这些信息。
- **仪表板（`/ops/dashboard`）：** 你可以查看一个仪表板，它提供对应用程序性能和健康状况的洞察（例如内存消耗、正在运行的进程、请求数量）。这个仪表板对于了解你使用的硬件是否足以处理负载非常有用。
