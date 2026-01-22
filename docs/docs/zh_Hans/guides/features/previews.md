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

在构建应用时，您可能需要与他人分享以获取反馈。传统上，团队会通过构建、签名并将应用推送到Apple的[TestFlight](https://developer.apple.com/testflight/)等平台来实现。然而，这个过程可能繁琐且耗时，尤其当您仅需从同事或朋友处快速获取反馈时。

为使流程更高效，Tuist提供了一种生成应用预览并分享给任何人的方式。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
在为设备构建应用时，确保应用正确签名目前是您的责任。我们计划在未来简化此流程。
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

该命令将生成可供任何人运行的应用链接——无论在模拟器还是真实设备上。用户只需执行以下命令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享`.ipa文件时，` 可通过预览链接直接在移动设备下载应用。默认情况下，`.ipa` 的预览链接为_private_
，即接收方需使用Tuist账户认证才能下载应用。若需公开分享，可在项目设置中将权限改为公开。

`tuist run` 还支持基于指定参数运行最新预览，例如：`latest` 、分支名称或特定提交哈希值：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
通过利用大多数CI提供商公开的CI运行编号，确保`的CFBundleVersion` （构建版本）具有唯一性。例如在GitHub
Actions中，可将`的CFBundleVersion` 设置为<code v-pre>${{ github.run_number }}</code>变量。

上传预览时，若二进制文件（构建版本）与`的CFBundleVersion` 相同，则上传失败。
<!-- -->
:::

## 轨道{#tracks}

轨道功能可将预览版本组织为命名组。例如：可为内部测试人员创建`beta` 轨道，为自动化构建创建`nightly`
轨道。轨道采用延迟创建机制——分享时只需指定轨道名称，若不存在则自动创建。

若需分享特定音轨的预览，请使用`--track` 选项：

```bash
tuist share App --track beta
tuist share App --track nightly
```

此规则适用于：
- **预览组织规则**: 按用途分组预览（例如：`beta`,`nightly`,`internal` ）
- **应用内更新** ：Tuist SDK通过追踪功能确定需通知用户的更新内容
- **筛选** ：在Tuist仪表盘中轻松按曲目查找和管理预览

::: warning PREVIEWS' VISIBILITY
<!-- -->
仅项目所属组织的成员可访问预览内容。我们计划添加链接过期功能。
<!-- -->
:::

## Tuist macOS 应用程序{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

为更便捷地运行Tuist预览功能，我们开发了Tuist
macOS菜单栏应用。您可[下载](https://tuist.dev/download)macOS应用替代通过Tuist命令行界面运行预览功能，也可通过以下命令安装：`brew
install --cask tuist/tuist/tuist`

现在当您在预览页面点击"运行"时，macOS应用程序将自动在您当前选定的设备上启动该程序。

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

与macOS应用类似，Tuist iOS应用也简化了预览内容的访问和运行流程。

## 拉取/合并请求注释{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
要获取自动拉取/合并请求评论，请将您的<LocalizedLink href="/guides/server/accounts-and-projects">远程项目</LocalizedLink>与<LocalizedLink href="/guides/server/authentication">Git平台</LocalizedLink>集成。
<!-- -->
:::

测试新功能应是代码审查的组成部分。但本地构建应用会增加不必要的摩擦，导致开发者常跳过设备端功能测试。但*如果每个拉取请求都包含一个构建链接，该链接能自动在Tuist
macOS应用中选定的设备上运行应用呢？*

当您的Tuist项目与Git平台（如[GitHub](https://github.com)）连接后，请在CI工作流中添加<LocalizedLink href="/cli/share">`tuist
share
MyApp`</LocalizedLink>。Tuist将自动在您的拉取请求中嵌入预览链接：![GitHub应用评论中的Tuist预览链接示例](/images/guides/features/github-app-with-preview.png)


## 应用内更新通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)
可使您的应用检测到更新的预览版本并通知用户。这有助于让测试人员始终使用最新构建版本。

SDK会在同一**预览分支内检查更新** 。当您通过`--track`
显式指定分支共享预览时，SDK将仅在此分支内查找更新。若未指定分支，则使用git分支作为预览分支——因此基于`主分支` 构建的预览，仅会通知基于`主分支`
构建的新预览。

### 安装{#sdk-installation}

将 Tuist SDK 添加为 Swift Package 依赖项：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 监测更新{#sdk-monitor-updates}

使用`monitorPreviewUpdates` 定期检查新预览版本：

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
更新检查功能在模拟器和App Store构建中会自动禁用。
<!-- -->
:::

## README 徽章{#readme-badge}

为使Tuist预览在您的仓库中更显眼，可在`的README文件` 中添加徽章，该徽章将指向最新的Tuist预览：

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

要在您的`README` 中添加徽章，请使用以下 Markdown 并替换账户和项目名称：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

若项目包含多个具有不同包标识符的应用，可通过添加`bundle-id` 查询参数指定要链接的预览应用：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自动化{#automations}

可通过`--json` 参数，从`tuist share` 命令获取JSON输出：
```
tuist share --json
```

JSON输出可用于创建自定义自动化流程，例如通过CI提供商发布Slack消息。该JSON包含以下关键字段：- `` `：包含完整预览链接的`网址- ``
`：提供二维码图像URL的`qrCodeURL字段这些功能便于从真实设备下载预览内容。JSON输出示例如下：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
