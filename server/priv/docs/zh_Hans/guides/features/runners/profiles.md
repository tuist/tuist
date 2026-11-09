---
{
  "title": "配置文件",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 配置文件是命名的机器规格，你可以在 runs-on 中引用它们，为 Tuist Runners 选择平台、大小、Ubuntu 版本或 Xcode 版本。"
}
---
# 配置文件 {#profiles}

**配置文件**是一种以账户为范围、具有名称的机器规格。你可以在工作流的 `runs-on` 中引用它，Tuist 会将作业路由到匹配的 Runner。配置文件将基础设施选择（平台、规格大小、Ubuntu 版本或 Xcode 版本）集中在一处，而不是分散在每个工作流文件中，并为你提供一个稳定的标签供 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

该标签是配置文件的名称加上 `tuist-` 前缀。名为 `macos` 的配置文件对应 `runs-on: tuist-macos`；名为 `linux-large` 的配置文件对应 `runs-on: tuist-linux-large`。匹配时不区分大小写。

## 默认配置文件 {#default-profiles}

每个启用了 Runners 功能的账户都预置了两个配置文件，因此你无需任何配置即可使用 Runner 集群：

{{runner_default_profiles_table}}

两者都指向各自平台的默认<.localized_link href="/guides/features/runners/profiles#machine-shapes">规格</.localized_link>。它们是**受保护的**，因此无法被删除，且你的工作流所依赖的标签始终可以解析。你仍然可以更改它们的规格或 Xcode 版本，也可以为其他规格大小或 Xcode 版本创建额外的配置文件。

## 机器规格 {#machine-shapes}

Runner 支持 macOS（Apple 芯片，在 Mac 集群上虚拟化）和 Linux。每个配置文件从下面的目录中固定一种机器规格，即一个 `(vCPUs, memory)` 对。

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux 配置文件还会选择一个 **Ubuntu 版本**，就像 macOS 配置文件选择 Xcode 版本一样：

- **Ubuntu 24.04**（`ubuntu-24.04`），新配置文件的默认值。
- **Ubuntu 22.04**（`ubuntu-22.04`），适用于仍需要它的工作流。GitHub 已弃用其 22.04 托管镜像，并将于 2027 年 4 月 17 日移除；请计划在此之前迁移。

配置文件会保持在你选择的版本上，直到你更改它，因此新的默认值不会自动将你的作业迁移到其他操作系统。在 24.04 上构建的二进制文件需要其较新的 glibc (2.39)，可能无法在较旧的系统上运行，并且其系统 Python 拒绝在虚拟环境之外执行 `pip install`（PEP 668）。Runner 会像 GitHub 托管的 Runner 一样设置 `ImageOS`（`ubuntu24` 或 `ubuntu22`），以便 setup 操作选择正确版本的构建。

每个 Linux 配置文件都通过 `/dev/kvm` 支持<.localized_link href="/guides/features/runners#android-emulators">硬件加速的 Android 模拟器</.localized_link>。不需要单独的 KVM 配置文件。

### macOS {#macos}

{{runner_macos_shapes_table}}

较大的 macOS 规格在集群中可用的机器较少，因此请求该规格的作业可能比在较小规格上运行的相同作业等待更长时间才能启动。当作业受 CPU 限制时，请选择较大的规格，其他情况则保留默认规格。如果不确定，可以在两种规格上运行作业并在仪表板中比较持续时间。

macOS 配置文件还会固定一个 **Xcode 版本**。该版本会选择预安装了该 Xcode 的 Runner 镜像，因此作业开始时工具链已就位。当前支持的版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 随着我们添加硬件和 Xcode 版本，目录会不断演变。仪表板中的 **新建配置文件** 表单和 `tuist runner profile catalog` 始终显示你的账户当前可用的规格、Xcode 版本和 Ubuntu 版本，因此请将它们视为权威来源。

macOS Runner 的名称显示其运行的 macOS 版本、配置文件的 Xcode 版本及其规格，例如 `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`。该名称出现在 GitHub 上作业的 **设置作业** 步骤以及 Tuist 仪表板中的作业详情中。

## 创建配置文件 {#creating-a-profile}

1. 打开账户仪表板的 **Runners → Profiles** 部分。
2. 选择 **新建配置文件**。
3. 为其命名，选择平台，并选择规格。对于 Linux，还需选择 Ubuntu 版本；对于 macOS，选择 Xcode 版本。
4. 保存，然后在工作流中使用 `runs-on: tuist-<name>` 引用它。

你也可以从命令行管理配置文件。创建、更改和删除配置文件需要账户管理员权限（如同在仪表板中一样），或者拥有带有 `account:runners:write` 范围的账户令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Agent 可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link> 执行相同的操作。

例如，在 8 vCPU / 32 GB 规格上名为 `linux-large` 的配置文件：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者一个名为 `xcode-26-4` 的 macOS 配置文件，固定到 Xcode `26.4.1`，这样作业就可以在较旧的工具链上运行，而你的默认 `macos` 配置文件跟踪最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
