---
{
  "title": "Bazel 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 在团队和 CI 之间共享 Bazel 远程缓存条目。"
}
---
# Bazel 缓存 {#bazel-cache}

Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可将其作为远程缓存连接。当某个操作的输出已存在于缓存中时，Bazel 会跳过该操作并从 Tuist 的缓存中拉取结果，从而为团队和 CI 环境节省编译时间。如需配置 GitHub Actions，请参阅 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解远程缓存的工作原理以及自建缓存与托管缓存的对比，请参阅 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 设置 {#setup}

在 Bazel 工作区的根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁写入一个 `.bazelrc.tuist` 文件，连接到距离最近的 Tuist 缓存区域，并通过每个工作区独立的凭据助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果希望自行管理导入，请传入 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore`，并在每台机器上运行设置，而不是将其提交到版本控制。生成的文件指向当前用户 Tuist 配置目录下的绝对凭据助手路径，以及距离生成该文件的机器最近的缓存区域，因此这两个值都不会传递给团队成员或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 行，它在每台机器上都相同。

当无法找到 Bazel 工作区标记、文件是符号链接，或已配置远程缓存或 Build Event Service 时，设置会保留现有的 `.bazelrc` 不变。这样，再次运行它是幂等的。

运行一个普通的 Bazel 命令来验证集成：

```bash
bazel build //...
```

随后，缓存活动会出现在 Tuist 仪表板中项目的 **Bazel Cache** 页面上，该页面显示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 会提供相同的操作缓存命中率摘要，并与构建时长并列显示。

要查看某个命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，因此你可以区分冷操作缓存和缓慢的构件下载。

## 远程执行 {#remote-execution}

Tuist 还可以在其 Linux 执行器上运行你的 Bazel 操作，因此缓存未命中会在远程运行，而不是在本地机器或 CI 运行器上运行。远程执行适用于已启用的账户；请 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 以为你的账户启用。然后将 `--remote-execution` 传给设置：

```bash
tuist bazel setup --remote-execution
```

设置随后在 `.bazelrc.tuist` 中将 Bazel 指向 Tuist 的执行器，位于远程缓存旁边。每次运行时都会查找当前的执行器和镜像，因此请重新运行设置，而不是复制生成的值。操作使用执行器的 Linux 工具链运行，而不是你机器上安装的工具，因此请在工作区中声明你的操作所需的工具链。

设置还将 `--jobs` 设置为你的账户可以同时运行的远程操作数量的两倍，以便每个操作都有下一个操作等待执行。否则，Bazel 会并行运行与机器核心数一样多的操作，而一个 2 核心的 CI 运行器只能同时保持两个远程操作在执行中。

要使用不同的值，请在命令行上传入 `--jobs`，或在 `try-import` 行之后的 `.bazelrc` 中设置它。Bazel 使用它读取的最后一个值，因此该行之前的 `--jobs` 会被生成的值替换。

### 执行器规格 {#executor-sizes}

操作默认使用 4 GB 内存和 2 个 vCPU。设置 `tuist-memory-gb` 执行属性以请求更大的虚拟机：

| `tuist-memory-gb` | 内存 | vCPU | 工作区磁盘 |
| --- | --- | --- | --- |
| `4`（默认） | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

例如，在 `.bazelrc` 中的 `try-import` 行 **之后** 添加以下内容，以默认请求 8 GB：

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

对于单个目标，请在其 Bazel 规则中使用 `exec_properties = {"tuist-memory-gb": "8"}`。仅支持 `4`、`8` 和 `16`。较大的操作会按比例消耗更多账户分配的 vCPU 和内存限额，从而减少可以同时运行的数量。规格必须同时符合这两项限额。生成的 `--jobs` 使用默认规格；如果需要请求更大规格，请根据需要覆盖它。

执行器目前使用 Tuist 的 Linux amd64 镜像。任意容器镜像、其他执行操作系统和架构、持久化操作工作器以及自带执行器无法通过设置进行配置。请重新运行设置以获取当前镜像和端点。

### 正在运行的操作和使用情况 {#running-actions-and-usage}

项目的 **Remote execution** 页面显示当前正在运行的内容和已运行的内容：

- **Invocations** 首先列出正在运行的 Bazel 调用，每五秒刷新一次，显示每个调用的运行时长以及其远程操作中正在运行和排队的数量。一旦 Kura 获取到其目标模式，调用就会出现，并一直保留直到其完成报告到达。打开一个调用会显示其 **Executions**：其正在虚拟机中执行或等待虚拟机的远程操作，包括每个操作的助记符、目标、机器规格以及当前状态下的耗时。执行网关在预先准备的虚拟机上运行的操作在运行期间不会列出；它们的计时信息会在调用完成后出现。当你搜索或过滤列表时，不会显示正在运行的调用。
- **Analytics** 以所选期间的 **Executions** 和 **Total execution time** 开头，并显示与上一周期相比的变化，按机器规格绘制图表。总执行时间是每个操作的执行器在其虚拟机中运行的时长，包括获取输入和上传输出，但不包括排队或准备虚拟机的时间。这是 **Usage** 页面计费的时间。从缓存提供的结果不计为执行。

相同的数据可从 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 和 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`（可选的 `from` 和 `to`，默认为最近 30 天，最多跨越 366 天）以及 `get_remote_execution_activity` 和 `get_remote_execution_usage` MCP 工具获取。

### 远程操作计时 {#remote-action-timings}

**Analytics** 的其余部分和 **Invocations** 表格涵盖具有已记录远程阶段的操作：平均队列和执行时间以及 p50/p90/p99 值，并显示与上一周期相比的变化、趋势图，以及指向每个调用阶段计时的链接。按日期过滤（最多 90 天）。调用表格显示每个调用的平均、p50 和 p90 执行时间。你可以按命令、目标或调用 ID 搜索，按状态、命令、目标或远程操作数量过滤，并按除 Invocation 之外的任何列排序。搜索和表格过滤器仅适用于调用表格，不适用于分析数据。

打开调用的 **Remote execution** 选项卡以查看其 **Executions**，即按持续时间（从长到短）或开始时间排序的远程操作：每个远程操作占一行，显示其相对于性能分析文件的开始时间、持续时间，以及一个分为排队、输入获取、执行和输出上传时间的条形图，该条形图按比例缩放至页面上最长的操作。将鼠标悬停在条形图上可查看每个阶段的持续时间。该表格使用上传的 Bazel 性能分析文件，并仅将服务器阶段与同一性能分析线程中明确的操作关联起来。

缺少计时信息表示 **Not recorded**，而非零。较旧的性能分析文件、缺失的操作间隔以及被 Bazel 省略的短阶段可能导致表格为空，即使发生了远程工作。记录的重试会在每个操作中累加。服务器元数据可以描述缓存结果，因此这些计时既不能证明是全新执行，也不代表可计费的使用量。客户端输入上传和本地执行输出的上传不计入输出上传时间。

相同的数据可从带有 `remote_execution=true` 的构建步骤 REST 端点以及 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具获取。计时信息与性能分析步骤一起保留 90 天。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便已完成的命令出现在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不希望发送构建事件流，请使用以下命令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一种方法对 CI 进行身份验证，然后在检出步骤中运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器的正确区域。有关特定提供商的示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>。

## 数据保留 {#data-retention}

Tuist 将远程缓存观察数据保留 90 天。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
