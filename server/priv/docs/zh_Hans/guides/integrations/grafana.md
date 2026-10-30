---
{
  "title": "Grafana",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "在 Grafana 中监控 Tuist 的构建健康状况、耗时和缓存节省情况，并为你的团队配置告警。"
}
---

# Grafana 集成 {#grafana}

Tuist 数据源允许你在 Grafana 中使用构建、测试和缓存指标，包括持续时间、失败次数以及缓存报告的节省时间。围绕团队关注的项目和指标构建仪表板，或将 Tuist 指标与公司现有仪表板中的其他数据源结合使用。利用 Grafana 的告警规则和通知渠道，在构建变慢或失败增加时通知你的团队。

## 可用指标 {#metric-definitions}

表格列出了可读标签及其查询标识符。构建健康度查询使用 `metric` 字段中的标识符；构建和测试持续时间查询在 `series` 字段中选择 `average`、`p50`、`p90` 或 `p99`。

### 构建次数与可靠性

| 指标 | 标识符 | 测量内容 |
| --- | --- | --- |
| 构建次数 | `builds` | 记录的构建数量。 |
| 成功构建 | `successful_builds` | 成功完成的构建。 |
| 失败构建 | `failed_builds` | 失败的构建。 |
| 已取消构建 | `cancelled_builds` | 记录为已取消的构建。请参阅[构建系统差异](#build-systems)。 |
| 构建成功率 | `success_rate` | 成功 ÷ (成功 + 失败)，以百分比表示。 |
| 失败或缓慢构建 | `builds_needing_attention` | 失败或缓慢的构建，每次构建只计数一次。 |

### 构建和测试持续时间

| 指标 | 标识符 | 测量内容 |
| --- | --- | --- |
| 平均持续时间 | `average` | 所选运行的平均持续时间。 |
| 中位持续时间 | `p50` | 运行持续时间的第 50 百分位数。 |
| 第 90 百分位持续时间 | `p90` | 90% 的运行持续时间处于或低于该值。 |
| 第 99 百分位持续时间 | `p99` | 99% 的运行持续时间处于或低于该值。 |
| 缓慢构建阈值 | `slow_build_threshold` | 第 90 百分位持续时间，或以毫秒为单位的固定限制。 |

测试持续时间指标使用 Tuist 中记录的测试运行。缓慢构建阈值仅适用于构建：当构建持续时间超过该阈值时，视为构建缓慢。已取消的构建单独计数，并从构建成功率中排除。

### 缓存节省

| 指标 | 标识符 | 测量内容 |
| --- | --- | --- |
| 累计任务时间节省（Gradle） | `cache_work_avoided` | 缓存命中避免的估计任务执行时间总和。 |
| 报告累计任务时间的构建 | `cache_work_avoided_samples` | 具有完整估计值的构建。 |
| 报告的缓存节省时间 | `cache_time_saved` | 报告的实际节省时间总和。 |
| 报告缓存节省时间的构建 | `cache_time_saved_samples` | 具有有效节省值的构建。 |

Gradle 插件会自动报告本地和远程任务缓存命中所避免的估计工作量。对于每个缓存任务，它从 Gradle 存储的原始执行时间中减去任务的恢复持续时间，最小值为零。构建估计值将这些值相加。并行任务可能会重叠，因此这是累计任务时间，而非节省的实际构建时间。最新任务和跳过的任务被排除在外。

没有任务缓存命中的构建报告为零。如果任何缓存任务缺少其原始计时、遥测数据不完整或自定义元数据映射没有空间，插件将省略该估计值。旧版本的插件和其他构建系统不报告此数据。将报告数量与总构建数进行比较以检查覆盖率。

报告的实际节省时间来自 `tuist.cache_time_saved_ms` 元数据。此指标与自动估计值保持独立。

当没有构建报告缓存节省时，该值无效。Once 目前不记录此测量值。通过此数据源无法获取缓存命中率和未命中率。

### 表格

这些标识符是查询的 `queryType` 字段的值。

| 表格 | 查询类型 | 内容 |
| --- | --- | --- |
| 按工作负载划分的健康状况 | `buildWorkloads` | 构建次数、成功率、中位数和第 90 百分位持续时间。 |
| 失败类别 | `buildFailureReasons` | 所有失败及其按失败类别统计的数量。 |
| 最近的失败构建 | `buildRecentFailures` | 最新的 100 次失败，带有指向 Tuist 的链接。 |

最近的失败包括开始时间、持续时间、用户、分支和请求的任务。失败类别为 `verification`、`infrastructure_tooling` 和 `unknown`。

工作负载摘要和分支/工作负载值列表最多返回 1000 个值。构建健康度变量查询使用过去 90 天的数据；遗留的 Gradle 变量查询保留其现有的历史窗口。Bazel 显示工具报告的构建用户。其他集成显示与报告凭据关联的帐户。历史 Bazel 和 Once 运行，以及使用项目凭据报告的 Once 运行，在未记录用户时显示为“未知”。

在“构建运行”上使用“失败类别”过滤器来查找匹配的失败。该类别出现在构建详细信息中，并附有解释其含义的信息提示；默认概览和“构建运行”表保留其现有列。成功、已取消和未完成的构建没有失败类别。Gradle 的“缓存分析”卡片和构建详细信息显示“累计任务时间节省”；工具提示解释了估计值以及并行任务的影响。缓存小部件使用相同的过滤器，将所选范围与紧接的前一个等长时期进行比较。比较是中性的：较大的总数可能反映更多的构建。缺少之前的估计值时不显示比较；记录的零基线显示绝对增加量而非百分比。

## 标准仪表板 {#what-you-can-query}

导入[构建健康度仪表板](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json)，然后选择你的数据源和项目。它包括构建次数、成功率、中位数和第 90 百分位持续时间、缓慢构建阈值、中性的失败或缓慢构建计数、分组的缓存节省和报告覆盖率，以及三个失败和工作负载表格。根据需要为其他可用指标添加面板。自动缓慢阈值是所选周期自身的第 90 百分位数；高于该阈值的构建不一定表明回归。为持续时间目标告警设置固定阈值。缓存面板优先显示 Gradle 的自动累计任务时间估计值及其覆盖率，其次是明确报告的实际节省时间及其各自的覆盖率。

## 构建系统 {#build-systems}

构建健康度查询和标准仪表板支持 Bazel、Once、Gradle 和 Xcode。Tuist 从你的项目中选择构建系统。混合项目目前不受构建健康度查询或标准仪表板支持。

| 构建系统 | 工作负载 | 取消报告 | 缓存节省 |
| --- | --- | --- | --- |
| Bazel | 命令 | 退出代码 8，除了 `run` | 需要自定义元数据 |
| Once | 命令类型 | 记录的取消原因 | 未记录 |
| Gradle | 任务组 | 报告的取消 | 自动避免工作估计；实际节省时间需要自定义元数据 |
| Xcode | 方案 | 未区分；计数为零 | 需要自定义元数据 |

处理记录和未完成的运行被排除。Bazel 包括构建、测试、运行和覆盖率命令。Once 包括已完成的构建、测试和通用运行。

Gradle 将任务分组为插桩测试、单元测试、lint/检查、组装/打包或其他，按此优先级顺序。每个构建属于一个工作负载。自定义元数据可以覆盖 Xcode、Bazel 和 Gradle 的工作负载。

### 失败类别

| 类别 | 含义 | 记录的证据 |
| --- | --- | --- |
| `verification` | 代码编译、链接、测试或检查失败。 | Gradle 验证或编译异常以及已知失败的任务类型；Xcode 编译器和链接器问题；Bazel 结构化的非零编译器/测试操作结果；Once 测试失败或明确声明为编译、链接、测试、lint 或检查的失败操作。 |
| `infrastructure_tooling` | 由于工具、依赖项或环境失败，构建无法正常进行。 | Gradle 配置、依赖解析、输入/输出或内存失败；Bazel 结构化基础设施故障和[文档化的退出代码](https://bazel.build/run/scripts)；Once 基础设施操作错误。 |
| `unknown` | 报告没有足够的证据来对失败进行分类。 | 任意命令、缺少诊断信息以及没有结构化证据的旧报告。 |

Gradle 配置阶段失败（包括构建脚本中的错误）被归类为基础设施/工具，因为任务执行无法继续。

显式的 `tuist.failure_category` 元数据会覆盖自动分类。否则，当构建中同时出现基础设施和验证证据时，基础设施证据优先。失败的任意脚本不被假定为编译器或测试失败。历史报告可以使用 Tuist 已存储的证据，但新的报告字段不会回填缺失的信息。自动报告元数据使用现有 20 条目自定义元数据限制内的可用空间。

`buildFailureReasons` 响应保留其 `all` 行以保持兼容性。标准仪表板将该总数从“失败类别”图表中过滤掉，并单独显示总失败数。遗留的 `gradleFailureReasons` 查询保留其原始的三个类别行。

## 查询选项 {#query-options}

数值查询使用这些 `queryType` 值：

| 查询 | 查询类型 |
| --- | --- |
| 构建健康度 | `buildHealth` |
| Xcode 构建持续时间 | `buildDuration` |
| 测试持续时间 | `testDuration` |

`resultMode` 字段控制结果的返回方式：

| 结果 | 值 | 行为 |
| --- | --- | --- |
| 时间序列 | `series` | 每个间隔一个值。 |
| 整个周期 | `total` | 根据范围内的所有运行计算出的一个值。 |

过滤器标签映射到这些查询字段：

| 过滤器 | 查询字段 | 适用于 |
| --- | --- | --- |
| 环境 | `environment` | 所有查询 |
| 分支 | `gitBranch` | 构建健康度查询和表格 |
| 工作负载 | `workload` | 构建健康度查询和表格 |
| 状态 | `status` | 构建健康度查询、表格和 Xcode 持续时间 |
| 方案 | `scheme` | Xcode 构建和测试持续时间 |
| 配置 | `configuration` | Xcode 构建持续时间 |
| 构建类型 | `category` | Xcode 构建持续时间 |

环境值为 `any`、`ci`（自动构建）和 `local`。状态值为 `success`、`failure`，对于构建健康度查询还包括 `cancelled`；省略该值以包含所有状态。构建类型值为 `clean` 和 `incremental`；省略该值以同时包含两者。

空的构建健康度间隔计数为零，且没有平均持续时间、持续时间百分位数或成功率值。慢构建阈值仍使用所选的完整范围。单独的测试持续时间查询对空时间序列间隔返回零。整个周期的百分位数是根据运行计算的，而不是根据间隔百分位数计算的。构建健康度百分位数使用精确聚合；单独的 Xcode 和测试持续时间查询使用近似百分位数。

构建健康度时间序列在所选范围的起始处放置一个部分的首个桶，以保持其可见性。遗留的 Gradle 查询保留其原始的桶时间戳。

所有查询接受最多 366 天的日期范围。它们的边界和时间戳有所不同：

| 查询 | 使用的时间戳 | 范围边界 |
| --- | --- | --- |
| 构建健康度：Xcode、Bazel、Gradle | 记录插入时间 | 包含起始，排除结束 |
| 构建健康度：Once | 运行开始时间 | 包含起始，排除结束 |
| Xcode 构建持续时间 | 记录插入时间 | 排除起始和结束 |
| 测试持续时间 | 记录的运行时间 | 包含起始和结束 |

### 仪表板变量

对项目和支持的过滤器使用仪表板变量。分支和工作负载变量使用以下查询：

| 变量 | 查询 |
| --- | --- |
| 分支 | `buildBranches account/project` |
| 工作负载 | `buildWorkloads account/project` |

过滤器接受一个精确值。对于分支和工作负载变量，将“全部”选项的自定义值设置为 `__tuist_all__`。其他过滤器使用其内置的“任意”选项或空值。不支持多选和正则表达式。

## 报告自定义元数据 {#custom-metadata}

Xcode、Bazel 和 Gradle 构建接受以下可选元数据值：

| 键 | 接受的值 |
| --- | --- |
| `tuist.workload` | 替换默认分组的工作负载名称。 |
| `tuist.failure_category` | `verification` 或 `infrastructure_tooling`。 |
| `tuist.cache_work_avoided_ms` | 仅限 Gradle。自动报告的工作避免估算值，以整数毫秒为单位，最多 365 天。 |
| `tuist.cache_time_saved_ms` | 0 到 31,536,000,000（365 天）之间的整数毫秒数。 |

通过你的构建集成的自定义元数据配置提供这些值：

```json
{
  "custom_metadata": {
    "values": {
      "tuist.workload": "Release verification",
      "tuist.failure_category": "verification",
      "tuist.cache_time_saved_ms": "12000"
    }
  }
}
```

仅当你有该构建的耗时测量值或有文档记录的估算值时，才报告缓存节省。当任务并发运行时，仅凭缓存命中和累积任务持续时间无法确定耗时节省。缺失的缓存节省保持未知状态。缺失的失败类别元数据会回退到记录的证据，如 [构建系统](#build-systems) 中所述。数据保留策略不变。

## 警报和 Slack {#alerts-and-slack}

使用数值指标创建由 Grafana 管理的警报规则。例如：

| 指标 | 标识符 | 示例条件 |
| --- | --- | --- |
| 构建成功率 | `success_rate` | 低于 99% |
| 失败的构建 | `failed_builds` | 高于零 |
| 第 90 百分位持续时间 | `p90` | 高于团队的持续时间限制 |

使用 **整个周期** 获取评估窗口内的单个值，或将时间序列缩减为单个值。对于处于整个周期模式的持续时间查询，选择一个序列。

- 使用固定的项目和过滤器值。在后台警报评估期间，仪表板变量不可用。
- 对警报使用数值查询。要监控工作负载，请将构建健康度查询过滤到该工作负载。
- 为没有构建或报告缓存节省的间隔设置规则的无数据行为。

配置 [Slack 联系人](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) 并通过 Grafana 的通知策略将规则路由到它。Grafana 发送通知并存储 Slack 凭据。

## 升级现有仪表板 {#upgrading}

现有的持续时间表盘保留其查询、过滤器、序列名称和单位。已保存的 Gradle 健康度表盘和变量也继续有效。

单独导入标准仪表板以使用共享的构建健康度查询。现有仪表板不会自动迁移。共享查询需要提供支持构建健康度端点的 Tuist 服务器；现有的持续时间查询仍可与较旧的服务器配合使用。

## 要求 {#requirements}

- Grafana 10.4 或更高版本。
- 具有读取你要绘制图表的项目和指标权限的 Tuist 令牌。请参阅下面的 [身份验证](#authentication)。

## 身份验证 {#authentication}

使用 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link> 进行仪表板和后台警报评估。授予 `project:builds:read` 以获取构建指标，授予 `project:tests:read` 以获取测试持续时间，并将访问权限限制为你要绘制图表的项目。仅需你使用的指标所需的范围。按照 <.localized_link href="/guides/server/authentication#creating-an-account-token">令牌创建说明</.localized_link> 生成一个令牌。

该集成还接受用于其自身项目的现有项目令牌，以及具有用户读取权限的 <.localized_link href="/guides/server/authentication#as-a-user">用户访问令牌</.localized_link>。用户访问令牌是短期的。Grafana 存储你提供的令牌，不会刷新它或重用你的本地 Tuist 登录；请在令牌过期时更换它。账户令牌让你能够独立于用户的登录会话来控制项目访问、权限和过期时间。

## 配置 {#configuration}

添加数据源并设置：

| 字段 | 保存的设置 | 备注 |
| --- | --- | --- |
| 服务器 URL | `jsonData.url` | 默认为 `https://tuist.dev`。 |
| 令牌 | `secureJsonData.apiToken` | Tuist Bearer 令牌，加密存储。 |

选择 **保存并测试** 以检查连接。Grafana 会列出可访问的项目，然后针对第一个项目检查构建和测试的读取权限。

## 安装 {#installation}

### 从 Grafana 目录安装 {#from-the-grafana-catalog}

发布后，像其他数据源一样从 **连接 → 添加新连接 → Tuist** 安装，或使用 `grafana-cli plugins install tuist-metrics-datasource` 安装。

### 在发布之前（自托管 Grafana）{#before-it-is-published-self-hosted-grafana}

该插件在获得目录批准之前处于未签名状态。在自托管实例上，你可以：

- **允许未签名加载** — 将 `tuist-metrics-datasource` 添加到 `allow_loading_unsigned_plugins`（或 `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`），并将构建好的插件放入你的插件目录。
- **为你的实例私有签名** — `npm run sign -- --rootUrls https://grafana.example.com`（URL 必须与实例的 `root_url` 匹配），然后分发 zip 文件。

[Grafana Cloud 要求使用目录中的插件](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/)，不支持未签名或手动上传的插件。
