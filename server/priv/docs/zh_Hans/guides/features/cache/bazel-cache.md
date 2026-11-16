---
{
  "title": "Bazel 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 在团队和 CI 之间共享 Bazel 远程缓存条目。"
}
---
# Bazel 缓存 {#bazel-cache}

Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可将其作为远程缓存连接。当某个操作的输出已存在于缓存中时，Bazel 会跳过该操作并从 Tuist 的缓存中拉取结果，从而为你的团队和 CI 环境节省编译时间。如需配置 GitHub Actions，请参阅 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。要了解远程缓存的工作原理以及自托管缓存与托管缓存的对比，请参阅 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 设置 {#setup}

在 Bazel 工作区的根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁写入一个 `.bazelrc.tuist` 文件，连接到距离最近的 Tuist 缓存区域，并通过每个工作区独立的凭据助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你希望自行管理导入，请传入 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore` 中，并在每台机器上运行设置，而不是提交该文件。生成的文件指向当前用户 Tuist 配置目录下的绝对凭据助手路径，以及距离生成该文件的机器最近的缓存区域，因此这些值不会传递给团队成员或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 行，它在每台机器上都相同。

当找不到 Bazel 工作区标记、文件是符号链接，或已配置远程缓存或 Build Event Service 时，设置会保留现有的 `.bazelrc` 不变。这样，再次运行它是幂等的。

运行普通的 Bazel 命令以验证集成：

```bash
bazel build //...
```

缓存活动随后会出现在 Tuist 仪表板中项目的 **Bazel Cache** 页面上，显示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 会在构建时长旁边提供相同的操作缓存命中率摘要。

要查看某条命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，因此你可以区分冷操作缓存与缓慢的构件下载。

## 远程执行 {#remote-execution}

Tuist 还可以在其 Linux 执行器上运行你的 Bazel 操作，因此缓存未命中会在远程运行，而不是在本地机器或 CI 运行器上运行。远程执行按账户按需启用：[contact us](mailto:contact@tuist.dev) 以开启。启用后，向设置传入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

设置随后会将 Bazel 指向 `.bazelrc.tuist` 中的 Tuist 执行器，位于远程缓存旁边。每次运行时都会查找当前的执行器和镜像，因此请重新运行设置，而不是复制生成的值。操作使用执行器的 Linux 工具链运行，而不是你机器上安装的工具，因此请在工作区中声明你的操作所需的工具链。

设置还会将 `--jobs` 设置为你的账户可以同时运行的远程操作数量的两倍，以便每个操作都有下一个操作等待执行。否则，Bazel 会并行运行与机器核心数一样多的操作，而双核 CI 运行器只能同时保持两个远程操作在执行中。

要使用不同的值，请在命令行上传入 `--jobs`，或在 `try-import` 行之后的 `.bazelrc` 中进行设置。Bazel 使用它读取的最后一个值，因此该行之前的 `--jobs` 会被生成的值替换。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便已完成的命令出现在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>，了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不想发送构建事件流，请使用以下选项退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一种方法对 CI 进行身份验证，然后在检出步骤中运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器的正确区域。有关特定提供商的示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>。

## 数据保留 {#data-retention}

Tuist 保留远程缓存观测数据 90 天。完整政策请参阅 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
