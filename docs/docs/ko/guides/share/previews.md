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

The command will generate a link that you can share with anyone to run the app – either on a simulator or an actual device. All they'll need to do is to run the command below:

```bash
tuist run {url}
tuist run {url} --device "My iPhone" # Run the app on a specific device
```

When sharing an `.ipa` file, you can download the app directly from the mobile device using the Preview link.
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
    <h1>Tuist</h1><a href="https://cloud.tuist.io/download" style="text-decoration: none;">Download</a><img src="/images/guides/share/menu-bar-app.png" style="width: 300px;" /><img src="/images/guides/share/menu-bar-app.png" style="width: 300px;" />
</div>

To make running Tuist Previews even easier, we developed a Tuist macOS menu bar app. Instead of running Previews via the Tuist CLI, you can [download](https://cloud.tuist.io/download) the macOS app. When you open a Preview link in the browser, the app will automatically launch on your currently selected device.

> [!IMPORTANT] REQUIREMENTS
> To download Previews, you need to first authenticate with the `tuist auth` command.
> In the future, you will be able to authenticate directly in the app.
>
> Additionally, you need to have Xcode locally installed.

## Pull/merge request 의견 {#pullmerge-request-comments}

> [!IMPORTANT] INTEGRATION WITH GIT PLATFORM REQUIRED
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects#projects">remote project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

Testing new functionality should be a part of any code review. But having to build an app locally adds unnecessary friction, often leading to developers skipping testing functionality on their device at all. But _what if each pull request contained a link to the build that would automatically run the app on a device you selected in the Tuist macOS app?_

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
