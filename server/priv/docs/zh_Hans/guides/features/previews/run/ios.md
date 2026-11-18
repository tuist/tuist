---
{
  "title": "使用 iPhone App 运行预览",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "通过 Tuist iOS App 查找、筛选并访问 Apple 预览。"
}
---
# 使用 iPhone App 运行预览

从 App Store 安装 [Tuist iOS App](https://apps.apple.com/us/app/tuist/id6748460335)，以查找并访问你的 Apple 预览版。发布工作流的签名和设备资格要求仍然适用。

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下载" style="height: 40px;">
    </a>
</div>

按应用名称或发行说明搜索，然后选择一个轨道来过滤预览。选择 **全部** 可浏览所有轨道，包括没有分配轨道的预览。打开预览以阅读完整的发行说明。

## 客户端与服务器兼容性 {#client-and-server-compatibility}

保持 Tuist App 为最新版本。如果你自托管 Tuist，请更新服务器以使用轨道过滤和发行说明功能。在较旧的服务器上，你仍可以不加过滤地浏览预览。

## 应用内更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 使你的 Apple 应用能够检测到更新的预览版并通知测试人员。它会在同一 **预览轨道** 内检查更新。对于使用 `tuist share --track` 发布的预览，它会使用该显式指定的轨道。如果没有显式指定轨道，则使用 git 分支，因此从 `main` 构建的预览只会通知来自 `main` 的更新预览。

### 安装 {#sdk-installation}

将 Tuist SDK 添加为 Swift Package 依赖项：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 监控更新 {#sdk-monitor-updates}

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

### 单次更新检查 {#sdk-single-check}

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

### 停止更新监控 {#sdk-stop-monitoring}

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
