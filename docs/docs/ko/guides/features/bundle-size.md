---
title: Bundle Size
titleTemplate: :title · Features · Guides · Tuist
description: 앱의 메모리 사용량을 최소화하고 이를 유지하는 방법을 배워봅니다.
---

# Bundle Size {#bundle-size}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

앱에 기능을 추가할수록 앱 번들 크기는 커지게 됩니다. 더 많은 코드와 에셋으로 인해 어느 정도의 번들 크기는 증가하지만 에셋이 번들 간에 중복되지 않도록 하거나 사용하지 않는 바이너리 심볼을 제거하는 등 크기를 최적화할 수 있는 많은 방법이 있습니다. Tuist는 앱 크기를 작게 유지할 수 있도록 툴과 인사이트를 제공하며, 지속적으로 앱 크기를 모니터링합니다.

## 사용법 {#usage}

`tuist inspect bundle` 명령어를 사용하여, 번들을 분석할 수 있습니다:

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

`tuist inspect bundle` 명령어는 번들을 분석하고 번들의 구성 내용이나 모듈별 분포 등 상세 내용을 링크로 제공합니다:

![Analyzed bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## Continuous integration {#continuous-integration}

번들 크기를 추적하려면 CI에서 번들 분석을 해야 합니다. 먼저, CI는 <LocalizedLink href="/guides/automate/continuous-integration#authentication">인증</LocalizedLink>되어 있는지 확인해야 합니다:

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

설정이 완료되면, 번들 크기가 시간에 따라 어떻게 변화하는지 확인할 수 있습니다:

![Bundle size graph](/images/guides/features/bundle-size/bundle-size-graph.png)

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] GIT 플랫폼 연동 필요\
> 자동으로 pull/merge request 의견을 받으려면, <0>Tuist 프로젝트</0>를 <1>Git 플랫폼</1>과 연동해야 합니다.

Tuist 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼과 연결되면, `tuist inspect bundle`을 수행할 때마다 Tuist가 Pull Request나 Merge Request 시 직접 댓글을 남깁니다:
![GitHub app comment with inspected bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
