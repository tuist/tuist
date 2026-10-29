---
{
  "title": "Bazel 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Bazel 命令耗时、缓存总量和关键路径诊断。"
}
---
# Bazel 构建洞察 {#bazel-build-insights}

每次完成的 `build`、`test` 以及其他 Bazel 命令都会显示在项目的 **调用** 仪表板上：包括命令类型、退出状态、开始和结束时间、持续时间，以及 Bazel 归因于该次调用的缓存命中、未命中、下载和上传。

调用数据通过 Bazel 的 [Build Event Protocol](https://bazel.build/remote/bep) 交付。当你运行 `tuist bazel setup` 时，设置会自动为你连接；无需额外标志即可开始查看调用。

## 仪表板显示内容 {#what-the-dashboard-shows}

每次调用记录：

- Bazel 运行的命令、其退出代码、开始和结束时间，以及总持续时间。
- 操作、目标和包的数量。
- 有限的构建时间线和关键路径摘要。
- 归因于该调用的缓存命中、未命中、下载和上传。
- 按执行顺序捕获的运行期间进度日志行。
- Bazel 版本、git 分支和提交（当 Bazel 报告时），以及运行是否在 CI 上发生。

Bazel 无法归因于已完成调用的缓存活动（例如命令在中途被中断时）仍会作为原始远程缓存观察出现在项目 **概览** 中。它不被视为命令成功、持续时间或测试结果的证据。

## 自定义元数据 {#custom-metadata}

将键值数据附加到调用，以比较来自不同团队、硬件或工作流的运行。值显示在每次调用的详细信息页面上，并通过应用程序编程接口和 Model Context Protocol 工具提供。

使用 Bazel 内置的 `--build_metadata` 标志设置元数据：

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

或在你的 `.bazelrc` 中为每个通道设置一次：

```text
build:ci --build_metadata=RUNNER=macos-14
```

每次调用最多可携带 20 个自定义条目。键最多可包含 50 个字符，值最多可包含 500 个字符。超出这些限制的条目会在存储调用之前被丢弃，因此无效条目不会阻止报告的其余部分被记录。

Tuist 从构建环境中派生的上下文键（如 `CI`、`GIT_BRANCH` 和 `GIT_COMMIT`）不作为自定义值存储，因为它们已填充到调用的首要字段中。

自定义元数据对项目成员在仪表板中可见，并通过应用程序编程接口和 Model Context Protocol 工具提供。不要将其用于凭据、访问令牌或其他敏感数据。

## 选择退出 {#opting-out}

Build Event Protocol 流携带命令行参数、环境变量值和命令输出。Tuist 仅保留上述列出的已完成命令字段并丢弃其余部分，但如果你根本不想发送事件流，请重新运行设置：

```bash
tuist bazel setup --no-build-insights
```

生成的 `.bazelrc.tuist` 随后仅配置远程缓存。调用将不再显示在仪表板中，而缓存观察仍保留在 **概览** 页面上。

## 数据保留 {#data-retention}

Tuist 保留 Bazel 调用及其日志 90 天。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">数据保留</.localized_link>。
