---
title: Previews
titleTemplate: :title · Share · Guides · Tuist
description: Learn how to generate and share previews of your apps with anyone.
---

# Previews {#previews}

> [!IMPORTANT] REQUIREMENTS
>
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

When building an app, you may want to share it with others to get feedback.
Traditionally, this is something that teams do by building, signing, and pushing their apps to platforms like Apple's [TestFlight](https://developer.apple.com/testflight/).
However, this process can be cumbersome and slow, especially when you're just looking for quick feedback from a colleague or a friend.

To make this process more streamlined, Tuist provides a way to generate and share previews of your apps with anyone.

> [!IMPORTANT] DEVICE BUILDS NEED TO BE SIGNED
> When building for device, it is currently your responsibility to ensure the app is signed correctly. We plan to streamline this in the future.

:::code-group

```bash [Tuist Project]
tuist build App # Build the app for the simulator
tuist build App -- -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```

```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```

:::

The command will generate a link that you can share with anyone to run the app – either on a simulator or an actual device. All they'll need to do is to run the command below:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
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
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1><a href="https://cloud.tuist.io/download" style="text-decoration: none;">Download</a><img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

To make running Tuist Previews even easier, we developed a Tuist macOS menu bar app. Instead of running Previews via the Tuist CLI, you can [download](https://tuist.dev/download) the macOS app. You can also install the app by running `brew install --cask tuist/tuist/tuist`.

When you now click on "Run" in the Preview page, the macOS app will automatically launch it on your currently selected device.

> [!IMPORTANT] REQUIREMENTS
> To download Previews, you need to first authenticate with the `tuist auth login` command.
> In the future, you will be able to authenticate directly in the app.
>
> Additionally, you need to have Xcode locally installed.

## Pull/merge request comments {#pullmerge-request-comments}

> [!IMPORTANT] INTEGRATION WITH GIT PLATFORM REQUIRED
> To get automatic pull/merge request comments, integrate your <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink> with a <LocalizedLink href="/server/introduction/integrations#git-platforms">Git platform</LocalizedLink>.

Testing new functionality should be a part of any code review. But having to build an app locally adds unnecessary friction, often leading to developers skipping testing functionality on their device at all. But _what if each pull request contained a link to the build that would automatically run the app on a device you selected in the Tuist macOS app?_

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), add a <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> to your CI workflow. Tuist will then post a Preview link directly in your pull requests:
![GitHub app comment with a Tuist Preview link](/images/guides/features/github-app-with-preview.png)

## README badge {#readme-badge}

To make Tuist Previews more visible in your repository, you can add a badge to your `README` file that points to the latest Tuist Preview:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

To add the badge to your `README`, use the following markdown and replace the account and project handles with your own:

```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

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
