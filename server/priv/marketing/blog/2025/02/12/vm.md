---
title: "Catching up with modern developer experiences through macOS virtualization"
category: "learn"
tags: ["oss", "virtualization"]
excerpt: "We discuss the cost of running macOS-dependent workflows remotely and how we can catch up with modern developer experiences through macOS virtualization."
author: pepicrft
---

When we discuss the developer experiences we'd like to provide at Tuist and what we need to enable them, we often find ourselves discussing the cost of running macOS-dependent workflows remotely.

In other ecosystems, like the web, workflows can run in Linux environments that can be easily virtualized with technologies like [Docker](https://www.docker.com) or [Podman](https://podman.io). Even browsers can become containers with projects like [WebContainers](https://webcontainers.io), in which you can run a [NodeJS](https://nodejs.org/en) instance. [StackBlitz](https://stackblitz.com) leverages this technology to include interactive code examples in websites. Other projects like [Replit](https://replit.com) or [Bolt](https://bolt.new) provide full-fledged AI experiences for creating and running code. As a project that likes to innovate in the developer experience space, we can't help but feel that we are lagging behind. But what would it take to catch up?

## A macOS-dependent world

It's well known that developing apps for the Apple environment is tightly coupled with macOS as a host. Although Swift and its toolchain are taking a different direction to expand into new environments, Apple development remains heavily dependent on proprietary macOS tools and frameworks. Even UI technologies like [SwiftUI](https://developer.apple.com/xcode/swiftui/) remain in Apple's proprietary domain, making it difficult to port to other platforms or leverage it to create new AI-based coding experiences that build on SwiftUI internals.

Ideally, this wouldn't be the case, but with Apple being a hardware and service company, the likelihood of the toolchain breaking its dependency on macOS is very low. From a business perspective, such an investment makes little sense. However, who knows what the future holds? They might surprise us.

If breaking the dependency with macOS isn't an option, what's the alternative? Let's talk about virtualization.

## Virtualization of macOS environments

Virtualization allows you to create isolated macOS environments on your machine. Apple released a framework called [Virtualization](https://developer.apple.com/documentation/virtualization) to facilitate this. Docker and Podman are similar technologies for Linux environments. Docker revolutionized the way we build and run applications. Suddenly, your cloud provider didn't have to provide you with the exact environment you needed—you simply gave them your [OCI image](https://github.com/opencontainers/image-spec), and they ran it.

Most CI providers use virtualization to prevent polluting a host's environment. They create ephemeral environments for each build. The options to virtualize were quite limited and proprietary, with [Anka](https://veertu.com/anka-build/) being one example. These CI providers not only had to solve the problem of virtualization (which was delegated to third-party companies offering proprietary technology) but also had to develop the technology to orchestrate host environments and distribute workloads within them.

Unlike Docker environments, which cloud providers can provision in seconds via API, achieving the same thing in macOS is more costly. Images are not as lightweight as Docker images, so you can't pull them lazily since they can take minutes to download. Additionally, until recently, accessing Apple hardware was a manual process with data centers. AWS [changed the game](https://aws.amazon.com/ec2/instance-types/mac/) by providing APIs to spin up new machines. The complexity lay in maintaining a pool of Apple hardware, warmed with images and ready to run workloads.

As mentioned earlier, innovation in this space happened behind closed doors and was oriented toward building continuous integration. But thanks to the beauty of software, things are getting commoditized, which opens a world of opportunities.

## Commoditization of virtualization

It's inevitable that software becomes commoditized through open source. Commoditization is the process of making goods or services more accessible and affordable to more people. Consider the process of building a web app today: you build it using an open-source framework and technologies, with an open-source programming language, that runs in open-source virtualization technology, on an open-source operating system, that most likely runs on proprietary hardware. macOS virtualization has been slow to commoditize, but that's changing.

Recently, we came across two efforts: [Lume](https://github.com/trycua/lume) and [macvm](https://github.com/macvmio). Both are building technologies to commoditize macOS virtualization. macvm is also developing [fugaci](https://github.com/macvmio/fugaci), a technology to orchestrate workload distribution using Kubernetes. We're getting closer to a point where an AWS key might be the only thing needed to bring CI to your organization, with solutions like GitHub Actions or [Buildkite](https://buildkite.com) serving as frontends to runners. We're not far from that world.

This might not be great news for CI companies that have built their businesses around proprietary technologies. But for a small team of 4 people like us, who can't afford the cost of developing and maintaining such commodities, it's a game-changer. We can focus on innovating in the developer experience space rather than building yet another version of technology that others have built before.

## Blurring local and remote environments

For many years, virtualization served CI businesses. CI is an easy way sell to investors and customers—you don't need to convince developers and organizations about its necessity. But what else could we do with virtualization? What can we learn from the web and other uses of Linux-based virtualization technologies? These are the questions we're interested in exploring and solving at Tuist.

Proprietary virtualization technologies and YAML naturally lead to automation that can't be debugged easily. Having to push code to see if a pipeline does what it's supposed to do is the result of investing in closed solutions. Now imagine this: you can have the same virtualization technology that you use in CI on your local machine. Suddenly, the same workflow that will run in CI is runnable locally, whether it's an `xcodebuild` command or your own workflow:

```bash
tuist xcodebuild -project MyApp -scheme MyApp -vm local:macos-sequoia-xcode:latest
```

Let that sink in. Automation becomes easier to debug. What if you could then run the same workflow remotely with a version of Xcode of your choice?

```bash
tuist xcodebuild -project MyApp -scheme MyApp -vm remote:macos-sequoia-xcode-15:latest
```

The logs would be forwarded to your local machine, making it feel as if things were running locally. This is similar to the `fly deploy` command for deploying apps to [Fly](https://fly.io), where the image can be built remotely, but everything feels local. Isn't that amazing?

Why hasn't this happened before? We wonder the same... Virtualization is costly, so only companies with substantial resources could afford to innovate. Additionally, companies with resources often find it less risky to mimic other models and compete on the value-cost tradeoff than to innovate. Here comes Tuist: poor but sexy. We can innovate because we're not afraid to explore new domains, and the cost is decreasing.

If you thought that was enough, you're wrong. Have you noticed that most solutions in the space require you to trigger workflows either from a local environment or a CI environment? This is because they don't want to solve virtualization. But imagine if it were possible. You could enable workflows triggered from the web, just like triggering a GitHub Action workflow.

Let's say you're reviewing a PR and want to get a preview build. You could click a button, and a preview build would be triggered in a macOS environment, with the preview shared with you. Forget about those nightly builds or [App Center](https://appcenter.ms) replacements. Those models are fundamentally broken, yet we keep mimicking them and racing to create alternatives. This opens a world of possibilities—it could be a preview, a release, or even on-the-fly signing to allow someone to install a release on their device.

## Closing Words

Apple decoupling app development from macOS is a dream that might never come true. However, the commoditization of virtualization technologies is a reality, and Tuist is going to leverage it to provide a better developer experience. Transitioning from being a purely client-side technology through our CLI to a web-based platform where the CLI is an interface to the platform positions us well to blur web and client boundaries in ways that ecosystems like the web have been doing for years.

While we don't have experience in building infrastructure, we have a strong appetite for learning about it and solving its challenges—not only to build better experiences ourselves but also to invite other companies and developers to innovate in the space, as we did with other commodities we've released in the past, like project generation and the [XcodeProj](https://github.com/tuist/xcodeproj) parser.
