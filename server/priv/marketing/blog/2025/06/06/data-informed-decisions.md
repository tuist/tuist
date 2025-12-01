---
title: "Building data-driven dev environments for Apple platforms"
category: "product"
tags: ["product"]
excerpt: "Explore how Apple's proprietary Xcode formats prevent data-driven development decisions and how Tuist is building the missing infrastructure to unlock productivity insights."
author: pepicrft
og_image_path: /marketing/images/blog/2025/06/06/data-informed-decisions/og.jpg
---

**This blog post will be valuable for people interested in understanding how they can use data to improve their development environments, and learn how Tuist is building the infrastructure to enable data-driven decisions.**

You might have heard of the concept of data-informed decisions—the idea that you back your decisions using data. The more and better data you have, the better your decisions can be, and this principle applies to developer environments too.

Many disciplines in the tech industry follow this approach: product, marketing, sales, and even engineering in production systems. However, some disciplines and domains have traditionally refrained from backing decisions with data, and app development productivity is one of those. Why, you might ask? In this blog post, I'd like to distill that for you and share examples of how having the right data can help you take a different approach to your development setup.

## The problem: Xcode's proprietary ecosystem

Have you ever heard of the concept of [narrow waist](https://www.oilshell.org/blog/2022/02/diagrams.html)? It's the idea that a concept, interface, or protocol solves an interoperability problem. TCP/IP is a narrow waist between the application layer and the transport layer. Shipping containers are the narrow waist between goods and transport mechanisms.

Often, these narrow waists are created by data formats like [Markdown](https://en.wikipedia.org/wiki/Markdown), which many editors and tools can interact with. When you choose Markdown, you know it's synonymous with having access to an ecosystem of tools that can work with it.

But Apple created their own ecosystem. Even though they're not the only ones building tools for developers—like build systems or test runners—they refused to adopt and, in some cases, evolve existing standards. Instead, they leaned into Xcode-scoped proprietary formats. These formats were optimized to be interacted with from Xcode, and their usage outside of that context required extensive reverse engineering. This is something we had to do with [tuist/xcodeproj](https://github.com/tuist/xcodeproj), and Spotify had to do with [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser).

**When you have to reverse-engineer an undocumented format, the incentives to build a narrow waist are minimal.** But by not building it, you prevent developers from having access to an ecosystem of tools. As a consequence, you create a strong dependency on Apple's investment in developer tools. Sure, they make amazing tools, but other people do too—perhaps you don't need to build everything yourself.

The result is that everything happens within Xcode. Any state, whether it's the result of a build or tests, doesn't "escape" that environment.

## The infrastructure challenge: where to store and process data

Let's assume you've gained access to the data. You've hacked your way through Xcode projects, used community tools to convert the format into a JSON payload, and you're ready to use it. The next natural question is: where do I place the data, and what do I do with it?

Storing it locally wouldn't be useful enough because you'd only be able to see your own data and compare how it changes over time within your environment. As we'll see later, there are many interesting insights we can derive once we make the data escape an environment. So you need a place to store the data and a publicly accessible API to push it to. You need a server.

At this point, you'll most likely need to sit down with a backend or infrastructure engineer from your company to spin up a data-ingestion pipeline or an instance of [XCMetrics](https://github.com/spotify/XCMetrics). But as I said earlier, the incentives to maintain narrow waists or tools that work with proprietary formats are minimal. With Spotify no longer using Xcode's build system, the project is no longer actively maintained. So chances are you give up.

Your project will continue growing. Every year, you'll pitch to your leadership about getting faster Apple Silicon—which your engineers and Apple will be happy about—and hope that things are just fine.

But even though you can't directly observe your dev environments, people talk about their feelings in private or group conversations. They joke about those flaky tests continuously making PRs red and requiring retries, or SwiftUI previews breaking again in the most recent Xcode version, or having to frequently delete derived data every time they change between branches. If you've been on a team working on an Xcode project, I'm sure you've been in one of these conversations.

Sooner or later, the unproductivity becomes so obvious that you find yourself in a desperate leadership decision, which typically ranges from adopting React Native or Flutter to asking the most senior people on the team to explore new build systems.

## The power of data: insights you can gain

Before we dive into what Tuist is doing to change the state of things, I think it's important to stop for a second and reflect on which questions we can get answered once we collect and process the data.

The most obvious metric is **build times**, and it's the one organizations are most interested in because it has the highest impact on productivity. If you get the build time per scheme, target, and file, you can see not only how they evolve over time but also how different decisions impact build time. For example, Apple Silicon has multiple cores, but their presence doesn't mean they're being used as effectively as possible. You might need to make changes in your graph or enable new Xcode features such as explicit modules to allow the build system to parallelize more.

What about how frequently people clean derived data, which translates to clean builds? If people are cleaning derived data too frequently, this negatively affects productivity, and it's important to understand why people clean in the first place. Are they getting an error they don't understand? Was an Xcode feature not working as expected?

Another metric directly connected to productivity is **flakiness**. If tests are flaky, people need to retry CI in their PRs, and whenever they do, they're increasing the time it takes to get their changes merged. Detecting whether a test is flaky requires storing two metrics for each uniquely identified test: a hash and a status. If, given the same hash, we get different results, we might consider the test flaky. By persisting this information, you can have a flakiness scoreboard so you know which tests are causing the most harm to your dev environment and prioritize fixing them.

What if you invest in new laptops, a new version of Xcode or Swift, or introduce a caching system like Tuist's? Then you can see the impact it's had on your team and do some mathematics to know if the investment was worth it. Without data, none of this is possible.

## Building the missing infrastructure

We can't influence Apple to give up on proprietary formats and build more narrow waists. We've seen it's costly for the community, but unless there's a mindset change, it's very unlikely to happen.

What we're doing with Tuist is trying to map those proprietary formats into standards that people can build tools upon. We did that with [XcodeProj](https://github.com/tuist/xcodeproj) to read, update, and write Xcode projects, [XcodeGraph](https://github.com/tuist/XcodeGraph) to have an in-memory representation of a project that's much nicer to work with than vanilla Xcode projects, and [Rosalind](https://github.com/tuist/Rosalind), which generates a schema with the internal structure of an Apple bundle. In other words, we build narrow waists in the Apple ecosystem so that others can build tools and come up with new ideas and improvements to make everyone's development experience better.

Once you have a narrow waist you can build features that are easy to adopt, and this is where Tuist comes in: we package the infrastructure management and make that data useful and actionable into a server product that has a strong focus on developer experience. It's plug-and-play. We also provide an API and soon data-ingestion capabilities so that you can build your own apps upon Tuist, or extract data from your projects into your data pipelines.

Remember XCMetrics that I mentioned before? Unlike it, you don't need to deploy anything. You sign up, create a project, [make a one-line change in your project, and you're good to go.](/blog/2025/06/05/build-insights)

Perhaps Apple will change their strategy and embrace industry standards like [OpenTelemetry](https://opentelemetry.io/). If that ever happens, we'll be the first ones celebrating because it'll be a win for the entire ecosystem. But until that happens, we think the ecosystem and teams need the narrow waists that we're building. It's important that we do so while building an incentive system to keep giving teams those tools to improve their workflows.

**This post was written by a human and its grammar reviewed with Claude 4 Sonnet.**
