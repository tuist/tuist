---
title: Bundle Size
titleTemplate: :title · Develop · Guides · Tuist
description: Find out how to make and keep your app's memory footprint as small as possible.
---

# Bundle Size {#bundle-size}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

As you add more features to your app, your app bundle size keeps growing. While some of the bundle size growth is inevitable as you ship more code and assets, there are many ways to minimze that growth, such as by ensuring your assets are not duplicated across your bundles or stripping unused binary symbols. Tuist provides you with tools and insights to help your app size stay small – and we also monitor your app size over time.

## 사용법 {#usage}

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

:::

The `tuist inspect bundle` command analyzes the bundle and provides you with a link to see a detailed overview of the bundle including a scan of the contents of the bundle or a module breakdown:

![Analyzed bundle](/images/guides/develop/bundle-size/analyzed-bundle.png)

## Continuous integration {#continuous-integration}

To track bundle size over time, you will need to analyze the bundle on the CI. First, you will need to ensure that your CI is <LocalizedLink href="/guides/automate/continuous-integration#authentication">authenticated</LocalizedLink>:

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
          TUIST_CONFIG_TOKEN: ${{ secrets.TUIST_CONFIG_TOKEN }}
```

Once set up, you will be able to see how your bundle size evolves over time:

![Bundle size graph](/images/guides/develop/bundle-size/bundle-size-graph.png)

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] GIT 플랫폼 연동 필요\
> 자동으로 pull/merge request 의견을 받으려면, <0>Tuist 프로젝트</0>를 <1>Git 플랫폼</1>과 연동해야 합니다.

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), Tuist will post a comment directly in your pull/merge requests whenever you run `tuist inspect bundle`:
![GitHub app comment with inspected bundles](/images/guides/develop/bundle-size/github-app-with-bundles.png)
