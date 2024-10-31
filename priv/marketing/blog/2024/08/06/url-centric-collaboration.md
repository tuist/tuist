---
title: "Introducing Tuist Previews. A URL-centric approach to collaboration."
category: "product"
tags: ["Product"]
excerpt: "Tuist Previews make it easy to share apps with anyone. Learn more about this new feature and what's coming next."
author: pepicrft
highlighted: true
---

Tuist's mission is to empower developers and organizations to build better apps faster. We've made significant strides in supporting developers on their journey, from simplifying Xcode's complexities to optimizing build times. However, there's one area where we've fallen short: collaboration.

When a developer has something built and running and wants to share it with their team, for instance, to gather feedback, they have to jump through hoops to get it in front of the right people. Isn't it crazy that something that's right there in your environment can't be easily shared with others?

Fortunately, that's no longer the case. We just released a new version of Tuist, [4.23.0](https://github.com/tuist/tuist/releases/tag/4.23.0), which introduces a new feature called **Previews**.

## The current state of collaboration

Traditionally, teams have relied on platforms like Visual Studio [App Center](https://appcenter.ms/)—which Microsoft has scheduled for retirement—and Apple's [TestFlight](https://developer.apple.com/testflight/). While TestFlight is excellent for sharing apps with testers, it's less effective for broader team sharing. To build, sign, and distribute apps, teams must set up and maintain scripts and continuous integration pipelines, which is both time-consuming and costly.

Additionally, the recipient must have an Apple account (which is a reasonable assumption), be invited to a group, and only then will they receive the builds to test. These builds might have a versioning system detached from the codebase context, making it difficult to correlate feedback with the code that generated the build. For instance, encountering a bug in TestFlight build number 455 prompts questions like: Was this build generated from a commit in main? From a PR? Or was it built and pushed by a teammate from their local environment? This uncertainty is problematic.

We believe collaboration needs a much simpler, web-centric approach:

- Sharing a build should be as easy as sending a link.
- It should be possible to share something running right in the simulator.
- Builds should include associated context to facilitate forwarding feedback to the appropriate person.
- Complexities like signing should not be a hindrance.

These principles are embodied in Tuist Previews, which we believe will herald a new era of collaboration for development teams.

## Tuist Previews

Tuist Previews make it easy to share apps with anyone. Once the app is built, you can effortlessly turn it into a link with a single command:

```bash
tuist share MyApp
```

The command will output a link that anyone can use to run the app with another simple command:

```bash
tuist run https://tuist.io....
```

<iframe title="Tuist Previews: Simplifying app sharing and collaboration" src="https://videos.tuist.io/videos/embed/46f2cfb5-7f7b-43fd-8350-87dda8476dc7" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

## Xcode projects support

We are gradually weakening the dependency with Tuist projects. Features like Previews and upcoming features will work directly with your Xcode projects. This means that you can use Tuist to build and run your apps, even if you don't use Tuist to generate your projects.

## What's next

This is just the beginning of Tuist Previews. We are eager to hear your feedback and prioritize it alongside some of the following features we have in mind:

- **Device support:** Previews currently work only on simulators, but we plan to add support for physical devices. We are developing open-source technologies and infrastructure to abstract away the intricacies of reliably signing apps. Our goal is to prevent any complexity from affecting the developer experience.
- **macOS app:** Non-developers may not feel comfortable running a command-line tool to use an app. We are building a macOS app that will make it easier to run and share apps. This app will serve as the foundation for more features that need to integrate natively with the macOS platform.
- **Feedback:** We aim to include metadata in previews and give developers the option to integrate an SDK that will allow users to report feedback. We'll handle forwarding that feedback to the appropriate team member.
- **Releases:** When you want to share the app with Apple, that's a release! We'll provide tools for this process, abstracting away any complexity, including signing, and offering remote environments so that you don't need to deal with intricate CI pipelines.

**Tuist Previews is a love letter to simplicity** and continues to shape Tuist as an Omakase experience for app developers. We're excited to see how teams leverage this feature to build better apps faster. If you have any feedback or ideas, please share them with us on [GitHub](https://github.com/tuist/tuist) or [Slack](https://slack.tuist.io).
