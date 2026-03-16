---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# 预览{#previews}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

在开发应用时，您可能希望与他人分享应用以获取反馈。通常，团队会通过构建、签名并将应用推送至 Apple 的
[TestFlight](https://developer.apple.com/testflight/)
等平台来实现这一点。然而，这个过程可能既繁琐又耗时，尤其是当您只是想从同事或朋友那里获得快速反馈时。

为了使这一流程更加顺畅，Tuist 提供了一种生成并分享应用预览的功能，供任何人查看。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
在为设备构建应用时，目前您需要自行确保应用已正确签名。我们计划在未来简化这一流程。
<!-- -->
:::

代码组
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

该命令将生成一个链接，您可以将其分享给任何人，以便他们在模拟器或真实设备上运行该应用。他们只需运行以下命令即可：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享`.ipa` 文件时，收件人可通过“预览”链接直接在移动设备上下载应用。`.ipa` 预览链接默认设置为_私有_ ，这意味着收件人需使用其 Tuist
账户进行身份验证才能下载应用。若需与任何人共享应用，您可在项目设置中将其更改为公开。

`运行 `` ` 还可以让你基于指定条件（例如 ``latest`、```、分支名称或特定提交哈希）运行最新预览版本：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
请利用大多数 CI 提供商公开的 CI 运行编号，确保`CFBundleVersion` （构建版本）的唯一性。例如，在 GitHub Actions
中，您可以将`CFBundleVersion` 设置为 <code v-pre>${{ github.run_number }}</code> 变量。

如果上传的预览包与原二进制文件（构建版本）的 CFBundleVersion 值相同（`` ），上传将失败。
<!-- -->
:::

## 轨道{#tracks}

“轨道”功能可让您将预览内容整理到命名组中。例如，您可以为内部测试人员创建一个`beta` 轨道，并为自动化构建创建一个`nightly`
轨道。轨道采用延迟创建机制——在分享时只需指定轨道名称，如果不存在该轨道，系统会自动创建。

若要分享特定曲目的预览，请使用`--track` 选项：

```bash
tuist share App --track beta
tuist share App --track nightly
```

这适用于：
- **预览组织**: 按用途分组预览（例如，`beta`,`nightly`,`internal` ）
- **应用内更新**: Tuist SDK 使用“轨迹”来确定需要通知用户哪些更新
- **筛选** ：在 Tuist 仪表盘中轻松查找和管理按曲目分类的预览

::: warning PREVIEWS' VISIBILITY
<!-- -->
只有该项目所属组织的成员才能访问预览。我们计划添加链接过期功能。
<!-- -->
:::

## Tuist macOS 应用程序{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

为了让运行 Tuist Previews 更加便捷，我们开发了一款 Tuist macOS 菜单栏应用。您无需通过 Tuist CLI 运行
Previews，而是可以 [下载](https://tuist.dev/download) 这款 macOS 应用。您也可以通过运行`brew install
--cask tuist/tuist/tuist` 来安装该应用。

现在，当您在“预览”页面点击“运行”时，macOS 应用将自动在您当前选定的设备上启动它。

警告要求
<!-- -->
您需要在本地安装 Xcode，并使用 macOS 14 或更高版本。
<!-- -->
:::

## Tuist iOS 应用程序{#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

与 macOS 应用类似，Tuist iOS 应用简化了预览文件的访问和运行流程。

## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要获取自动生成的拉取/合并请求评论，请将您的
<LocalizedLink href="/guides/server/accounts-and-projects">远程项目</LocalizedLink>
与 <LocalizedLink href="/guides/server/authentication">Git 平台</LocalizedLink> 集成。
<!-- -->
:::

测试新功能应是任何代码审查的组成部分。但必须在本地构建应用程序会增加不必要的麻烦，这往往导致开发者在设备上完全跳过功能测试。但*，如果每个拉取请求都包含一个构建链接，该链接能自动在您于
Tuist macOS 应用中选定的设备上运行应用程序，会怎样呢？*

当您的 Tuist 项目与 [GitHub](https://github.com) 等 Git 平台连接后，请在您的 CI 工作流中添加
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>。随后，Tuist
会直接在您的拉取请求中发布预览链接：![包含 Tuist 预览链接的 GitHub
应用评论](/images/guides/features/github-app-with-preview.png)


## 应用内更新通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)
可让您的应用检测到是否有新的预览版本可用，并通知用户。这有助于让测试人员始终使用最新构建版本。

SDK 会在同一**预览轨道** 内检查更新。当您使用`--track` 明确指定轨道分享预览时，SDK 将检查该轨道上的更新。如果未指定轨道，则使用 Git
分支作为轨道——因此，从`main` 分支构建的预览，只会通知同样从`main` 分支构建的新版预览。

### 安装{#sdk-installation}

将 Tuist SDK 添加为 Swift 包依赖项：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 监测更新{#sdk-monitor-updates}

使用`monitorPreviewUpdates` 定期检查是否有新的预览版本：

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### 单次更新检查{#sdk-single-check}

手动检查更新时：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 停止更新监控{#sdk-stop-monitoring}

`monitorPreviewUpdates` 返回一个可取消的`任务` ：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

信息
<!-- -->
在模拟器和 App Store 构建版本中，更新检查功能会自动禁用。
<!-- -->
:::

## README 徽章{#readme-badge}

为了让 Tuist Previews 在您的仓库中更显眼，您可以在`README` 文件中添加一个徽章，指向最新的 Tuist Preview：

[![Tuist
预览](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

要在您的`README` 中添加徽章，请使用以下 Markdown 代码，并将账户和项目名称替换为您自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果您的项目包含多个具有不同包标识符的应用，您可以通过添加`bundle-id` 查询参数来指定要链接到哪个应用的预览：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自动化{#automations}

`` 您可以使用 ``--json` 参数，通过 ``tuist share` 命令获取 JSON 输出：
```
tuist share --json
```

JSON 输出可用于创建自定义自动化操作，例如通过您的 CI 提供商发布 Slack 消息。该 JSON 包含一个`url`
键，其中包含完整的预览链接；以及一个`qrCodeURL` 键，其中包含二维码图片的 URL，以便更轻松地从真实设备下载预览。以下是一个 JSON 输出的示例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
