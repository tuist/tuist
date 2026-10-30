---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share iOS and Android app builds instantly with Tuist Previews. Give teammates and stakeholders a link, no TestFlight or Play Console setup required."
}
---
# Previews {#previews}

Tuist Previews let teammates test your application without rebuilding it locally or waiting for a TestFlight or Play Console release. Publish a build to your Tuist project, then share its preview link.

Choose your build system for setup, signing requirements, and publication commands:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Share applications from existing Xcode projects or Tuist-generated projects."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Build an Android APK with Gradle and share it with the Tuist CLI."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="Publish signed Android, Apple simulator, and macOS applications with companion Bazel rules."
    link="/guides/features/previews/bazel"
  />
</.home_cards>

## Run a preview {#run-a-preview}

After publishing, share the returned preview link. Recipients can run a compatible build on a connected device or simulator:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

When sharing an `.ipa` file, you can download the app directly from the mobile device using the Preview link.
The links to `.ipa` previews are by default _private_, meaning the recipient needs to authenticate with their Tuist account to download the app. You can change this to public in the project settings if you want to share the app with anyone.

`tuist run` also enables you to run a latest preview based on a specifier such as `latest`, branch name, or a specific commit hash:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

## Publish from Once {#publish-from-once}

Existing Once integrations have a separate <.localized_link href="/guides/features/previews/once">artifact publication guide</.localized_link>. Publication remains separate from cached graph execution.

## Publish from Bazel {#publish-from-bazel}

See the <.localized_link href="/guides/features/previews/bazel">Bazel preview guide</.localized_link> for the application rules, runtime publication consent, and cache replay behavior.

## Desktop apps and CLIs {#desktop-apps-and-clis}

Share a built macOS application bundle and launch it on another Mac without rebuilding:

```bash
tuist share path/to/MyApp.app
tuist run {preview-url}
```

You can also share a standalone executable on macOS or Linux:

```bash
tuist share path/to/my-tool
tuist run {preview-url} -- --help
```

If the CLI needs resource bundles, dynamic libraries, or helper executables, assemble a distribution directory and specify its entry point relative to that directory:

```bash
tuist share path/to/distribution --executable bin/my-tool
tuist run {preview-url} -- build --configuration Release
```

The entire distribution directory is uploaded, including executable permissions and directory structure. The preview runs with the recipient's working directory, environment, and terminal input/output, and returns the executable's exit status. It does not replace an installed CLI or add it to `PATH`. CLI distributions remain in Tuist's local `previews` cache after execution so generated projects can continue to reference them; deleting that cache also removes those references' targets.

Use `--` to separate Tuist options from the preview's arguments. Everything after it is forwarded literally, including `--verbose`, `--quiet`, and `--path`. Child arguments are excluded from Tuist command analytics.

### Multiple CLI targets {#multiple-cli-targets}

A preview groups builds of the same CLI for one commit; each build contains a distribution for one operating system and one or more CPU architectures. For example, one preview can contain macOS arm64, macOS x86_64, and Linux x86_64 distributions. A universal macOS executable covers both Mac architectures in one build.

Build each target separately, then publish the distributions sequentially from the same Git checkout using the same entry-point basename and track:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

These uploads add builds to the same preview link. Keep the project, commit, publishing account, CLI name, and track identical across uploads. Build directory names do not determine compatibility: Tuist reads the executable headers at upload and selects the recipient's operating system and CPU architecture before downloading a build. Recipients use the same `tuist run {preview-url} -- …` command on either OS, without architecture flags. Tuist verifies the downloaded executable's target before execution; older previews without architecture metadata use this check to find a compatible build. An unavailable target produces a compatibility error rather than running another platform's build. The repository's automated Tuist CLI publisher currently builds only native macOS; Linux distributions can be published separately.

### Client and server compatibility {#client-and-server-compatibility}

Desktop execution requires an updated CLI and server. Existing clients continue to upload and run mobile previews against an updated server. New clients can still use mobile previews on older servers; an older server cannot accept the new CLI format.

