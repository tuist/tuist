---
title: "Empowering teams to build better apps faster"
category: "product"
tags: ["Product"]
excerpt: "Tuist is shifting its focus to empower teams to build better apps faster. Learn more about our new vision and what's coming next."
author: pepicrft
og_image: /images/og/empower-teams-to-build-better-apps-faster.jpg
highlighted: false
---

Tuist started in 2017 with a very narrow focus.
**Making Xcode's complexities more manageable.**
Since then,
we've grown to be an indispensable tool for many development teams to build their apps:

- [Asana scaled their iOS codebase with Tuist](https://asana.com/inside-asana/scaling-a-mature-ios-codebase-with-tuist)
- [Bumble chose it over Bazel and SPM to scale their development](https://medium.com/bumble-tech/scaling-ios-at-bumble-76754fa874f7)
- [Trendyol made Tuist their modularization cornerstone](https://medium.com/trendyol-tech/revamping-trendyols-ios-app-a-modularization-success-story-a6c1d2c4188b)

During this journey, we've learned a lot about the challenges teams face when building apps.
And we built solutions for those challenges,
like slow build or test times,
stretching Tuist's original focus around Xcode's complexities.
This left organizations and developers confused about what Tuist is and what it does.
Therefore, we decided to revisit our mission and vision and share it with all of you.

## From idea to top-notch apps

Apps usually start with an idea or a business need. Ideas can fade away if they're not validated quickly, and potentially great apps may never see the light of day. Unfortunately, the Apple platform has grown in complexity over the years, creating challenges and friction that developers and organizations need to navigate. Luckily, the community has built excellent open-source tools to assist developers with various challenges they face. However, developers still have to do the job of gluing these tools together into workflows that are a joy to use, sometimes in programming languages they are not familiar with, and maintain them indefinitely.

We believe there must be a better way: an ["omakase"](https://en.wikipedia.org/wiki/Omakase) for app developers. We envision an integrated experience with sensible defaults and the right extensibility points. This experience would hold your hand from the moment you start your project until you ship it to your users, helping you scale your development and your team. It would be an experience that can be easily ported from one project to another, from one team to another, and from one organization to another. We are building that experience with Tuist.

**We are shifting our focus to empower teams to build better apps faster.**

## Meeting developers where they are

Our strategy has always been to meet developers where they are by integrating with the official tools and APIs provided by Apple and equipping them with superpowers. A good testament to this work is our caching feature, which leverages Xcode primitives to achieve this. We will continue with this approach, minimizing abstractions as much as possible, aligning with Apple's direction, and embracing the languages and tools that developers are familiar with and love, such as [Swift](https://www.swift.org/).

Moreover, we are taking the approach of meeting developers where they are even further. We believe that ignoring the fact that developers spend significant time on platforms like [Slack](https://slack.com), [GitHub](https://github.com), and [GitLab](https://gitlab.com) is a mistake. Developers often spend a substantial portion of their time there collaborating with each other and with other teams and roles. It is crucial that their workflows integrate seamlessly with these platforms, so that anyone in the organization can access the information they need to make informed decisions without having to install developer-specific toolchains. Therefore, we are embracing the web platform and URLs as units of collaboration. Developers and organizations that want to extend Tuist's capabilities further will be able to do so by plugging their projects into a server, and voila.

**Tuist becomes a unified toolchain that encompasses both the client (CLI) and the server (formerly Tuist Cloud).**

## The lifecycle of an app

The toolchain will reflect the lifecycle of apps, from their creation to their release. The CLI, the dashboard, and our documentation will all mirror this lifecycle. We believe it’s crucial for developers to feel comfortable understanding and using the toolchain. Long-term, we aim for Tuist’s interface, which is very client-centric today, to evolve as follows:

- **tuist init:** Create a new project from community or Tuist-provided templates.
- **tuist build:** Build my project reliably and quickly, collecting insights.
- **tuist test:** Test my project reliably and quickly, collecting insights such as test coverage, performance, and flakiness.
- **tuist lint:** Validate the project or the artifacts generated from builds.
- **tuist share:** Share this app with my team or external people for feedback.
- **tuist workflow:** Run a Swift-based workflow locally, or manage the ones running remotely.
- **tuist release:** Trigger a release of my app to the App Store or any other distribution channel.

Drawing inspiration from the [Ruby](https://www.ruby-lang.org/en/) and [Ruby on Rails](https://rubyonrails.org/) communities, from which we have learned a lot, we will design the interface of Tuist to optimize for joy and invest in Swift extensibility to foster a vibrant ecosystem of plugins and integrations. More on this in the coming months.

## Embracing openness

The best organizations that we aspire to be like have one thing in common: *openness* (e.g., [Supabase](https://supabase.com/), [GitLab](https://gitlab.com), [PostHog](https://posthog.com)). Being open is what has brought us to where we are. It’s how we built trust with our users, created a foundation for diverse ideas, fostered collaboration, and, without a doubt, developed high-quality software that lasts and solves real problems. We are committed to doubling down on this value.

We are working on establishing a path and timeline to open-source everything we do without compromising our ability to build a sustainable business. We are documenting how we are building the company in a [public handbook](https://handbook.tuist.io) that is available for everyone to read. We believe that having **a handbook will enable a frictionless and asynchronous remote work environment, attracting the best talent from around the world.** As first-time founders on this journey, we also aim to inspire others to start their own companies and share their learnings with the world.

We will also **commoditize some pieces of technology** that we’ve noticed are common across many organizations to help elevate innovation at different layers of the stack. We believe that by doing so, we can help organizations focus on what differentiates them rather than on focusing on zero-sum game. Expect a handful of open-source projects from us in the coming months.

## A simple and open pricing model

The features that require a server are part of a paid plan, ensuring we can work on the project full-time and continue to support you with the challenges you face. Today, **we are pleased to announce our plans publicly,** focusing on simplicity and openness. We believe users shouldn’t have to figure out which plan works best for them. Everyone has access to every feature in each plan and simply pays based on usage and the level of support they desire from us.

- **Tuist Air:** For individual developers and small companies that don't need a dedicated support channel.
- **Tuist Pro:** For medium to large companies that need a dedicated support channel.

Only enterprise models are privately discussed, as they are tailored to the needs of large organizations (e.g., custom terms, SLAs, and support).

## What's next

We are beginning to work on the vision outlined above. To achieve this, we are developing foundational technology that we will open source in the coming months. Additionally, we are undergoing a website redesign with the amazing [Guinda](https://www.guindastudio.com/) team to reflect the new vision and make it easier for you to understand what Tuist is and how it can help you.

We will also double down on investing in our community to provide the Apple ecosystem with the best toolchain for building better apps faster.
