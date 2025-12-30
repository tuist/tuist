---
title: "Streamline previewing changes in your open source Swift apps – IcySky case study."
category: "learn"
tags: ["Guide", "Previews"]
excerpt: "Use Tuist Previews in open source Swift apps to streamline testing latest changes for maintainers and contributors alike."
author: fortmarek
highlighted: true
---

As mobile developers, we all understand the importance of testing latest changes as automated tests often fall short in catching UI and behavior-related issues. However, the current solutions for testing apps in PRs come with their own set of challenges. Tools like TestFlight, while powerful, have not been built with PRs in mind. Instead, they are focused for testing changes that have already been merged – critical metadata like commit SHA, branch name, and PR number are lost in the process.

Additionally, TestFlight brings a lot of overhead to upload builds – such as going through the app review or having to sign the app in the PR workflows – which can be quite cumbersome for open source projects. This is where [Tuist Previews](https://docs.tuist.dev/en/guides/features/previews) come in. They offer a streamlined way to test the latest changes in PRs, making it easier for maintainers and contributors alike.

Recognizing the potential for open source apps, we partnered with [Thomas Ricouard](https://github.com/Dimillian) and integrated Tuist Previews in the new [IcySky](https://github.com/Dimillian/IcySky) app. IcySky can now benefit from all the features that Tuist Previews offer and we get to iterate with Thomas and IcySky's contributors to make Tuist Previews even better.

![Github PR comment](/marketing/images/blog/2024/11/25/tuist-previews-in-opensource/icysky-preview.gif)

## Contribute by testing changes

Let's consider a common scenario: a user raises an issue that they found in the app. A contributor creates a PR that _should_ fix the issue. But does it really?

Ideally, the issue author would test changes from the PR to confirm the issue is actually gone. But in most project, that would mean they'd need to set up the development environment and build the app on their device. That can often be a cumbersome process, especially for newcomers. But with Tuist Previews, the PR includes a preview link with the app pre-built:

![Github PR comment](/marketing/images/blog/2024/11/25/tuist-previews-in-opensource/github-pr-comment.png)

Now, they can just click a link to see the changes on their simulator. The only prerequisite is to have Xcode and the [Tuist macOS app](https://docs.tuist.dev/en/guides/features/previews#tuist-macos-app) installed. Contributors can then use the macOS app to test changes in multiple environments, such as iPhone or Apple TV:

<img src="/marketing/images/blog/2024/11/25/tuist-previews-in-opensource/tuist-macos-app.png" width=300px alt="Tuist macOS app screenshot" />

And to make it easier to test the latest changes that have been merged to `main`, use a `README` badge to make the latest preview easily accessible by anyone:
[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

To see Tuist Previews in action, you can watch the following video:
<iframe title="Running previews from a PR comment" width="560" height="315" src="https://videos.tuist.io/videos/embed/1eea415f-a2b1-4264-89a3-f64c7e2a3477" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

## Set it up

Did the above pique your interest? Here's a few of steps to start using Tuist Previews in _your_ open source project.

1. **Install the Tuist CLI** – if you haven't already, [install](https://docs.tuist.dev/en/guides/quick-start/install-tuist) the Tuist CLI.
2. `tuist auth` – authenticate and create an account if needed. We recommend using GitHub for authentication which is required for some features.
3. `tuist organization create {organization-name}` – it's recommended to create a Tuist organization unless you're working on a personal project. Run  to create one.
4. `tuist project create {organization-name}/{project-name}` – create a new project in your organization. The full project handle follows the same convention as GitHub.
5. Create a `Tuist.swift` file in the root of your project with the following content:

```swift
import ProjectDescription

let config = Config(
    fullHandle: "{organization-name}/{project-name}"
)
```

6. `tuist project update {organization-name}/{project-name} --repository-url {your-repository-url} --visibility public` – connect your Tuist project with the GitHub repository and make its visibility public to make it accessible to developers outside of your Tuist organization.
7. `tuist project tokens create {organization-name}/{project-name}` – create a token for your project. This token will be used to authenticate with Tuist in your CI – copy this token and set it as a secret in your repository.
8. Install the [Tuist GitHub app](https://github.com/marketplace/tuist) in your repository to get [PR comments](https://docs.tuist.dev/en/guides/features/previews#pullmerge-request-comments).
9. Add `tuist share NameOfYourApp --configuration Debug --platforms iOS` to your CI script to share a Tuist Preview. This needs to be done _after_ you build the app. You can find an example of a CI script with `tuist share` in the [IcySky repository](https://github.com/Dimillian/IcySky/blob/6f1e92bc4a3f1b8c83f1e61230ebef7034dca142/.github/workflows/icy_sky.yml). Ensure that the CI steps with `tuist share` has the `TUIST_CONFIG_TOKEN` environment variable defined with the value from step 6.
10. [Add a badge](https://docs.tuist.dev/en/guides/features/previews#readme-badge) to your README, so that you and contributors can easily download the latest version.


... and that's it – you have now made testing changes easier for maintainers, contributors, and users! All Tuist features are **free for open source projects**, so you can start using Tuist Previews today with no strings attached. To learn more about Tuist Previews, you can find our up-to-date [documentation here](https://docs.tuist.dev/en/guides/features/previews).

Additionally, to see Tuist Previews in action, head over to the [IcySky](https://github.com/Dimillian/IcySky) repository, including the [PR](https://github.com/Dimillian/IcySky/pull/3) for the initial Tuist Preview support. **Huge thanks to Thomas** for taking the time to set everything up and give us feedback. It means a lot 💜

And if _you_ have feedback to share, we'd love to hear from you at our [community forum](https://community.tuist.dev/) 😌
