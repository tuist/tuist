---
{
  "title": "支持的预览类型",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "移动应用、macOS 应用和命令行预览的打包与兼容性要求。"
}
---
# 支持的预览类型

预览类型决定了你要打包的内容以及它可以在哪里运行，这与生成它的构建系统无关。每种发布工作流都有其自身的签名和资格要求。

## 移动应用 {#mobile-apps}

- **Android：** 已签名的应用程序 APK。接收者需要兼容的 Android 设备或模拟器。Android App Bundles（`.aab`）不是预览安装程序包。
- **Apple：** 用于模拟器的应用程序包，或用于物理设备的导出 IPA。设备构建需要一个允许在接收者设备上安装的配置文件。

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>、<.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> 和 <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> 指南描述了每种工作流可以发布哪些输出。例如，Bazel 和 Once 发布支持符合条件的 Apple 模拟器和 macOS 应用程序，不支持物理设备构建。

## 桌面应用 {#desktop-apps}

共享已构建的 macOS 应用程序包：

```bash
tuist share path/to/MyApp.app
```

签名和公证要求仍然适用。桌面应用程序包不同于 Tuist macOS 应用，后者可供接收者用来运行预览。

## 命令行工具 {#command-line-tools}

在 macOS 或 Linux 上共享独立可执行文件：

```bash
tuist share path/to/my-tool
```

如果 CLI 需要资源包、动态库或辅助可执行文件，请组装一个分发目录并指定相对于该目录的入口点：

```bash
tuist share path/to/distribution --executable bin/my-tool
```

整个分发目录都会被上传。包含你的工具所需的库、资源和辅助程序，并确保它可以在构建目录之外运行。脚本需要在接收者的系统上安装 shebang 和解释器。

## 多个 CLI 目标 {#multiple-cli-targets}

预览将同一 CLI 针对一次提交的构建分组；每个构建包含针对一个操作系统和一个或多个 CPU 架构的分发。例如，一个预览可以包含 macOS arm64、macOS x86_64 和 Linux x86_64 分发。通用 macOS 可执行文件在一次构建中涵盖两种 Mac 架构。

分别构建每个目标，然后从相同的 Git 检出中使用相同的入口点基本名称和轨道依次发布分发：

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

这些上传会将构建添加到同一个预览链接。在所有上传中保持项目、提交、发布账户、CLI 名称和轨道一致。Tuist 会选择与接收者操作系统和 CPU 架构匹配的构建。

## 客户端和服务器兼容性 {#client-and-server-compatibility}

使用最新的 Tuist CLI 来运行桌面和命令行预览。如果你自托管 Tuist，请在发布这些类型之前更新你的服务器。移动预览仍可与旧版客户端配合使用。

为接收者的操作系统和 CPU 架构进行构建。Tuist 不会交叉编译你的应用或安装其依赖项；Linux 工具还需要兼容的系统库。

预览以你的用户账户权限运行，而不是在沙盒中。仅运行你信任的作者和拉取请求中的构建。

参见<.localized_link href="/guides/features/previews/run/cli">使用 CLI 运行预览</.localized_link>了解执行行为和参数转发，以及<.localized_link href="/guides/features/previews#visibility">预览概览</.localized_link>了解访问权限、轨道和 README 徽章。
