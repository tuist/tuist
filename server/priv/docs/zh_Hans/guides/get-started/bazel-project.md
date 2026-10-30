---
{
  "title": "Bazel project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Bazel workspace to Tuist for a shared remote cache and build and test insights across CI, without changing any BUILD file."
}
---
# Bazel 项目 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

按照此路径将现有的 Bazel 工作区接入 Tuist。Tuist 提供一个 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 缓存，Bazel 可将其作为远程缓存进行连接；同时提供 Build Event Service 流，将每次构建和测试转化为仪表板上可见的数据。

下面的每个部分首先说明当前缺失的内容，然后引导你了解填补这一空白的功能。

## 前提条件

- 一个 Bazel 工作区（根目录下包含 `WORKSPACE` 或 `MODULE.bazel`），并且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令行界面</.localized_link>。

## 连接工作区

> [!NOTE]
> `tuist init` 内的 Bazel 工作流需要随其一起提供的 Tuist CLI 版本。在较早的版本中，`tuist init` 不会将“Integrate a Bazel workspace”列为选项。请回退到从工作区根目录运行 `tuist auth login`，然后运行 `tuist bazel setup`，这将引导你完成下面相同的步骤。

在 Bazel 工作区的根目录下，运行 `tuist init`。Tuist 会检测 `WORKSPACE` / `MODULE.bazel` 并提供 **Integrate a Bazel workspace**。在浏览器中进行身份验证，并选择应拥有该项目的账户。

```bash
tuist init
```

如果你通过编码代理或脚本驱动此流程，请先运行 `tuist auth login`（浏览器流程会等待你按 Enter 键），然后使用非交互式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

当 init 完成后，Tuist 会：

1. 在工作区根目录写入包含项目句柄的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁边写入 `.bazelrc.tuist`，连接到最近的 Tuist 缓存区域，并通过每个工作区的凭据助手进行身份验证。
3. 在你的 `.bazelrc` 中添加一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 行。它在每台机器上都相同。将 `.bazelrc.tuist` 添加到你的 `.gitignore`。凭据助手的路径是按用户设置的，缓存区域是按位置设置的，因此不应共享。

一旦工作区连接成功，以下内容将自动启用。

## 远程缓存

Bazel 自身的本地磁盘缓存位于 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位开发者机器上的缓存命中不会惠及他人，而 CI 任务容器每次运行都从空缓存开始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是将同一缓存扩展到共享端点的协议。Tuist 支持该协议。一旦 `.bazelrc.tuist` 就位，Bazel 会跳过输出已存在于共享缓存中的操作，并改为下载这些输出。一台机器的工作成果将惠及构建相同版本的其他所有机器。

通过对同一版本执行两次干净构建来验证（本地执行，或一次本地 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次运行的摘要应报告缓存命中。在仪表板上打开 **Cache** 以查看随时间变化的命中率。

## 构建和测试洞察

Bazel 的构建事件流和每次测试的 XML 报告会在每次调用时发出。比较一周内目标级别的持续时间，或识别在多次 CI 运行中变得不稳定的测试，意味着需要在某处收集并聚合这些事件。

Bazel 已经发出的 Build Event Service 协议正是为此设计的。`tuist init` 写入的 `.bazelrc.tuist` 会将 BES 流配置为指向 Tuist，因此在下一次 `bazel build` 和 `bazel test` 时，构建和测试洞察数据就会开始流入。无需额外配置。在仪表板上打开 **Builds** 和 **Tests** 即可查看数据。

## 邀请团队加入

缓存命中和洞察的价值会随着连接到项目的人数增加而累积。从仪表板的账户设置中邀请你的团队成员加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），这样入职只需点击一下，而不必让每个人单独运行 `tuist auth login`。
