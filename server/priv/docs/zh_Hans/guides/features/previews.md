---
{
  "title": "Previews",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist Previews 分享移动应用、桌面应用和命令行工具，让团队成员无需在本地重新构建即可试用。"
}
---
# 预览 {#previews}

Tuist 预览让团队成员无需在本地重新构建即可试用移动应用、桌面应用和命令行工具。将构建发布到你的 Tuist 项目，然后分享其预览链接。

## 可预览的内容 {#what-you-can-preview}

- **移动应用：** Android APK 以及 Apple 应用包或 IPA。支持的设备、模拟器和签名要求取决于发布工作流。
- **桌面应用：** macOS 应用包。
- **命令行工具：** macOS 或 Linux 可执行文件，可单独提供或与依赖项打包在一起。

请参阅<.localized_link href="/guides/features/previews/types">支持的类型</.localized_link>以了解打包和兼容性要求。构件类型决定预览可以在哪里运行；它并不规定由哪个构建系统生成。

## 发布预览 {#publish-a-preview}

选择你的构建系统以获取设置和发布命令：

<.home_cards>
  <.home_card
    title="Xcode"
    details="共享来自现有 Xcode 项目或 Tuist 生成项目的应用。"
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="共享来自 Gradle 项目的 Android 应用和原生命令行工具。"
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="通过配套的 Bazel 规则共享 Android 应用、Apple 应用和命令行工具。"
    link="/guides/features/previews/bazel"
  />
</.home_cards>

如果你已有受支持的构建，请使用<.localized_link href="/cli/share">`tuist share`</.localized_link>在不集成构建系统的情况下发布它。打包和签名要求仍然适用。

## 运行预览 {#run-a-preview}

接收者不需要生成该预览的构建系统。选择访问兼容构建的方式：

<.home_cards>
  <.home_card
    title="CLI"
    details="使用 tuist run 运行移动应用、macOS 应用和命令行预览。"
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS 应用"
    details="通过 Tuist 菜单栏应用运行兼容的 Apple 预览。"
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone 应用"
    details="在 iPhone 上查找并访问你的 Apple 预览。"
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## 可见性 {#visibility}

预览使用项目的默认可见性。私有预览需要身份验证和项目访问权限。仅当构建可以与任何人共享时，才在项目设置中将预览设为公开。公开可见性不会绕过平台签名或设备安装要求。

## 轨道 {#tracks}

轨道将预览组织为命名组，例如用于内部测试人员的 `beta` 或用于自动化构建的 `nightly`。在工作流的发布命令中指定轨道；轨道会在首次使用时延迟创建。使用它们按用途对预览进行分组，并在 Tuist 仪表板中过滤预览。

## README 徽章 {#readme-badge}

在你的仓库的 `README` 中添加一个指向最新预览的徽章：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

将账户和项目句柄替换为你自己的：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果项目包含多个具有不同 bundle identifier 的应用，请添加 `bundle-id` 查询参数来选择应用：

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
