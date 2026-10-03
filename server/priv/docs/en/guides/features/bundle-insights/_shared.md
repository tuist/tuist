## Understanding bundle sizes {#understanding-sizes}

For every analyzed bundle, Tuist reports two values:

- **Install size**: the space the app takes up once installed on a device.
- **Download size**: the compressed size users download. For Apple bundles this is only reported for `.ipa` (the size of the archive); for `.xcarchive` or `.app` inputs it is not available.

Sizes are stored in bytes and displayed using the decimal convention, where 1 MB is 1,000,000 bytes and 1 GB is 1,000,000,000 bytes — the same convention Apple uses to report storage and app sizes (see [How storage capacity is measured on Apple devices](https://support.apple.com/en-us/102119)). An install size of 733,446,863 bytes shows as 733.4 MB.

## Continuous integration {#continuous-integration}

To track bundle size over time, analyze the bundle on CI. First, make sure your CI is <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

Tuist also needs to know which project to report the bundle to. If you have not connected the project yet, run `tuist init`, or declare the handle yourself:

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Use <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> for projects without a Swift manifest, such as Gradle projects. When both files are present, `Tuist.swift` takes precedence.

An example GitHub Actions workflow:

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

Once set up, you can see how your bundle size evolves over time:

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

### Restricting who can accept {#size-thresholds-approvals}

By default anyone with write access to the repository can accept a size increase, because that is who GitHub shows the button to. To narrow it, set **Who can accept** under **Settings > Bundles**:

- **Anyone**: the default. Anyone with write access to the repository.
- **Selected GitHub users**: only the GitHub usernames you add.

Someone not on the list leaves the check failing with an explanation, and the button stays for whoever can use it.
