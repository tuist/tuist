---
{
  "title": "Bazel 项目",
  "titleTemplate": ":title · 入门指南 · 教程 · Tuist",
  "description": "将 Bazel 工作区连接到 Tuist，以共享远程缓存并在 CI 中获取构建和测试洞察，无需更改任何 BUILD 文件。"
}
---
# Bazel 项目 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

按照此步骤将现有的 Bazel 工作区接入 Tuist。Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可将其作为远程缓存连接；同时提供 Build Event Service 流，将每次构建和测试转化为仪表板上可见的数据。如需了解 Tuist 为 Bazel 带来的价值，请参阅 [Bazel with Tuist](https://tuist.dev/build-systems/bazel)。如果你正从其他 Bazel 服务商迁移，[BuildBuddy](https://tuist.dev/compare/buildbuddy) 和 [EngFlow](https://tuist.dev/compare/engflow) 的对比页面说明了变更内容。

以下每个部分先指出当前的缺失，再引导你使用填补该空白的功能。

## 前提条件

- 一个 Bazel 工作区（根目录下包含 `WORKSPACE` 或 `MODULE.bazel`），并且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接工作区

在 Bazel 工作区的根目录运行 `tuist init`。Tuist 会检测到 `WORKSPACE` / `MODULE.bazel` 并提供 **集成 Bazel 工作区** 选项。在浏览器中完成身份验证，并选择应拥有该项目的账户。

```bash
tuist init
```

如果你通过编码代理或脚本执行此操作，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互模式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init 完成后，Tuist 会：

1. 在工作区根目录写入包含项目句柄的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁写入 `.bazelrc.tuist`，并将其连接到最近的 Tuist 缓存区域，通过每个工作区独立的凭据助手进行身份验证。
3. 向你的 `.bazelrc` 添加一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 这一行。它在每台机器上都相同。将 `.bazelrc.tuist` 加入你的 `.gitignore`。凭据助手的路径是按用户设置的，缓存区域是按位置设置的，因此不应共享。

工作区连接后，以下内容会自动启用。

## 远程缓存

Bazel 自带的本地磁盘缓存位于 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位开发者机器上的缓存命中不会惠及他人，而 CI 任务容器每次运行都从空缓存开始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是将同一缓存扩展到共享端点的协议。Tuist 支持该协议。一旦 `.bazelrc.tuist` 就位，Bazel 会跳过输出已存在于共享缓存中的动作，并直接下载这些输出。一台机器的工作成果将惠及其他所有构建相同版本的机器。

通过针对同一版本的两次干净构建来验证（本地两次，或一次本地 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次运行的摘要应报告缓存命中。在仪表板上打开 **Cache** 查看随时间变化的命中率。

## 构建与测试洞察

Bazel 的构建事件流和每个测试的 XML 报告在每次调用时发出。要比较一周内目标级别的耗时，或识别在多次 CI 运行中变得不稳定的测试，需要在某处收集并聚合这些事件。

Bazel 已经发出的 Build Event Service 协议正是为此设计。`tuist init` 写入的 `.bazelrc.tuist` 会将 BES 流配置到 Tuist，因此在下一次 `bazel build` 和 `bazel test` 时，构建和测试洞察数据就会开始流入。无需额外配置。在仪表板上打开 **Builds** 和 **Tests** 即可查看数据。

## 邀请团队加入

连接到项目的人数越多，缓存命中和洞察的价值就越显著。从仪表板的账户设置中邀请团队成员加入组织，并配置 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），让入职只需点击一下，而不必每人执行一次 `tuist auth login`。
