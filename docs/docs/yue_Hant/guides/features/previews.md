---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Previews {#previews}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

When building an app, you may want to share it with others to get feedback.
Traditionally, this is something that teams do by building, signing, and pushing
their apps to platforms like Apple's
[TestFlight](https://developer.apple.com/testflight/). However, this process can
be cumbersome and slow, especially when you're just looking for quick feedback
from a colleague or a friend.

To make this process more streamlined, Tuist provides a way to generate and
share previews of your apps with anyone.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
When building for device, it is currently your responsibility to ensure the app
is signed correctly. We plan to streamline this in the future.
<!-- -->
:::

::: code-group
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

The command will generate a link that you can share with anyone to run the app –
either on a simulator or an actual device. All they'll need to do is to run the
command below:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

When sharing an `.ipa` file, you can download the app directly from the mobile
device using the Preview link. The links to `.ipa` previews are by default
_public_. In the future, you will have an option to make them private, so that
the recipient of the link would need to authenticate with their Tuist account to
download the app.

`tuist run` also enables you to run a latest preview based on a specifier such
as `latest`, branch name, or a specific commit hash:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Ensure the `CFBundleVersion` (build version) is unique by leveraging a CI run
number that most CI providers expose. For example, in GitHub Actions you can set
the `CFBundleVersion` to the <code v-pre>${{ github.run_number }}</code>
variable.

Uploading a preview with the same binary (build) and the same `CFBundleVersion`
will fail.
<!-- -->
:::

## Tracks {#tracks}

Tracks allow you to organize your previews into named groups. For example, you
might have a `beta` track for internal testers and a `nightly` track for
automated builds. Tracks are lazily created — simply specify a track name when
sharing, and it will be created automatically if it doesn't exist.

To share a preview on a specific track, use the `--track` option:

```bash
tuist share App --track beta
tuist share App --track nightly
```

This is useful for:
- **Organizing previews**: Group previews by purpose (e.g., `beta`, `nightly`,
  `internal`)
- **In-app updates**: The Tuist SDK uses tracks to determine which updates to
  notify users about
- **Filtering**: Easily find and manage previews by track in the Tuist dashboard

::: warning PREVIEWS' VISIBILITY
<!-- -->
Only people with access to the organization the project belongs to can access
the previews. We plan to add support for expiring links.
<!-- -->
:::

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

To make running Tuist Previews even easier, we developed a Tuist macOS menu bar
app. Instead of running Previews via the Tuist CLI, you can
[download](https://tuist.dev/download) the macOS app. You can also install the
app by running `brew install --cask tuist/tuist/tuist`.

When you now click on "Run" in the Preview page, the macOS app will
automatically launch it on your currently selected device.

::: warning REQUIREMENTS
<!-- -->
You need to have Xcode locally installed and be on macOS 14 or later.
<!-- -->
:::

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Similarly to the macOS app, the Tuist iOS apps streamlines accessing and running
your previews.

## Pull/merge request comments {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
To get automatic pull/merge request comments, integrate your
<LocalizedLink href="/guides/server/accounts-and-projects">remote project</LocalizedLink> with a
<LocalizedLink href="/guides/server/authentication">Git platform</LocalizedLink>.
<!-- -->
:::

Testing new functionality should be a part of any code review. But having to
build an app locally adds unnecessary friction, often leading to developers
skipping testing functionality on their device at all. But *what if each pull
request contained a link to the build that would automatically run the app on a
device you selected in the Tuist macOS app?*

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), add a <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> to your CI workflow. Tuist will then post a Preview
link directly in your pull requests: ![GitHub app comment with a Tuist Preview
link](/images/guides/features/github-app-with-preview.png)


## In-app update notifications {#in-app-update-notifications}

The [Tuist SDK](https://github.com/tuist/sdk) enables your app to detect when a
newer preview version is available and notify users. This is useful for keeping
testers on the latest build.

The SDK checks for updates within the same **preview track**. When you share a
preview with an explicit track using `--track`, the SDK will look for updates on
that track. If no track is specified, the git branch is used as the track — so a
preview built from the `main` branch will only notify about newer previews also
built from `main`.

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

::: info
<!-- -->
Update checking is automatically disabled on simulators and App Store builds.
<!-- -->
:::

## README badge {#readme-badge}

To make Tuist Previews more visible in your repository, you can add a badge to
your `README` file that points to the latest Tuist Preview:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

To add the badge to your `README`, use the following markdown and replace the
account and project handles with your own:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

If your project contains multiple apps with different bundle identifiers, you
can specify which app's preview to link to by adding a `bundle-id` query
parameter:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automations {#automations}

You can use the `--json` flag to get a JSON output from the `tuist share`
command:
```
tuist share --json
```

The JSON output is useful to create custom automations, such as posting a Slack
message using your CI provider. The JSON contains a `url` key with the full
preview link and a `qrCodeURL` key with the URL to the QR code image to make it
easier to download previews from a real device. An example of a JSON output is
below:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
