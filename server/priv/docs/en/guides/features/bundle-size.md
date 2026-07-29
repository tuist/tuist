---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Monitor your app's bundle size and memory footprint with Tuist Bundle Insights."
}
---
# Bundle insights {#bundle-size}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>


As you add more features to your app, your app bundle size keeps growing. While some of the bundle size growth is inevitable as you ship more code and assets, there are many ways to minimize that growth, such as by ensuring your assets are not duplicated across your bundles or stripping unused binary symbols. Tuist Bundle Insights supports both **Apple** and **Android** bundles, providing you with tools and insights to help your app size stay small, and we also monitor your app size over time.

## Usage {#usage}

To analyze a bundle, you can use the `tuist inspect bundle` command:

### Apple {#usage-apple}

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

### Android {#usage-android}

::: code-group
```bash [Analyze an .aab (recommended)]
tuist inspect bundle App.aab
```
```bash [Analyze an .apk]
tuist inspect bundle App.apk
```
<!-- -->
:::

The `tuist inspect bundle` command analyzes the bundle and provides you with a link to see a detailed overview of the bundle including a scan of the contents of the bundle or a module breakdown:

![Analyzed bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## Understanding bundle sizes {#understanding-sizes}

For every analyzed bundle, Tuist reports two values:

- **Install size**: the space the app takes up once installed on a device.
- **Download size**: the compressed size users download. For Apple bundles, this is only available when you analyze an `.ipa` (it is the size of the `.ipa` archive); it is not reported for `.xcarchive` or `.app` inputs.

Sizes are stored in bytes and displayed using the decimal convention, where 1 MB is 1,000,000 bytes and 1 GB is 1,000,000,000 bytes. This is the same convention Apple uses to report storage and app sizes (see [How storage capacity is measured on Apple devices](https://support.apple.com/en-us/102119)). For example, an install size of 733,446,863 bytes is shown as 733.4 MB.

### Comparing with App Store Connect {#app-store-connect}

Tuist measures the bundle exactly as you provide it and does not apply [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size). The reported sizes therefore correspond to the **universal** (unthinned) variant, the row labeled "Universal" in App Store Connect's app file sizes report, rather than the per-device variants.

When comparing the two, expect the numbers to be in the same range as the Universal row, but not identical:

- **Install size** is close to the Universal install size. App Store Connect reports a slightly higher value because it includes on-device overhead, such as filesystem block allocation and Apple's own estimation, that a raw file-size measurement does not capture.
- **Download size** is lower than the Universal download size. Apple encrypts the app binary after you upload it, and encrypted data compresses less efficiently, so the App Store's compressed download ends up larger than the `.ipa` archive Tuist measures. This happens on Apple's side after upload, so it is not reflected in Tuist's number.

The per-device rows in App Store Connect are smaller again, because app thinning removes the CPU architectures and asset variants that a specific device does not need. Tuist does not currently report per-device (thinned) sizes.

## Continuous integration {#continuous-integration}

To track bundle size over time, you will need to analyze the bundle on the CI. First, you will need to ensure that your CI is <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>:

An example workflow for GitHub Actions could then look like this:

::: code-group
```yaml [Apple]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

Once set up, you will be able to see how your bundle size evolves over time:

![Bundle size graph](/images/guides/features/bundle-size/bundle-size-graph.png)

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **Integration With Git Platform Required**
>
> To get automatic pull/merge request comments, integrate your <.localized_link href="/guides/server/accounts-and-projects">Tuist project</.localized_link> with a <.localized_link href="/guides/server/authentication">Git platform</.localized_link>.


Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), Tuist will post a comment directly in your pull/merge requests whenever you run `tuist inspect bundle`:
![GitHub app comment with inspected bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)

## Size thresholds {#size-thresholds}

> [!WARNING]
> **Integration With Git Forge Required**
>
> To use size thresholds, connect the [Tuist GitHub App](https://github.com/apps/tuist) to your project. You can do this from your project's integrations page.


Size thresholds let you block pull requests when the bundle size increases beyond a configured percentage compared to a baseline branch. When a threshold is violated, Tuist creates a GitHub Check Run on the PR commit, blocking the merge until the size increase is resolved:

![PR status check showing bundle size threshold exceeded](/images/guides/features/bundle-size/github-pr-check-status.png)

The check run shows the baseline size, current size, and percentage change. If the increase is intentional, you can accept it directly from the GitHub UI by clicking the **Accept** button:

![GitHub check run showing threshold violation](/images/guides/features/bundle-size/github-check-run-threshold.png)

### Configuration {#size-thresholds-configuration}

To configure thresholds, go to your project's **Settings > Bundles** tab:

![Bundle size thresholds settings](/images/guides/features/bundle-size/bundle-size-thresholds.png)
