---
{
  "title": "一次性远程执行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 远程执行工作节点上运行符合条件的一次性图命令操作。"
}
---
# Once 远程执行 {#once-remote-execution}

共享缓存可以避免重复其他机器已完成的工作。远程执行还能将符合条件的缓存未命中任务从你的计算机移走：Once 会在 Tuist 的一次性 Linux 工作节点上调度图命令操作，并通过相同的项目缓存检索其输出。

> [!NOTE]
> 远程执行目前仅限受邀用户。[联系我们](mailto:contact@tuist.dev)为你的账户申请访问权限。

> [!IMPORTANT]
> **要求**
>
> - 一个已启用远程执行且具有可用执行容量的 Tuist 账户。
> - 支持 Tuist 远程执行的 Once 版本。
> - 一台兼容的服务器，需公布工作节点镜像、缓存端点、并发数以及绝对执行目录。省略该目录的服务器与当前 Once 客户端不兼容；Once 会在上传工作前停止。
> - 能够在公布的 worker 镜像内的 `linux/amd64` 上运行的命令和工具链。

这只会运行图操作，而非整个 CI 作业。配置 Once 并不会安装 GitHub 或 GitLab 工作流编排。

## 设置 {#setup}

完成<.localized_link href="/guides/get-started/once-project">开始使用 Once</.localized_link>。为缓存和执行选择相同的 Tuist 提供商，并固定服务公布的工作节点镜像：

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
once build --remote MyTarget
```

将目标和镜像标签替换为你自己的值。Once 会在上传工作前检查公布的镜像、执行目录、缓存目标以及账户容量。缓存和执行必须指向同一个项目。

## 为工作节点准备操作 {#prepare-actions-for-workers}

- 声明输入和输出。输出必须保留在操作的工作目录之下。
- 在工作节点镜像内解析工具，而不是在发起计算机上使用绝对路径。
- 使用可安全重复执行的操作：工作节点故障或服务重启可能导致再次执行。
- 将超时控制在服务的十分钟操作限制内。不支持的要求（包括网络拒绝）会失败，而不会静默地在本地运行。

Once 会遵守账户公布的操作用并发数，并在服务队列已满时退避。更改镜像会将构建配置与缓存结果分离，防止在不兼容的工作节点镜像之间重用。

## 检查远程执行 {#inspect-remote-execution}

项目侧边栏有一个**远程执行**页面。其**分析**卡片显示所选时间段内的执行次数和总执行时间，如<.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">运行操作与用量</.localized_link>中所述。Once 的运行遥测数据尚无法区分远程执行与本地操作，因此该页面没有每次运行的远程计时或正在运行的运行记录。它会解释这一差距，并提供指向**构建运行**的链接以查看记录的操作详情。当前正在运行和排队的远程操作可通过 `get_remote_execution_activity` MCP 工具及其 REST 端点获取。两者都来自执行服务，而非工作节点通道。

请参阅[Once 的远程执行指南](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)，了解排队、身份验证刷新和缓存端点覆盖。按照<.localized_link href="/guides/features/build-insights/once">Once 构建洞察</.localized_link>检查生成的运行记录。
