---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle insights · Features · Guides · Tuist",
  "description": "Analyze iOS, iPadOS, macOS, watchOS, and tvOS bundles (.ipa, .xcarchive, .app) with Tuist Bundle Insights."
}
---
# Apple {#bundle-insights-apple}

Analyze an Apple bundle by pointing `tuist inspect bundle` at an archive, an installable, or a built app:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

When you pass an app name instead of a path on macOS, Tuist resolves the built `.app` from Xcode's build products (honoring `--derived-data-path` when set), the same way `tuist share` does.

The command uploads the bundle to Tuist and returns a link to a detailed overview, including a scan of the contents and a module breakdown:

![Analyzed bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## Comparing with App Store Connect {#app-store-connect}

Tuist measures the bundle exactly as you provide it and does not apply [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). The reported sizes correspond to the **universal** (unthinned) variant — the row labeled "Universal" in App Store Connect's app file sizes report — not the per-device variants.

Expect the numbers to be in the same range as the Universal row, but not identical:

- **Install size** is close to the Universal install size. App Store Connect reports a slightly higher value because it includes on-device overhead, such as filesystem block allocation and Apple's own estimation, that a raw file-size measurement does not capture.
- **Download size** is lower than the Universal download size. Apple encrypts the app binary after upload, and encrypted data compresses less efficiently, so the App Store's compressed download ends up larger than the `.ipa` archive Tuist measures. This happens on Apple's side after upload, so it is not reflected in Tuist's number.

The per-device rows in App Store Connect are smaller again, because app thinning removes CPU architectures and asset variants that a specific device does not need. Tuist does not currently report per-device (thinned) sizes.

<!-- @snippet: ./_shared -->

