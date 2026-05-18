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
