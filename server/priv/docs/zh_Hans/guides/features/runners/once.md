---
{
  "title": "一次性远程执行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 远程执行工作节点上运行符合条件的一次性图命令操作。"
}
---
# Once 远程执行 {#once-remote-execution}

共享缓存避免重复其他机器已完成的工作。远程执行还将符合条件的缓存未命中从你的计算机移走：Once 在 Tuist 的一次性 Linux worker 上调度图命令操作，并通过同一项目缓存检索其输出。

> [!IMPORTANT]
> **要求**
>
> - 一个已启用远程执行并具备可用执行容量的 Tuist 账户。
> - 支持 Tuist 远程执行的 Once 版本。
> - 一个兼容的服务器，用于公布 worker 镜像、缓存端点、并发性和绝对执行目录。省略目录的服务器与当前 Once 客户端不兼容；Once 会在上传工作之前停止。
> - 能够在公布的 worker 镜像内的 `linux/amd64` 上运行的命令和工具链。

这运行的是图操作，而不是整个 CI 作业。配置 Once 不会安装 GitHub 或 GitLab 工作流编排。

## 设置 {#setup}

完成<.localized_link href="/guides/get-started/once-project">Once 入门指南</.localized_link>。为缓存和执行选择相同的 Tuist 提供商，并锁定服务公布的 worker 镜像：

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

将目标和镜像标签替换为你自己的。Once 在上传工作之前会检查公布的镜像、执行目录、缓存目标和账户容量。缓存和执行必须指向同一个项目。

## 为 worker 准备操作 {#prepare-actions-for-workers}

- 声明输入和输出。输出必须保留在操作的工作目录之下。
- 在 worker 镜像内解析工具，而不是在发起计算机上的绝对路径中解析。
- 使用可安全重复的操作：worker 故障或服务重启可能导致再次执行。
- 将超时时间控制在服务的十分钟操作限制内。不支持的要求（包括网络拒绝）会导致失败，而不是静默地在本地运行。

Once 尊重账户公布的操作并发性，并在服务队列已满时退避。更改镜像会将构建配置与缓存结果分开，防止在不兼容的 worker 镜像之间重用。

请参阅[Once 远程执行指南](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)以了解队列、身份验证刷新和缓存端点覆盖。按照<.localized_link href="/guides/features/build-insights/once">Once 构建洞察</.localized_link>检查生成的运行结果。
