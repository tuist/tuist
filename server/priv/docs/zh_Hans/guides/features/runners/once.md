---
{
  "title": "一次性远程执行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 远程执行工作节点上运行符合条件的一次性图命令操作。"
}
---
# Once 远程执行 {#once-remote-execution}

共享缓存避免重复其他机器已完成的工作。远程执行还会将符合条件的缓存未命中任务从你的计算机移出：Once 会在 Tuist 的一次性 Linux 工作器上调度图命令操作，并通过相同的项目缓存检索其输出。

> [!NOTE]
> 远程执行目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)以请求为你的账户开通访问权限。

> [!IMPORTANT]
> **要求**
>
> - 一个已启用远程执行且具备可用执行容量的 Tuist 账户。
> - 一个支持 Tuist 远程执行的 Once 版本。
> - 一个兼容的服务器，需公布工作器镜像、缓存端点、并发能力以及绝对执行目录。省略该目录的服务器与当前 Once 客户端不兼容；Once 会在上传工作前停止。
> - 能够在已公布的工作器镜像内的 `linux/amd64` 上运行的命令和工具链。

这仅运行图操作，而非整个 CI 作业。配置 Once 不会安装 GitHub 或 GitLab 工作流编排。

## 设置 {#setup}

完成<.localized_link href="/guides/get-started/once-project">Once 入门指南</.localized_link>。为缓存和执行选择相同的 Tuist 提供商，并锁定服务所公布的工作器镜像：

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

将目标和镜像标签替换为你自己的值。Once 会在上传工作前检查已公布的镜像、执行目录、缓存目标以及账户容量。缓存和执行必须指向同一个项目。

## 为工作器准备操作 {#prepare-actions-for-workers}

- 声明输入和输出。输出必须保留在操作的工作目录之下。
- 在工作器镜像内解析工具，而不是在发起计算机上使用绝对路径。
- 使用可安全重试的操作：工作器故障或服务重启可能导致再次执行。
- 将超时控制在服务的十分钟操作限制内。不支持的要求（包括网络拒绝）会失败，而不会静默地在本地运行。

Once 遵循账户公布的操作用并发度，并在服务队列已满时退避。更改镜像会将构建配置与缓存结果隔离，防止在不兼容的工作器镜像之间复用。

## 检查远程执行 {#inspect-remote-execution}

项目侧边栏有一个**远程执行**页面，但 Once 的运行遥测数据尚无法区分远程执行与本地操作。该页面说明了这一差距，并链接到**构建运行**以查看记录的操作详情；它不会从工作器通道推断远程活动，也不会将这些操作显示为远程用量。

请参阅[Once 远程执行指南](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)，了解队列处理、身份验证刷新和缓存端点覆盖。按照<.localized_link href="/guides/features/build-insights/once">Once 构建洞察</.localized_link>检查生成的运行结果。
