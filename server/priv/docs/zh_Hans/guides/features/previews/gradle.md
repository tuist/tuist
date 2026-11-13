---
{
  "title": "Gradle 预览",
  "titleTemplate": ":title · 预览 · Tuist",
  "description": "使用 Tuist Previews 从 Gradle 项目构建并分享 Android 应用和原生命令行工具。"
}
---
# Gradle 预览

直接从 Gradle 构建并分享 Android 应用和原生命令行工具。首先阅读<.localized_link href="/guides/get-started/gradle-project">Gradle 项目指南</.localized_link>，以连接项目并进行身份验证。

## Android 应用

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` 设置插件会为 Android Gradle Plugin（8.8.2 或更高版本）中的每个应用变体注册一个`tuistShare<Variant>`任务。将`app`和`Debug`替换为你的应用模块和变体，例如产品风味使用`:app:tuistShareDemoDebug`。该任务在发布之前会通过 Gradle 声明的构件依赖项来构建 APK。当构建输出为最新状态或从构建缓存中恢复时，它同样有效。

仅支持单个已签名的通用应用 APK。Android 的 debug 变体通常使用调试签名密钥；release 变体则需要你自己的签名配置。该任务会在身份验证或上传之前验证 APK 签名。未签名、无效、instrumentation 以及 split APK 均会被拒绝。库模块、测试 APK 和 Android App Bundle（`.aab`）不是发布目标。

## 原生命令行工具

使用 Gradle 的`cpp-application`或`swift-application`插件的项目会为每个原生二进制文件获得一个分享任务：

```bash
./gradlew :app:tuistShareMainDebug
```

该任务会构建并打包已安装的分发版，包括其启动器和运行时库。对 release 二进制文件使用`tuistShareMainRelease`。面向多台机器的项目会为每个二进制文件提供一个任务；运行`./gradlew :app:tasks --all`以查找它们的名称。

支持 arm64 或 x86_64 的原生 macOS 和 Linux 可执行文件。在目标平台上使用 Gradle 插件所需的工具链进行构建。此集成不支持 JVM 应用及其生成的启动器脚本。

## 发布行为

分享任务使用插件现有的 Tuist 凭据进行发布，无需调用 Tuist CLI。普通的`assemble`、`build`和测试任务永远不会发布预览。

分享后，在项目中打开**预览**以复制链接。重复分享相同的构建和轨道会复用其发布，包括在缓存命中之后。失败或未确认的上传会导致分享任务失败；它们不会被报告为成功的预览。

## CI 和轨道

使用与插件其他需要身份验证的功能相同的凭据配置<.localized_link href="/guides/integrations/continuous-integration">CI 身份验证</.localized_link>，然后显式请求发布：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

以相同方式将`--track nightly`添加到原生分享任务中。任务会使用配置的 Tuist 项目、服务器 URL 和代理设置。预览发布始终需要身份验证。这些任务不会附加 Git 修订元数据、发布说明或自动拉取请求评论。

在托管的 Tuist 上，构件发布会在 30 天后过期。自托管实例使用`TUIST_APP_PREVIEW_RETENTION_DAYS`；不设置该项将禁用此类发布的过期机制。已过期的发布无法通过重复相同操作来恢复。

## 分享现有 APK

对于在此工作流之外构建的 APK，或者为了在使用传统上传流程时包含发布说明，CLI 仍然可用：

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

请参阅<.localized_link href="/guides/features/previews#run-a-preview">运行预览</.localized_link>，了解如何运行已发布的构建、访问权限、轨道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->
