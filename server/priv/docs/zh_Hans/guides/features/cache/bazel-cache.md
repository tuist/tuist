---
{
  "title": "Bazel cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel remote cache entries across your team and CI with Tuist."
}
---
# Bazel 缓存 {#bazel-cache}

Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可以将其作为远程缓存进行连接。当某个操作的输出已存在于缓存中时，Bazel 会跳过该操作并从 Tuist 的缓存中拉取结果，从而节省团队和 CI 环境中的编译时间。

## 设置 {#setup}

在 Bazel 工作区的根目录下运行：

```bash
tuist bazel setup
```

这会在你的 `.bazelrc` 旁边写入一个 `.bazelrc.tuist` 文件，该文件连接到最近的 Tuist 缓存区域，并通过每个工作区的凭证助手进行身份验证。它还会在你的仓库的 `.bazelrc` 中添加一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理导入，请传递 `--no-add-bazelrc-import`。

将 `.bazelrc.tuist` 添加到你的 `.gitignore` 中，并在每台机器上运行设置，而不是提交该文件。生成的文件指向当前用户 Tuist 配置目录下的绝对凭证助手路径，以及生成该文件的机器最近的缓存区域，因此这两个值都不会传递给团队成员或持续集成运行器。请在 `.bazelrc` 中提交 `try-import` 行，这在每台机器上都是相同的。

当无法找到 Bazel 工作区标记、文件是符号链接，或者已经配置了远程缓存或 Build Event Service 时，设置会保留现有的 `.bazelrc` 不变。这样，再次运行它是幂等的。

运行正常的 Bazel 命令以验证集成：

```bash
bazel build //...
```

缓存活动随后会显示在 Tuist 仪表板的项目 **Bazel Cache** 页面上，其中显示缓存传输、下载和上传、读写延迟、吞吐量以及操作缓存命中率。项目 **Overview** 包含相同操作缓存命中率的摘要以及构建持续时间。

要查看某个命令如何使用缓存，请从 **Invocations** 中打开它。调用页面将操作缓存查找与内容对象请求分开，因此你可以区分冷操作缓存和慢速构件下载。

## 构建洞察 {#build-insights}

默认情况下，`tuist bazel setup` 还会配置 Bazel 的 Build Event Service，以便已完成的命令显示在 **Invocations** 仪表板上。请参阅 <.localized_link href="/guides/features/build-insights/bazel">Bazel 构建洞察</.localized_link> 了解仪表板显示的内容以及如何附加自定义元数据。

如果你只想要远程缓存而不想发送构建事件流，请使用以下命令退出：

```bash
tuist bazel setup --no-build-insights
```

## 持续集成 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">身份验证指南</.localized_link> 中的一种方法对 CI 进行身份验证，然后作为检出步骤的一部分运行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映运行器的正确区域。请参阅 <.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link> 获取特定于提供商的示例。

## 数据保留 {#data-retention}

Tuist 保留远程缓存观察数据 90 天。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">数据保留</.localized_link>。