The CLI automatically sends `x-tuist-preview-capabilities: desktop` when reading or completing previews. Without that capability, the API returns only the original app formats and platforms, including for previews that contain both mobile and CLI builds. Update checks select the latest compatible build. Opening a CLI-only preview from an older client returns an upgrade message. Architecture metadata is optional, and clients ignore unknown future build formats and platforms rather than failing to decode the preview.

For self-hosted upgrades, migrate and upgrade **all** server replicas and workers that read previews before publishing CLI previews. Canary and production require explicit `cli_previews` account or global feature-flag enrollment after that rollout; mobile uploads do not depend on this flag. Keep automated CLI publication disabled until enrollment. Once executable or Linux records exist, do not roll back to a server version that cannot read those stored enum values. Turning off the flag stops new CLI uploads, but does not make existing records readable by those older servers.

Previews are not a cross-compilation or dependency-bundling service. Include non-system dependencies and use relocatable library/resource paths. Tuist reads the executable's Mach-O or ELF header to identify its OS and CPU architectures, including universal macOS binaries, and selects a compatible build. Linux binaries still need compatible system libraries (for example, glibc and the Swift runtime); prefer self-contained distributions targeting your recipients' oldest supported OS. Scripts must have a shebang and require their interpreter on the recipient's system; they use the publisher's OS as their target.

A preview does not provide a sandbox: it runs as the current user with access to their files and environment. Only run builds from authors and pull requests you trust. Signing and notarization requirements still apply to macOS applications.

To share the Tuist CLI from CI, include its `ProjectDescription` library/module and resource bundles alongside the executable, rather than uploading the binary alone. The preview retains the commit and branch metadata used by the existing pull-request integration.

In the Tuist repository, `mise run cli:preview build/cli-preview` assembles a native macOS distribution with `ProjectDescription.framework`, templates, resource bundles, Swift runtime libraries, and the CAS plugin/proxy. Upload it with `build/cli-preview/tuist share build/cli-preview --executable tuist`. The CLI Previews workflow publishes non-fork PRs once the repository variable `TUIST_CLI_PREVIEWS_ENABLED` is enabled, after deploying server support and releasing a recipient CLI with preview support. These development builds are ad-hoc signed, not notarized releases.

## Tracks {#tracks}

Tracks allow you to organize your previews into named groups. For example, you might have a `beta` track for internal testers and a `nightly` track for automated builds. Tracks are lazily created — simply specify a track name when sharing, and it will be created automatically if it doesn't exist.

To share a preview on a specific track, use the `--track` option:

```bash
tuist share App --track beta
tuist share App --track nightly
```

This is useful for:
- **Organizing previews**: Group previews by purpose (e.g., `beta`, `nightly`, `internal`)
- **In-app updates**: The Tuist SDK uses tracks to determine which updates to notify users about
- **Filtering**: Easily find and manage previews by track in the Tuist dashboard

> [!WARNING]
> **Previews' Visibility**
>
> Previews use the project's default visibility. Private previews require authentication and project access; make previews public in project settings only when the application can be shared with anyone.

## Release notes {#release-notes}

Use tracks for environment groups and release notes for the purpose of an individual build:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes are optional plain text, up to 10,000 characters. The first nonblank line appears as a single-line snippet in web and iOS preview lists, so build numbers and other identifying information are visible at a glance. Long lines are truncated; full notes appear on the detail pages. Search in both lists matches display names and full release notes, including lines not shown in the snippet. Multiline notes are supported, for example `--release-notes "$(< release-notes.txt)"`. They do not change the app's display name or its track.

### Compatibility {#preview-metadata-compatibility}

Release notes are additive metadata, not part of a preview's identity. Uploads from old and new clients still group into the same preview across platforms. The first nonblank notes are retained: a later upload can fill notes that were previously absent, but cannot overwrite existing notes. Omitting `release_notes`, sending `null`, or sending an empty or whitespace-only string never clears notes. Existing previews are not backfilled and remain valid without notes.

