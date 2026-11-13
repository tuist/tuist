---
{
  "title": "Bazel 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 在团队和 CI 之间共享 Bazel 远程缓存条目。"
}
---
# Bazel 缓存 {#bazel-cache}

Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可将其作为远程缓存连接。当某个操作的输出已存在于缓存中时，Bazel 会跳过该操作并从 Tuist 的缓存中拉取结果，从而为团队和 CI 环境节省编译时间。

## 设置 {#setup}

在 Bazel 工作区的根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁写入一个 `.bazelrc.tuist` 文件，连接到最近的 Tuist 缓存区域，并通过每个工作区的凭据助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你希望自行管理导入，请传递 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore` 中，并在每台机器上运行设置，而不是提交该文件。生成的文件指向当前用户 Tuist 配置目录下的绝对凭据助手路径，以及距离生成该文件的机器最近的缓存区域，因此这两个值都不会传递给队友或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 行，该行在每台机器上都相同。

当找不到 Bazel 工作区标记、文件是符号链接，或已经配置了远程缓存或 Build Event Service 时，设置会保留现有的 `.bazelrc` 不变。这样，再次运行它是幂等的。

运行一个普通的 Bazel 命令来验证集成：

```bash
bazel build //...
```

缓存活动随后会显示在 Tuist 仪表板的项目 **Bazel Cache** 页面上，其中显示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 会提供相同的操作缓存命中率摘要，并与构建时长并列显示。

要查看某个命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，因此你可以区分冷操作缓存和缓慢的构件下载。

## 远程执行 {#remote-execution}

Tuist 还可以在其 Linux 执行器上运行你的 Bazel 操作，因此缓存未命中将在远程运行，而不是在本地机器或 CI 运行器上运行。向设置传递 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

设置随后会在 `.bazelrc.tuist` 中将 Bazel 指向 Tuist 的执行器，位于远程缓存旁边。每次运行时都会查找当前的执行器和镜像，因此请重新运行设置，而不是复制生成的值。操作使用执行器的 Linux 工具链运行，而不是你机器上安装的工具，因此请在工作区中声明你的操作所需的工具链。

设置还将 `--jobs` 设置为你的账户可以同时运行的远程操作数量的两倍，以便每个操作都有下一个操作等待执行。否则，Bazel 会并行运行与机器核心数一样多的操作，而 2 核 CI 运行器只能保持两个远程操作处于进行中状态。

要使用不同的值，请在命令行上传递 `--jobs`，或在 `try-import` 行之后在 `.bazelrc` 中设置它。Bazel 使用它读取的最后一个值，因此该行之前的 `--jobs` 将被生成的值替换。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便已完成的命令显示在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不希望发送构建事件流，请使用以下命令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一种方法对 CI 进行身份验证，然后作为检出步骤的一部分运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器的正确区域。有关特定提供商的示例，请参阅 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>。

## 数据保留 {#data-retention}

Tuist 保留远程缓存观察数据 90 天。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
