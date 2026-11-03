---
{
  "title": "Xcode 预览",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "分享来自现有 Xcode 项目和 Tuist 生成项目的应用预览。"
}
---
# Xcode 预览

构建你的应用，然后使用 `tuist share` 将其发布到你的 Tuist 项目。请先按照 <.localized_link href="/guides/get-started/existing-xcode-project">现有 Xcode 项目</.localized_link> 或 <.localized_link href="/guides/get-started/generated-xcode-project">生成项目</.localized_link> 指南连接你的项目。

## 构建与分享

对于 Tuist 生成的项目：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

对于现有的 Xcode 项目：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

将 scheme、项目和 workspace 名称替换为你自己的名称。要分享 Release 构建，请在构建时使用 `-configuration Release`，在分享时使用 `--configuration Release`。

## 物理设备

你需要负责使用允许在接收者设备上安装的描述文件对设备构建进行签名。请使用设备目标而非模拟器 SDK 进行构建：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

你也可以分享已导出的 IPA：

```bash
tuist share App.ipa
```

接收者可以在移动设备上打开 IPA 预览链接以安装应用。身份验证和项目的预览可见性设置仍然适用。

## CI 与构建号

使用你现有的 <.localized_link href="/guides/integrations/continuous-integration">CI 身份验证</.localized_link>，并确保每个新构建的 `CFBundleVersion` 唯一。例如，可以使用 GitHub Actions 的 <code v-pre>{{ github.run_number }}</code>。通过 `tuist share` 再次上传相同的二进制文件和构建号将会失败，而不会创建重复项。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

请参阅 <.localized_link href="/guides/features/previews#run-a-preview">运行预览</.localized_link>，了解如何运行已发布的构建、访问权限、渠道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->

接收者可以独立于构建系统集成使用 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 应用</.localized_link> 或 <.localized_link href="/guides/features/previews/run/ios">iPhone 应用</.localized_link>。iPhone 指南还介绍了如何使用 Tuist SDK 实现 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">应用内更新通知</.localized_link>。
