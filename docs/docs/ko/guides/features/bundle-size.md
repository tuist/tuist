---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# 번들 인사이트 {#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

앱에 더 많은 기능을 추가하면 앱 번들 크기가 계속 커집니다. 더 많은 코드와 에셋을 제공하면 번들 크기가 커지는 것은 불가피하지만, 에셋이
번들 간에 중복되지 않도록 하거나 사용하지 않는 바이너리 심볼을 제거하는 등 여러 가지 방법으로 크기를 최소화할 수 있습니다. 튜이스트는 앱
크기를 작게 유지하는 데 도움이 되는 도구와 인사이트를 제공하며, 시간이 지남에 따라 앱 크기를 모니터링합니다.

## 사용량 {#usage}

번들을 분석하려면 `tuist inspect bundle` 명령을 사용할 수 있습니다:

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

`tuist 검사 번들` 명령은 번들을 분석하고 번들의 내용 스캔 또는 모듈 분석을 포함하여 번들에 대한 자세한 개요를 볼 수 있는 링크를
제공합니다:

![분석된 번들](/images/guides/features/bundle-size/analyzed-bundle.png)

## 지속적 통합 {#continuous-integration}

시간 경과에 따른 번들 크기를 추적하려면 CI의 번들을 분석해야 합니다. 먼저 CI가 <LocalizedLink href="/guides/integrations/continuous-integration#authentication">인증</LocalizedLink>되었는지 확인해야 합니다:

그러면 GitHub 액션의 워크플로 예시는 다음과 같습니다:

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

설정이 완료되면 시간이 지남에 따라 번들 크기가 어떻게 변하는지를 확인할 수 있습니다:

![번들 크기 그래프](/images/guides/features/bundle-size/bundle-size-graph.png)

## 요청 댓글 풀/병합 {#pullmerge-request-comments}

::: warning GIT PLATFORM INTEGRATION REQUIRED
<!-- -->
자동 풀/병합 요청 코멘트를 받으려면 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 프로젝트</LocalizedLink>를 <LocalizedLink href="/guides/server/authentication">Git 플랫폼</LocalizedLink>과 통합하세요.
<!-- -->
:::

튜이스트 프로젝트가 [GitHub](https://github.com)와 같은 Git 플랫폼에 연결되면, 튜이스트는 풀/머지 요청을 실행할
때마다 `tuist 검사 번들`: ![검사된 번들이 있는 GitHub 앱
코멘트](/images/guides/features/bundle-size/github-app-with-bundles.png)에 직접 코멘트를
게시합니다.
