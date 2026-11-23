---
{
  "title": "Bazel 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 在团队和 CI 之间共享 Bazel 远程缓存条目。"
}
---
# Bazel 缓存 {#bazel-cache}

Tuist 提供了一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可以将其作为远程缓存连接。当某个操作的输出已存在于缓存中时，Bazel 会跳过该操作并从 Tuist 的缓存中拉取结果，从而为团队和 CI 环境节省编译时间。如需了解 GitHub Actions 设置，请参阅 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解远程缓存的工作原理以及自托管缓存与托管缓存的比较，请参阅 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 设置 {#setup}

在 Bazel 工作区的根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁边写入一个 `.bazelrc.tuist` 文件，连接到最近的 Tuist 缓存区域，并通过每个工作区的凭据助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你希望自己管理导入，请传入 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore` 中，并在每台机器上运行设置，而不是提交该文件。生成的文件指向当前用户 Tuist 配置目录下的绝对凭据助手路径，以及离生成该文件的机器最近的缓存区域，因此这两个值都不会传递给队友或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 行，它在每台机器上都是相同的。

当无法找到 Bazel 工作区标记、文件是符号链接，或者已经配置了远程缓存或 Build Event Service 时，设置会保留现有的 `.bazelrc` 不变。这样，再次运行它是幂等的。

运行一个普通的 Bazel 命令来验证集成：

```bash
bazel build //...
```

缓存活动随后会出现在 Tuist 仪表板项目的 **Bazel Cache** 页面上，该页面显示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 提供了相同操作缓存命中率的摘要， alongside 构建持续时间。

要查看某个命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，因此你可以区分冷操作缓存和慢速构件下载。

## 远程执行 {#remote-execution}

Tuist 还可以在其 Linux 执行器上运行你的 Bazel 操作，因此缓存未命中将在远程运行，而不是在本地机器或 CI 运行器上运行。远程执行适用于已启用的账户；[email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以为你的账户启用它。然后将 `--remote-execution` 传递给设置：

```bash
tuist bazel setup --remote-execution
```

设置随后会将 Bazel 指向 `.bazelrc.tuist` 中的 Tuist 执行器，位于远程缓存旁边。每次运行时都会查找当前的执行器和镜像，因此请重新运行设置而不是复制生成的值。操作使用执行器的 Linux 工具链运行，而不是你机器上安装的工具，因此请在工作区中声明你的操作所需的工具链。

设置还将 `--jobs` 设置为你的账户可以同时运行的远程操作数量的两倍，以便每个操作都有下一个操作等待。如果没有这一点，Bazel 会并行运行与机器核心数一样多的操作，而一个 2 核心的 CI 运行器只能保持两个远程操作在进行中。

要使用不同的值，请在命令行上传入 `--jobs`，或在 `try-import` 行之后在 `.bazelrc` 中设置它。Bazel 使用它读取的最后一个值，因此该行之前的 `--jobs` 将被生成的值替换。

### 执行器大小 {#executor-sizes}

操作默认使用 2 GB 内存和 1 vCPU，这适合单线程编译操作。设置 `tuist-memory-gb` 执行属性以请求更大的 VM 用于多线程测试或内存密集型链接：

| `tuist-memory-gb` | 内存 | vCPU | 工作区磁盘 |
| --- | --- | --- | --- |
| `2`（默认） | 2 GB | 1 | 30 GB |
| `4` | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行 **之后** 添加此项以默认请求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

对于单个目标，请在其 Bazel 规则中使用 `exec_properties = {"tuist-memory-gb": "8"}`。仅支持 `4`、`8` 和 `16`。较大的操作会按比例消耗更多账户分配的 vCPU 和内存限制，减少可以同时运行的数量。形状必须同时符合这两个限制。生成的 `--jobs` 使用默认形状；如果需要请求更大的形状，请覆盖它。

执行器目前使用 Tuist 的 Linux amd64 镜像。任意容器镜像、其他执行操作系统和架构、持久操作工作器以及自带执行器无法通过设置进行配置。重新运行设置以获取当前镜像和端点。

### 运行操作和使用情况 {#running-actions-and-usage}

项目的 **Remote execution** 页面显示当前正在运行的内容和已运行的内容：

- **Invocations** 首先列出正在运行的 Bazel 调用，每五秒刷新一次，显示每个调用的运行时长以及其远程操作中正在运行和排队的数量。一旦 Kura 获得其目标模式，调用就会出现，并一直保留直到其完成报告到达。打开一个调用会显示其 **Executions**：首先是正在 VM 中执行或等待 VM 的远程操作，然后是最近完成的 50 个操作及其结果（Passed、Cached、Failed 或 Error），每个操作都有其助记符、目标、机器大小和迄今为止的持续时间。刚刚完成的操作会显示为 **Finishing**，最多持续一分钟，直到其记录到达。每一行都会打开操作的页面；当操作仍在运行时，页面显示其状态、机器和摘要，并在完成后加载完整记录。执行网关在预先准备的 VM 上运行的操作在运行时不会列出；它们会出现在已完成的操作中。当你搜索或过滤列表时，不会显示正在运行的调用。
- **Analytics** 以所选期间的 **Executions** 和 **Total execution time** 开头，显示与上一期间相比的变化以及随时间变化的图表。总执行时间是每个操作的执行器在其 VM 中运行的时间，包括获取输入和上传输出，但不包括排队或准备 VM 的时间。这是 **Usage** 页面计费的时间。从缓存提供的结果不是执行。

相同的数据可从 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可选 `from` 和 `to`，默认为最近 30 天，最多跨越 366 天）以及 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具中获得。

### 远程操作计时 {#remote-action-timings}

**Analytics** 的其余部分和 **Invocations** 表格涵盖具有记录的远程阶段的操作：平均队列和执行时间以及 p50/p90/p99，显示与上一期间相比的变化、趋势图，以及指向每个调用阶段计时的链接。按日期过滤（最多 90 天）。调用表格显示每个调用的平均、p50 和 p90 执行时间。你可以按命令、目标或调用 ID 搜索，按状态、命令、目标或远程操作数量过滤，并按除 Invocation 之外的任何列排序。搜索和表格过滤器仅适用于调用表格，不适用于分析数据。

打开调用的 **Remote execution** 选项卡以查看其 **Executions**，即按持续时间（从最长开始）或开始时间排序的远程操作：每个远程操作占一行，显示其相对于配置文件的开始时间、持续时间，以及一个分为队列、输入获取、执行和输出上传时间的条形图，该条形图按页面上最长的操作进行缩放。将鼠标悬停在条形图上可查看每个阶段的持续时间。该表格使用上传的 Bazel 配置文件，并仅将服务器阶段与同一配置文件线程上明确的操作关联起来。

缺少计时意味着 **Not recorded**，而不是零。较旧的配置文件、缺失的操作间隔以及被 Bazel 省略的短阶段可能导致表格为空，即使发生了远程工作。记录的重试会在每个操作中累加。服务器元数据可以描述缓存的结果，因此这些计时既不是新鲜执行的证明，也不是可计费的使用量。客户端输入上传和本地执行输出的上传不计入输出上传时间。

相同的数据可从带有 `remote_execution=true` 的构建步骤 REST 端点以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具中获得。计时与配置文件步骤一起保留 90 天。

### 检查远程操作 {#inspect-a-remote-action}

当 Tuist 的执行器记录一个操作时，其在调用的 **Remote execution** 选项卡中的行会链接到该操作的页面。**Overview** 显示状态和退出代码、队列、输入获取、执行和输出上传时间，操作是调度的还是在为调用租赁的工作器上运行的，以及工作器、内存、超时和操作摘要。失败的操作还会获得一个 **Errors** 卡片：在其标准错误中识别出的编译器错误（Clang、GCC、Swift、javac、Go 和 rustc 格式）按文件分组，或者在未识别出任何错误时显示其退出代码和标准错误的末尾。**Logs** 在一个带有行号的日志中显示标准输出，后跟标准错误，并高亮显示错误行。与 CI 作业日志一样，它会在末尾打开，而 **Load earlier lines** 可向前翻页。记录保留每个流的前 16 KiB；执行器还将更长的流完整存储为运行工件，因此日志和 **Errors** 卡片涵盖所有输出。超过 16 MiB 的流仅保留其前 16 KiB 和最后 16 MiB。日志中的标记显示字节缺失的位置和原因：从非常长的流中跳过，或未存储，例如副本已过期时。**Overview** 上的 **Command** 卡片显示命令行（可通过 **Copy** 复制）、工作目录和输出路径，以及折叠部分中的环境和平台属性。

名称包含 `TOKEN`、`SECRET`、`PASSWORD` 或 `KEY` 的环境变量，以及以此方式命名的标志的值，显示为 `****`。记录是尽力而为的：没有链接的行意味着没有记录明确匹配其输出，并不意味着操作在本地运行。记录保留 90 天。REST 端点 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` 和 `.../remote-actions/{operation_id}` 以及 `list_bazel_remote_actions` / `get_bazel_remote_action` MCP 工具返回相同的记录；`.../remote-actions/{operation_id}/logs/{stdout|stderr}` 和 `get_bazel_remote_action_log` 按字节范围读取日志。存储的日志副本是运行工件，并随计划的运行工件窗口过期。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便完成的命令出现在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不想发送构建事件流，请使用以下命令选择退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一种方法对 CI 进行身份验证，然后在检出步骤中运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器的正确区域。请参阅 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 获取特定于提供商的示例。

## 数据保留 {#data-retention}

Tuist 将远程缓存观察结果保留 90 天。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
