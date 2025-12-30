---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Bundle insights {#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

As you add more features to your app, your app bundle size keeps growing. While some of the bundle size growth is inevitable as you ship more code and assets, there are many ways to minimze that growth, such as by ensuring your assets are not duplicated across your bundles or stripping unused binary symbols. Tuist provides you with tools and insights to help your app size stay small – and we also monitor your app size over time.

## Usage {#usage}

To analyze a bundle, you can use the `tuist inspect bundle` command:

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
<!-- -->
:::

The `tuist inspect bundle` command analyzes the bundle and provides you with a link to see a detailed overview of the bundle including a scan of the contents of the bundle or a module breakdown:

![Analyzed bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## Continuous integration {#continuous-integration}

To track bundle size over time, you will need to analyze the bundle on the CI. First, you will need to ensure that your CI is <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>:

An example workflow for GitHub Actions could then look like this:

```yaml
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

Once set up, you will be able to see how your bundle size evolves over time:

![Bundle size graph](/images/guides/features/bundle-size/bundle-size-graph.png)

## Pull/merge request comments {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
To get automatic pull/merge request comments, integrate your <LocalizedLink href="/guides/server/accounts-and-projects">Tuist project</LocalizedLink> with a <LocalizedLink href="/guides/server/authentication">Git platform</LocalizedLink>.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), Tuist will post a comment directly in your pull/merge requests whenever you run `tuist inspect bundle`:
![GitHub app comment with inspected bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
