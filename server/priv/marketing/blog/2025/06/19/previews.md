---
title: "The Future of App Development: Tuist Previews in an AI-Powered World"
category: "community"
tags: ["ai", "devx", "previews", "automation", "future"]
excerpt: "As AI transforms how we write code, we're reimagining how Tuist Previews can bridge the gap between automated development and human validation. Here's our vision for the future of mobile app development."
author: pepicrft
og_image_path: /marketing/images/blog/2025/06/19/previews.jpg
---

There's no question at this point that AI will have an impact on the way we write code.
We touched on this in our [Vibe Xcoding your Apps](/blog/2025/05/13/vibe-xcoding), and most recently we've seen Apple taking steps toward reconciling recent innovations, like agentic coding workflows, into Xcode.
There's no turning back. However, development is just part of the equation.
If things continue this way, there's a high chance that an agent can take your task,
run it in a macOS environment,
and come back with a PR.
But what happens from that point on?
This is something we're exploring at Tuist,
and we believe Tuist Previews can play a pivotal role in this new landscape.

## Between PR Opening and Merge

If you think of traditional workflows in Swift app development, 
which closely mirror workflows in other technologies,
once a PR is opened,
two main things happen. First,
your peers review the code to ensure it's correct.
Second, you trigger one or multiple CI jobs that run automated checks against your changes.
If both give the green light, you merge the PR.

Whether through Tuist's optimizations like binary caching or selective testing,
or in the near future with swift-build optimizations,
combined with the decreasing cost of Mac infrastructure,
the financial and time cost of running automated checks will become minimal.
In other words, you'll get CI results in minutes or even seconds.
This sounds idealistic,
but in the world of agents, where fast feedback is crucial,
we believe this will become reality.

What does this mean? If you automate code review using AI tools like [Claude Code](https://www.anthropic.com/claude-code) or [GitHub Copilot](https://github.com/features/copilot),
which analyze code patterns and best practices,
what remains is ensuring that the changes do what they're supposed to do.
This requires compiling, launching, and using the app—
and this is where [Tuist Previews](https://docs.tuist.dev/en/guides/features/previews) become essential.

## Previews: A Tool to Manually Test Your Changes

When we introduced previews,
we drew inspiration from platforms like [Vercel](https://vercel.com/), [Cloudflare](https://www.cloudflare.com/), and [Netlify](https://www.netlify.com/),
where you get an ephemeral environment accessible via URL to see your changes live.
We also took cues from [Shopify's "tophat" culture](https://shopify.engineering/shopify-tophat-mobile-developer-testing),
where developers are required to test changes as part of reviewing PRs.
We loved this concept and brought it to the mobile app world through Tuist.

For previews to succeed, they need to be available no slower than the longest wait between CI checks or review approvals. Let's say both happen in under 5 minutes. If your preview takes 10 minutes to build, authors will likely merge without peers manually testing the changes.
That's why we're heavily invested in cutting build times so that preview generation is comparable to CI check times, while also reducing the costs of creating previews (since CI typically charges per build minute).

The second crucial piece is ensuring previews are seamless to run. **We designed them to be URL-centric.** When someone shares a URL with you, you should be able to install the preview just by tapping the URL, or pasting it in the terminal if you have the CLI installed. And if the app supports physical devices and your device ID is in the signing certificate, you can install it on your device too.

Many people compare previews with **nightly builds** because, as I pointed out in [Building a Business Around Tuist](/blog/2025/05/20/business-around-tuist), people iterate on their mental models gradually. Both nightly builds and previews are tools to build and share apps. The difference is that while nightly builds are distant in time and space from code changes—making it difficult to correlate feedback with changes—previews are immediate. They happen right at the PR level, where feedback can be provided in context and easily addressed. Compare this to getting a Slack message days later saying, "Hey, I found something in build 233." Finding the PR that introduced the issue becomes increasingly difficult as merge throughput increases.

If you haven't tried previews yet, it's remarkably simple. Build your project with `xcodebuild`, Fastlane, or your tool of choice, then run one command to share the app:

```bash
tuist share App
```

The metadata necessary to correlate the preview with the Git forge is automatically collected. In other words, Tuist knows which PR the preview belongs to.

## Time for Feedback

Getting previews into people's hands is just half the equation. We're actively working to eliminate friction through features like on-the-fly signing and bringing the experience to the web so you don't need simulators or even Apple devices. But there's more we can—and will—do. The natural next step after testing an app is reporting feedback, and this closes the development loop.

This is where things get truly exciting. Imagine you're using a preview and discover an issue. Wouldn't it be powerful if the preview provided built-in tools to report that feedback? What if that feedback automatically included contextual information to help developers understand the issue? For example: redacted traces of server requests, user navigation paths through the app, logs, or even a recording of the last few minutes leading to the issue.

These are just examples, but you get the idea. We're exploring the development of a **Tuist Development SDK** that integrates into your app's development builds, closing the loop with a feedback tool that seamlessly integrates with previews and the AI-powered coding world that's taking shape.

## What If You Could Automate the Feedback Process Too?

Here's where we get truly forward-thinking. Having built infrastructure to distribute previews, feedback building blocks, and the Tuist SDK, we have all the ingredients for something transformative:

- Push your changes
- Get CI and AI feedback about your code
- Get AI feedback about your app's runtime behavior

Wouldn't that be revolutionary? We know the web is already moving in this direction, and we're eager to bring the same experience to app developers. We're doubling down on previews because we believe they can unlock a world of possibilities in this new era that's unfolding before us.

The future of app development is being written right now, and we're thrilled to be part of shaping it. With curiosity as our compass and innovation as our engine, we're building the tools that will make tomorrow's development workflows feel like magic compared to today's.

**You can start using [previews](https://docs.tuist.dev/en/guides/features/previews) today with Xcode projects or generated Tuist projects.**
