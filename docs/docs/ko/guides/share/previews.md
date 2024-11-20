---
title: Previews
titleTemplate: :title · Share · Guides · Tuist
description: 앱 미리보기를 생성하고 다른 사람과 공유하는 방법을 알아보세요.
---

# Previews {#previews}

> [!IMPORTANT] XCODEPROJ 호환가능
> 이 기능은 순수 Xcode 프로젝트와 호환됩니다.

> [!IMPORTANT] REMOTE PROJECT REQUIRED
> This feature requires a <LocalizedLink href="/server/introduction/accounts-and-projects#projects">remote project</LocalizedLink>.

앱을 개발할 때 다른 사람들의 피드백을 받기 위해 앱을 공유하고 싶을 수 있습니다.
전통적으로, 팀들은 앱을 빌드하고 서명한 후 Apple의 [TestFlight](https://developer.apple.com/testflight/)와 같은 플랫폼에 업로드하여 이 작업을 수행해왔습니다.
하지만, 이 과정은 번거롭고 느릴 수 있으며, 특히 동료나 친구로부터 빠른 피드백을 받고자 할 때는 더욱 그렇습니다.

Tuist는 이러한 과정을 간소화하기 위해 앱 미리보기를 생성하고 다른 사람과 공유할 수 있는 방법을 제공합니다.

> [!IMPORTANT] DEVICE(실기기) 빌드 시 서명 필요
> DEVICE용으로 빌드할 때, 앱이 올바르게 서명되었는지 확인하는 책임은 사용자에게 있습니다. 우리는 향후 이 과정을 더 간소화할 계획입니다.

:::code-group

```bash [Tuist Project]
tuist build App # simulator용 앱 빌드
tuist build App -- -destination 'generic/platform=iOS' # device용 앱 빌드
tuist share App
```

```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
```

:::

이 명령어는 앱을 시뮬레이터나 실기기에서 실행할 수 있는 공유 가능한 링크를 생성합니다. 사용자가 해야 할 일은 아래 명령어를 실행하는 것뿐입니다:

```bash
tuist run {url}
tuist run {url} --device "My iPhone" # 특정 기기에서 앱 실행하기
```

Preview 링크를 통해 모바일 기기에서 직접 `.ipa` 파일을 다운로드하여 앱을 설치할 수 있습니다.
The links to `.ipa` previews are by default _public_. In the future, you will have an option to make them private, so that the recipient of the link would need to authenticate with their Tuist account to download the app.

`tuist run` also enables you to run a latest preview based on a specifier such as `latest`, branch name, or a specific commit hash:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!IMPORTANT] PREVIEWS' VISIBILITY
> Only people with access to the organization the project belongs to can access the previews. We plan to add support for expiring links.

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/public/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    
    
    <a href="https://cloud.tuist.io/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/share/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews를 더욱 쉽게 실행할 수 있도록, 우리는 Tuist macOS menu bar 앱을 개발했습니다. Tuist CLI를 통해 Previews를 실행하는 대신, macOS 앱을 [다운로드](https://cloud.tuist.io/download)하여 사용할 수 있습니다. 브라우저에서 Preview 링크를 열면, 앱이 현재 선택된 디바이스에서 자동으로 실행됩니다.

> [!IMPORTANT] 요구 사항
> Previews를 다운로드하려면, 먼저 `tuist auth` 명령어를 사용해 인증해야 합니다.
> 앞으로는 앱에서 직접 인증할 수 있게 될 예정입니다.
>
> 추가로, 로컬에 Xcode가 설치되어 있어야 합니다.

## Pull/merge request 코멘트 {#pullmerge-request-comments}

> [!IMPORTANT] Git 플랫폼 연동 필요
> 자동으로 pull/merge request에 대한 코멘트를 받으려면, <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink>를 <LocalizedLink href="/server/introduction/integrations#git-platforms"> Git 플랫폼</LocalizedLink>과 연동해야 합니다.

새로운 기능에 대한 테스트는 모든 코드 리뷰에서 필수 과정이어야 합니다. 그러나 앱을 로컬에서 빌드하는 과정은 번거로워 개발자들이 실기기에서 기능을 전혀 테스트하지 않게 되는 경우가 많습니다. But _what if each pull request contained a link to the build that would automatically run the app on a device you selected in the Tuist macOS app?_

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), add a <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> to your CI workflow. Tuist will then post a Preview link directly in your pull requests:
![GitHub app comment with a Tuist Preview link](/images/guides/share/github-app-with-preview.png)

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
