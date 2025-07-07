---
title: Previews
titleTemplate: :title · Features · Guides · Tuist
description: 앱 미리보기를 생성하고 다른 사람과 공유하는 방법을 알아보세요.
---

# Previews {#previews}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

앱을 개발할 때 다른 사람들의 피드백을 받기 위해 앱을 공유하고 싶을 수 있습니다.
전통적으로, 팀들은 앱을 빌드하고 서명한 후 Apple의 [TestFlight](https://developer.apple.com/testflight/)와 같은 플랫폼에 업로드하여 이 작업을 수행해왔습니다.
하지만, 이 과정은 번거롭고 느릴 수 있으며, 특히 동료나 친구로부터 빠른 피드백을 받고자 할 때는 더욱 그렇습니다.

Tuist는 이러한 과정을 간소화하기 위해 앱 미리보기를 생성하고 다른 사람과 공유할 수 있는 방법을 제공합니다.

> [!IMPORTANT] DEVICE(실기기) 빌드 시 서명 필요
> DEVICE용으로 빌드할 때, 앱이 올바르게 서명되었는지 확인하는 책임은 사용자에게 있습니다. 우리는 향후 이 과정을 더 간소화할 계획입니다.

:::code-group

```bash [Tuist Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # simulator용 앱 빌드
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # device용 앱 빌드
tuist share App --configuration Debug --platforms iOS
```

```bash [Xcode Project]
tuist build App # simulator용 앱 빌드
tuist build App -- -destination 'generic/platform=iOS' # device용 앱 빌드
tuist share App
```

:::

이 명령어는 앱을 시뮬레이터나 실기기에서 실행할 수 있는 공유 가능한 링크를 생성합니다. 사용자가 해야 할 일은 아래 명령어를 실행하는 것뿐입니다:

```bash
tuist run {url}
tuist run {url} --device "My iPhone" # 특정 기기에서 앱 실행하기
```

Preview 링크를 통해 모바일 기기에서 직접 `.ipa` 파일을 다운로드하여 앱을 설치할 수 있습니다.
`.ipa` preview 링크는 기본적으로 _public_ 으로 설정되어 있어 누구나 접근할 수 있습니다. 추후에는 링크를 private으로 설정할 수 있는 옵션이 제공될 예정이며, 이 경우 Tuist 계정으로 인증해야만 앱을 다운로드할 수 있습니다.

`tuist run` 명령어를 사용하면 `latest`, branch 이름, 또는 특정 커밋 해시와 같은 지정자를 기반으로 최신 preview를 실행할 수 있습니다.

```bash
tuist run App@latest # 프로젝트의 기본 branch와 연결된 최신 App preview 실행
tuist run App@my-feature-branch # 지정된 branch와 연결된 최신 App preview 실행
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # 특정 Git 커밋 SHA와 연결된 최신 App preview 실행
```

> [!IMPORTANT] Preview 공개 범위
> 프로젝트가 속한 조직에 접근 권한이 있는 사람만 preview를 볼 수 있습니다. 링크 만료 기능에 대한 지원을 추가할 계획입니다.

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>


    <a href="https://cloud.tuist.io/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews를 더욱 쉽게 실행할 수 있도록, 우리는 Tuist macOS menu bar 앱을 개발했습니다. Tuist CLI를 통해 Preview를 실행하는 대신, macOS 앱을 [다운로드](https://tuist.dev/download)하여 사용할 수 있습니다. `brew install --cask tuist/tuist/tuist` 명령어를 실행하여 설치할 수도 있습니다.

Preview 페이지에서 "Run"을 클릭하면, macOS 앱이 현재 선택된 디바이스에서 자동으로 실행됩니다

> [!IMPORTANT] 요구 사항\
> Preview를 다운로드하려면, `tuist auth login` 명령어를 사용해 인증해야 합니다.
> 앞으로는 앱에서 직접 인증할 수 있게 될 예정입니다.
>
> 추가로, 로컬에 Xcode가 설치되어 있어야 합니다.

## Pull/merge request 코멘트 {#pullmerge-request-comments}

> [!IMPORTANT] Git 플랫폼 연동 필요
> 자동으로 pull/merge request에 대한 코멘트를 받으려면, <LocalizedLink href="/guides/server/accounts-and-projects">remote project</LocalizedLink>를 <LocalizedLink href="/guides/server/authentication"> Git 플랫폼</LocalizedLink>과 연동해야 합니다.

새로운 기능에 대한 테스트는 모든 코드 리뷰에서 필수 과정이어야 합니다. 그러나 앱을 로컬에서 빌드하는 과정은 번거로워 개발자들이 실기기에서 기능을 전혀 테스트하지 않게 되는 경우가 많습니다. But _what if each pull request contained a link to the build that would automatically run the app on a device you selected in the Tuist macOS app?_

[GitHub](https://github.com)와 같은 Git 플랫폼에 Tuist 프로젝트를 연결한 후, CI workflow에 <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>을 추가하세요. 이후 Tuist는 Pull request에 Preview 링크를 직접 게시합니다:
![GitHub app comment with a Tuist Preview link](/images/guides/features/github-app-with-preview.png)

## README 배지 {#readme-badge}

Tuist Previews를 repository에서 더 잘 보이게 하려면, `README` 파일에 최신 TUIST Preview를 가리키는 배지를 추가할 수 있습니다:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

`README`에 배지를 추가하려면, 아래의 markdown을 사용하고 계정 및 프로젝트 핸들을 여러분의 것으로 교체하세요:

```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

## 자동화 {#automations}

`tuist share` 명령어에서 `--json` 플래그를 사용하면 JSON 형식의 출력을 얻을 수 있습니다:

```
tuist share --json
```

JSON 출력은 CI provider를 사용해 Slack 메시지를 보내는 등 같은 커스텀 자동화를 만드는 데 유용합니다.
JSON에는 전체 preview 링크가 포함된 `url` 키와 실기기에서 preview를 쉽게 다운로드할 수 있도록 QR 코드 이미지 URL이 포함된 `qrCodeURL` 키가 있습니다. JSON 출력 예시는 아래와 같습니다:

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
