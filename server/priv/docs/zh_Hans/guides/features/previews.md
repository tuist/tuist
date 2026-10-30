---
{
  "title": "Previews",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "通过 Tuist Previews 即时分享 iOS 和 Android 应用构建。只需向团队成员和利益相关者发送一个链接，无需配置 TestFlight 或 Play Console。"
}
---
# Previews {#previews}

Tuist Previews 让你生成并分享应用预览，团队成员无需在本地重新构建即可测试构建。

在构建应用时，你可能希望与他人分享以获取反馈。传统上，团队会通过构建、签名并将应用推送到 Apple 的 [TestFlight](https://developer.apple.com/testflight/) 等平台来实现这一点。然而，这一过程可能繁琐且缓慢，尤其是当你只是想从同事或朋友那里快速获取反馈时。

为了让这一流程更加顺畅，Tuist 提供了一种生成并与任何人分享应用预览的方式。

> [!WARNING]
> **设备构建需要签名**
>
> 在为设备构建时，目前由你负责确保应用正确签名。我们计划在未来简化这一流程。

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

该命令将生成一个链接，你可以与任何人分享以运行应用——无论是在模拟器上还是在真实设备上。他们只需运行以下命令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享 `.ipa` 文件时，你可以使用预览链接直接从移动设备下载应用。`.ipa` 预览的链接默认是 _私有_ 的，这意味着接收者需要使用其 Tuist 账户进行身份验证才能下载应用。如果你希望与任何人分享应用，可以在项目设置中将其更改为公开。

`tuist run` 还允许你基于诸如 `latest`、分支名称或特定提交哈希等标识符运行最新的预览：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI 中的唯一构建号**
>
> 通过利用大多数 CI 提供商提供的 CI 运行编号，确保 `CFBundleVersion`（构建版本）是唯一的。例如，在 GitHub Actions 中，你可以将 `CFBundleVersion` 设置为 <code v-pre>${{ github.run_number }}</code> 变量。 
>
> 上传具有相同二进制文件（构建）和相同 `CFBundleVersion` 的预览将会失败。

## Tracks {#tracks}

Tracks 允许你将预览组织成命名组。例如，你可能有一个用于内部测试人员的 `beta` track，以及一个用于自动化构建的 `nightly` track。Track 是惰性创建的——只需在分享时指定 track 名称，如果它不存在，系统将自动创建。

要在特定 track 上分享预览，请使用 `--track` 选项：

```bash
tuist share App --track beta
tuist share App --track nightly
```

这适用于：
- **组织预览**：按用途对预览进行分组（例如，`beta`、`nightly`、`internal`）
- **应用内更新**：Tuist SDK 使用 tracks 来确定要通知用户哪些更新
- **过滤**：在 Tuist 仪表板中按 track 轻松查找和管理预览

> [!WARNING]
> **预览的可见性**
>
> 只有有权访问项目所属组织的人员才能访问预览。我们计划添加对过期链接的支持。

## Release notes {#release-notes}

使用 tracks 进行环境分组，并使用 release notes 说明单个构建的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes 是可选的纯文本，最多 10,000 个字符。第一个非空行在 Web 和 iOS 预览列表中显示为单行摘要，因此构建号和其他识别信息一目了然。长行会被截断；完整说明出现在详情页。两个列表中的搜索都会匹配显示名称和完整 release notes，包括摘要中未显示的行。支持多行说明，例如 `--release-notes "$(< release-notes.txt)"`。它们不会更改应用的显示名称或其 track。

### Compatibility {#preview-metadata-compatibility}

Release notes 是附加元数据，不是预览身份的一部分。来自旧客户端和新客户端的上传仍然在各平台中归入同一预览。保留第一个非空说明：后续上传可以填充之前缺失的说明，但不能覆盖现有说明。省略 `release_notes`、发送 `null` 或发送空字符串或仅含空格的字符串永远不会清除说明。现有预览不会回填，在没有说明的情况下仍然有效。

列表 API 的可选 `track` 查询参数不区分大小写地匹配整个 track 名称，与现有 track 存储一致。省略它或发送空值（`?track=`）以列出所有 tracks。Track 名称保持为开放字符串，而不是固定的值列表。iOS 应用的 **All Tracks** 选择会省略过滤器。iOS 应用的 track 标签从 `GET /api/projects/:account_handle/:project_handle/previews/tracks` 加载完整的项目摘要，权限与列出构建时的预览读取授权相同。该端点返回 `{total_count, tracks: [{name, count}]}`，包含排序后且不区分大小写分组的命名 tracks。计数涵盖整个项目，独立于分页、搜索和所选 track；总数包括未跟踪的预览。仅统计具有包标识符的可列出预览。列表 API 还接受可选的 `search`，用于匹配显示名称或完整 release notes 的字面量、不区分大小写的子串，并在分页前与 track 组合。现有的 `display_name` 过滤保持精确匹配。

旧客户端可以继续上传和列出预览，而无需发送任一字段。新客户端接受省略 track 或 notes 的旧响应，并忽略未来服务器添加的未知响应属性。API 集成也应忽略未知响应属性，以便附加元数据保持兼容。

自托管部署需要支持 release notes 和 track 过滤的服务器版本，以及更新的 CLI 和应用，才能使用这些功能。较旧的服务器可能会忽略 notes 或未知查询参数。如果 track 发现不可用，iOS 应用会保持未过滤浏览可用，并说明选择 track 需要更新的服务器。如果服务器在活动过滤器下仍返回其他 track 的预览，iOS 应用会报告不支持过滤，而不是呈现误导性结果。macOS 应用首先请求每个应用的最新兼容预览；在应用平台过滤器之前先选择不同应用的较旧服务器上，它会回退到分页历史记录，而不施加可能隐藏可用构建的截止条件。

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

为了让运行 Tuist Previews 更加轻松，我们开发了 Tuist macOS 菜单栏应用。你可以通过 [下载](https://tuist.dev/download) macOS 应用来代替通过 Tuist CLI 运行 Previews。你也可以通过运行 `brew install --cask tuist/tuist/tuist` 来安装该应用。

当你在预览页面点击“运行”时，macOS 应用会自动在你当前选定的设备上启动它。

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下载" style="height: 40px;">
    </a>
</div>

与 macOS 应用类似，Tuist iOS 应用简化了访问和运行预览的流程。每个预览都会显示其 track。使用原生搜索栏按应用名称查找预览，然后在 **Tracks** 下选择一个标签以按环境过滤。选中的标签为紫色；选择 **All** 可移除 track 过滤器。每个标签会显示该项目范围内的预览数量，“All”包含没有 track 的构建。搜索和 track 过滤适用于所有页面，而不仅限于已加载的预览。每个构建的 track 标签位于其 commit hash 旁边。

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **需要集成 Git 平台**
>
> 要获得自动的 pull/merge request 评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">远程项目</.localized_link> 与一个 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。

测试新功能应是任何代码审查的一部分。但必须在本地构建应用会增加不必要的摩擦，往往导致开发者完全跳过在设备上测试功能。但如果 *每个 pull request 都包含一个指向构建的链接，该链接能自动在你于 Tuist macOS 应用中选定的设备上运行应用，会怎样？*

一旦你的 Tuist 项目与如 [GitHub](https://github.com) 等 Git 平台连接，就在你的 CI 工作流中添加一个 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>。Tuist 随后会在你的 pull requests 中直接发布 Preview 链接：![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/github-app-with-preview.png)

## In-app update notifications {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 使你的应用能够检测何时有更新的预览版本可用并通知用户。这有助于让测试人员始终使用最新构建。

SDK 会在同一 **preview track** 内检查更新。当你使用 `--track` 并指定明确的 track 来分享预览时，SDK 将在该 track 上查找更新。如果未指定 track，则使用 git 分支作为 track——因此，从 `main` 分支构建的预览只会通知同样从 `main` 构建的更新预览。

### Installation {#sdk-installation}

将 Tuist SDK 添加为 Swift Package 依赖：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Monitor for updates {#sdk-monitor-updates}

使用 `monitorPreviewUpdates` 定期检查新的预览版本：

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

### Single update check {#sdk-single-check}

用于手动检查更新：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Stopping update monitoring {#sdk-stop-monitoring}

`monitorPreviewUpdates` 返回一个可取消的 `Task`：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 在模拟器和 App Store 构建中，更新检查会自动禁用。

## README badge {#readme-badge}

为了让 Tuist Previews 在你的仓库中更显眼，你可以在 `README` 文件中添加一个指向最新 Tuist Preview 的徽章：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

要将徽章添加到你的 `README`，请使用以下 markdown 并将账户和项目句柄替换为你自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果你的项目包含多个具有不同 bundle identifier 的应用，你可以通过添加 `bundle-id` 查询参数来指定链接到哪个应用的预览：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automations {#automations}

你可以使用 `--json` 标志从 `tuist share` 命令获取 JSON 输出：
```
tuist share --json
```

JSON 输出对于创建自定义自动化非常有用，例如使用你的 CI 提供商发布 Slack 消息。JSON 包含一个带有完整预览链接的 `url` 键，以及一个带有二维码图片 URL 的 `qrCodeURL` 键，以便更轻松地从真实设备下载预览。以下是 JSON 输出的示例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
