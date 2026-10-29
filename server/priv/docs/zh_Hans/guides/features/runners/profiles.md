---
{
  "title": "配置文件",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "Runner 配置文件是已命名的机器规格，你可以在 runs-on 中引用它们，为 Tuist Runners 选择平台、规模和 Xcode 版本。"
}
---
# 配置文件 {#profiles}

**配置文件**是账户级别、具名的机器规格。你可以在工作流的 `runs-on` 中引用它，Tuist 会将作业路由到匹配的 Runner。配置文件将基础设施选择（平台、规格、Xcode 版本）集中在一处，而不是分散在每个工作流文件中，并为你提供一个稳定的标签供 CI 使用。

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

该标签是配置文件名称加上 `tuist-` 前缀。名为 `macos` 的配置文件对应 `runs-on: tuist-macos`；名为 `linux-large` 的配置文件对应 `runs-on: tuist-linux-large`。匹配不区分大小写。

## 默认配置文件 {#default-profiles}

每个启用 Runners 的账户都预置两个配置文件，因此你无需任何配置即可使用资源池：

{{runner_default_profiles_table}}

两者都指向各自平台的默认<.localized_link href="/guides/features/runners/profiles#machine-shapes">机器规格</.localized_link>。它们是**受保护的**，因此无法被删除，且你的工作流所依赖的标签始终能够正确解析。你仍然可以更改其机器规格或 Xcode 版本，也可以为其他规格或 Xcode 版本创建额外的配置。

## 机器规格 {#machine-shapes}

Runner 支持 macOS（Apple silicon，在 Mac 资源池上虚拟化）和 Linux。每个配置文件固定一种机器规格，即来自下方目录的一个 `(vCPUs, memory)` 对。

### Linux {#linux}

{{runner_linux_shapes_table}}

每个 Linux 配置都通过 `/dev/kvm` 支持<.localized_link href="/guides/features/runners#android-emulators">硬件加速的 Android 模拟器</.localized_link>。无需单独的 KVM 配置。

### macOS {#macos}

{{runner_macos_shapes_table}}

较大的 macOS 规格在资源池中可用的机器较少，因此请求此类规格的作业可能比在较小规格上运行的相同作业等待更久才能启动。当作业受 CPU 限制时，选择更大的规格；其他情况保留默认规格。如果不确定，可以在两种规格上运行作业并在仪表盘中比较耗时。

macOS 配置文件还会固定一个**Xcode 版本**。该版本会选择预装相应 Xcode 的 Runner 镜像，因此作业启动时工具链已就绪。当前支持的版本：

{{runner_macos_xcode_versions}}

> [!NOTE]
> 随着我们添加新硬件和 Xcode 发布，目录会不断更新。仪表盘中的**新建配置文件**表单和 `tuist runner profile catalog` 始终显示你的账户当前可用的规格和 Xcode 版本，因此请以它们为准。

macOS Runner 的名称会显示其运行的 macOS 版本、配置文件的 Xcode 版本以及规格，例如 `tuist-macos-26.6-xcode-27.0-6vcpu-14gb-1a2b3c4d5e6f`。该名称会出现在 GitHub 上作业的 **设置作业** 步骤中，以及 Tuist 仪表盘的作业详情中。

## 创建配置文件 {#creating-a-profile}

1. 打开账户仪表盘中的 **Runners → Profiles** 部分。
2. 选择 **新建配置文件**。
3. 为其命名，选择平台，并选择规格。对于 macOS，还需选择 Xcode 版本。
4. 保存，然后在工作流中通过 `runs-on: tuist-<name>` 引用它。

你也可以从命令行管理配置文件。创建、更改和删除配置文件需要账户管理员权限（如同在仪表盘中操作），或拥有 `account:runners:write` 范围的账户令牌：

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

智能体也可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link> 执行相同的操作。

例如，一个名为 `linux-large` 的配置文件，使用 8 vCPU / 32 GB 规格：

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

或者一个名为 `xcode-26-4` 的 macOS 配置文件，固定到 Xcode `26.4.1`，这样作业可以在较旧的工具链上运行，而你的默认 `macos` 配置文件则跟踪最新版本：

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
