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

在 Bazel 工作区根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁写入一个 `.bazelrc.tuist` 文件，连接到最近的 Tuist 缓存区域，并通过每个工作区的凭据助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果希望自行管理导入，请传入 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore`，并在每台机器上运行 setup，而不是将其提交到版本控制。生成的文件指向当前用户 Tuist 配置目录下的绝对凭据助手路径，以及生成该文件的机器所对应的最近缓存区域，因此这两个值都不会传递给团队成员或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 这一行，它在每台机器上都相同。

当找不到 Bazel 工作区标记、文件是符号链接，或已配置远程缓存或 Build Event Service 时，setup 不会修改现有的 `.bazelrc`。这样再次运行它是幂等的。

运行一个普通的 Bazel 命令来验证集成：

```bash
bazel build //...
```

随后，缓存活动会显示在 Tuist 仪表板中项目的 **Bazel Cache** 页面上，其中展示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 会提供相同的操作缓存命中率摘要，并与构建时长并列显示。

要查看某条命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，以便你区分冷操作缓存与缓慢的构件下载。

## 远程执行 {#remote-execution}

Tuist 还可以在其 Linux 执行器上运行你的 Bazel 操作，因此缓存未命中会在远程运行，而不是在本地机器或 CI 运行器上运行。远程执行适用于已启用的账户；请 [email us](mailto:contact@tuist.dev) 或 [book a call](https://cal.tuist.dev/team/tuist/tuist) 为你的账户启用。然后向 setup 传入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

随后，setup 会在 `.bazelrc.tuist` 中将 Bazel 指向 Tuist 的执行器，与远程缓存并列。每次运行时它都会查找当前的执行器和镜像，因此请重新运行 setup，而不是复制生成的值。操作使用执行器的 Linux 工具链运行，而不是你机器上安装的工具，因此请在工作区中声明你的操作所需的工具链。

Setup 还会将 `--jobs` 设置为你的账户可同时运行的远程操作数量的两倍，以便每个操作都有下一个操作等待执行。否则，Bazel 会并行运行与机器核心数一样多的操作，而一个 2 核的 CI 运行器只能同时保持两个远程操作在执行中。

要使用不同的值，请在命令行上传入 `--jobs`，或在 `try-import` 行之后的 `.bazelrc` 中进行设置。Bazel 使用它读取的最后一个值，因此该行之前的 `--jobs` 会被生成的值替换。

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

对于单个目标，请在其 Bazel 规则中使用 `exec_properties = {"tuist-memory-gb": "8"}`。仅支持 `4`、`8` 和 `16`。更大的操作会按比例消耗更多账户分配的 vCPU 和内存限额，从而减少可同时运行的数量。一个规格必须同时满足这两项限额。生成的 `--jobs` 使用默认规格；在请求更大规格时，如有需要可覆盖它。

执行器目前使用 Tuist 的 Linux amd64 镜像。任意容器镜像、其他执行操作系统和架构、持久化操作工作器以及自带执行器无法通过 setup 配置。请重新运行 setup 以获取当前的镜像和端点。

### 远程操作耗时 {#remote-action-timings}

在项目侧边栏中打开 **Remote execution**，查看包含已记录远程阶段的调用和操作、平均及 p50/p90/p99 排队和执行时间（含相较于上一周期的变化）、趋势图，以及指向每个调用阶段耗时的链接。按环境（CI 或本地）和日期（最多 90 天）进行过滤。调用表显示每个调用的平均、p50 和 p90 执行时间。可按命令、目标或调用 ID 搜索，按状态、命令、目标或远程操作数量过滤，并按除 Invocation 外的任何列排序。搜索和表格过滤器仅适用于调用表，不适用于分析数据。

打开某个调用的 **Remote execution** 标签页，查看其远程操作，按持续时间（最长优先）或开始时间排序：每个远程操作占一行，显示其相对于性能分析文件的开始时间、持续时间，以及分为排队、输入获取、执行和输出上传时间的条形图，并按页面上最长的操作进行缩放。将鼠标悬停在条形图上可查看每个阶段的持续时间。该表使用上传的 Bazel 性能分析文件，并仅将服务器阶段与同一性能分析线程中明确的操作关联。

缺失的耗时表示 **Not recorded**，而非零。较旧的性能分析文件、缺失的操作间隔以及被 Bazel 省略的短阶段可能导致表格为空，即使发生了远程工作。记录的重试会在每个操作中累加。服务器元数据可能描述缓存结果，因此这些耗时既不能证明是全新执行，也不代表可计费用量。客户端输入上传和本地执行输出的上传不计入输出上传时间。

相同的数据可通过构建步骤 REST 端点获取，需传入 `remote_execution=true`，并使用 `list_bazel_build_steps` / `get_bazel_build_step` MCP 工具。耗时数据会与性能分析步骤一起保留 90 天。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便已完成的命令显示在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>，了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不希望发送构建事件流，可以使用以下命令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一种方法对 CI 进行身份验证，然后在检出步骤中运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器所在的正确区域。有关特定提供商的示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>。

## 数据保留 {#data-retention}

Tuist 将远程缓存观测数据保留 90 天。完整政策请参阅 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
