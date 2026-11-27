---
{
  "title": "Struo 远程执行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 远程执行工作节点上运行符合条件的 Struo 图命令操作。"
}
---
# Struo 远程执行 {#struo-remote-execution}

<a id="once-remote-execution"></a>

共享缓存可避免重复其他机器已完成的工作。远程执行还能将符合条件的缓存未命中任务从你的计算机转移出去：Struo 会在 Tuist 的一次性 Linux 工作器上调度图命令操作，并通过相同的项目缓存检索其输出。

> [!NOTE]
> 远程执行目前仅限受邀用户。[联系我们](mailto:contact@tuist.dev)以申请为你的账户开通访问权限。

> [!IMPORTANT]
> **要求**
>
> - 一个已启用远程执行并具备可用执行容量的 Tuist 账户。
> - 支持 Tuist 远程执行的 Struo 版本。
> - 一个兼容的服务器，需通告工作器镜像、缓存端点、并发度以及绝对执行目录。省略该目录的服务器与当前 Struo 客户端不兼容；Struo 会在上传工作前停止。
> - 能够在通告的工作器镜像内的 `linux/amd64` 上运行的命令和工具链。

这仅运行图操作，而非整个 CI 作业。配置 Struo 不会安装 GitHub 或 GitLab 工作流编排。

## 设置 {#setup}

完成<.localized_link href="/guides/get-started/struo-project">开始使用 Struo</.localized_link>。为缓存和执行选择相同的 Tuist 提供商，并固定服务通告的工作器镜像：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

使用能够读写项目缓存的凭据进行身份验证，然后请求远程执行：

```bash
struo build --remote MyTarget
```

将目标和镜像标签替换为你自己的值。Struo 会在上传工作前检查通告的镜像、执行目录、缓存目标以及账户容量。缓存和执行必须指向同一个项目。

## 为工作器准备操作 {#prepare-actions-for-workers}

- 声明输入和输出。输出必须保留在操作的工作目录之下。
- 在工作器镜像内解析工具，而不是在发起计算机上使用绝对路径。
- 使用可安全重复执行的操作：工作器故障或服务重启可能导致再次执行。
- 将超时控制在服务的十分钟操作限制内。不支持的要求（包括网络拒绝）会失败，而不会静默地在本地运行。

Struo 遵循账户通告的操作并发度，并在服务队列已满时退避。更改镜像会将构建配置与缓存结果分离，防止在不兼容的工作器镜像之间复用。

## 检查远程执行 {#inspect-remote-execution}

项目侧边栏包含一个**远程执行**页面。其**分析**卡片显示所选时间段内的执行次数和总执行时间，如<.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">运行操作与用量</.localized_link>中所述。在 2.19.0 之后的 Struo 版本中，每个远程操作都会标明其所属的 Struo 运行，因此该页面还会绘制队列时间和执行时间的图表，并列出各运行及其远程操作、结果和耗时，正在运行的运行排在前面。点击某个运行会在**构建运行**中打开其页面。来自旧版客户端的运行以及由远程缓存响应的操作不计入其中。当前正在运行和排队的远程操作可通过 `get_remote_execution_activity` MCP 工具及其 REST 端点获取。两者均来自执行服务，而非工作器通道。

参阅[Struo 远程执行指南](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)了解排队、身份验证刷新和缓存端点覆盖。按照<.localized_link href="/guides/features/build-insights/struo">Struo 构建洞察</.localized_link>检查生成的运行。