The list API's optional `track` query parameter matches a whole track name, case-insensitively, consistent with existing track storage. Omit it or send an empty value (`?track=`) to list all tracks. Track names remain open strings, not a fixed list of values. The iOS app's **All Tracks** selection omits the filter. The iOS app's track pills load the complete project summary from `GET /api/projects/:account_handle/:project_handle/previews/tracks`, under the same preview-read authorization as listing builds. That endpoint returns `{total_count, tracks: [{name, count}]}` with sorted, case-insensitively grouped named tracks. Counts cover the whole project independently of pagination, search, and the selected track; the total includes untracked previews. Only listable previews with a bundle identifier are counted. The list API also accepts optional `search` for a literal, case-insensitive substring of the display name or full release notes, combined with the track before pagination. Existing `display_name` filtering remains exact.

Old clients can continue uploading and listing previews without sending either field. New clients accept older responses that omit track or notes, and ignore unknown response properties added by future servers. API integrations should likewise ignore unknown response properties so additive metadata remains compatible.

Self-hosted deployments need a server version that supports release notes and track filtering, together with an updated CLI and app, to use these features. Older servers may ignore notes or unknown query parameters. If track discovery is unavailable, the iOS app keeps unfiltered browsing available and explains that selecting a track requires an updated server. If a server returns previews from another track despite an active filter, the iOS app reports that filtering is unsupported rather than presenting misleading results. The macOS app first requests the latest compatible preview per app; on older servers that select distinct apps before applying platform filters, it falls back to paginated history without imposing a cutoff that could hide an available build.

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

To make running Tuist Previews even easier, we developed a Tuist macOS menu bar app. Instead of running Previews via the Tuist CLI, you can [download](https://tuist.dev/download) the macOS app. You can also install the app by running `brew install --cask tuist/tuist/tuist`.

When you now click on "Run" in the Preview page, the macOS app will automatically launch it on your currently selected device.

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Similarly to the macOS app, the Tuist iOS app streamlines accessing and running your previews. Each preview shows its track. Use the native search field to find previews by app name, then select a pill under **Tracks** to filter by environment. The selected pill is purple; choose **All** to remove the track filter. Each pill shows its project-wide preview count, and All includes builds without a track. Search and track filtering apply across pages, not just to previews already loaded. Each build's track tag sits beside its commit hash.

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **Integration With Git Platform Required**
>
> To get automatic pull/merge request comments, integrate your <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> with a <.localized_link href="/guides/server/authentication">Git platform</.localized_link>.

Testing new functionality should be a part of any code review. But having to build an app locally adds unnecessary friction, often leading to developers skipping testing functionality on their device at all. But *what if each pull request contained a link to the build that would automatically run the app on a device you selected in the Tuist macOS app?*

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), add a <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> to your CI workflow. Tuist will then post a Preview link directly in your pull requests:
![GitHub app comment with a Tuist Preview link](/images/guides/features/github-app-with-preview.png)

## In-app update notifications {#in-app-update-notifications}

The [Tuist SDK](https://github.com/tuist/sdk) enables your app to detect when a newer preview version is available and notify users. This is useful for keeping testers on the latest build.

The SDK checks for updates within the same **preview track**. When you share a preview with an explicit track using `--track`, the SDK will look for updates on that track. If no track is specified, the git branch is used as the track — so a preview built from the `main` branch will only notify about newer previews also built from `main`.

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

## README badge {#readme-badge}

To make Tuist Previews more visible in your repository, you can add a badge to your `README` file that points to the latest Tuist Preview:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

To add the badge to your `README`, use the following markdown and replace the account and project handles with your own:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

If your project contains multiple apps with different bundle identifiers, you can specify which app's preview to link to by adding a `bundle-id` query parameter:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automations {#automations}

You can use the `--json` flag to get a JSON output from the `tuist share` command:
```
tuist share --json
```

The JSON output is useful to create custom automations, such as posting a Slack message using your CI provider.
The JSON contains a `url` key with the full preview link and a `qrCodeURL` key with the URL to the QR code image
to make it easier to download previews from a real device. An example of a JSON output is below:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
