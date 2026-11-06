---
{
  "title": "Run previews with the iPhone app",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Find, filter, and access Apple previews with the Tuist iOS app."
}
---
# Run previews with the iPhone app

Install the [Tuist iOS app from the App Store](https://apps.apple.com/us/app/tuist/id6748460335) to find and access your Apple previews. The publication workflow's signing and device eligibility requirements still apply.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Search by app name or release notes, then select a track to filter previews. Choose **All** to browse every track, including previews without a track. Open a preview to read its full release notes.

## Client and server compatibility {#client-and-server-compatibility}

Keep the Tuist app up to date. If you self-host Tuist, update your server to use track filtering and release notes. You can still browse previews without filtering on older servers.

## In-app update notifications {#in-app-update-notifications}

The [Tuist SDK](https://github.com/tuist/sdk) enables your Apple app to detect a newer preview and notify testers. It checks for updates within the same **preview track**. For previews published with `tuist share --track`, it uses that explicit track. Without an explicit track, the git branch is used, so a preview built from `main` only notifies about newer previews from `main`.

### Installation {#sdk-installation}

Add Tuist SDK as a Swift Package dependency:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Monitor for updates {#sdk-monitor-updates}

Use `monitorPreviewUpdates` to periodically check for new preview versions:

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

For manual update checking:

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

`monitorPreviewUpdates` returns a `Task` that can be cancelled:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> Update checking is automatically disabled on simulators and App Store builds.
