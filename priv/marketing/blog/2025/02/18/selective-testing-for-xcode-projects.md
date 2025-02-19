---
title: "Selective testing for all Xcode projects"
category: "product"
tags: ["product", "test"] 
excerpt: "Run only tests that have changed, regardless of your setup, using Tuist's selective testing."
author: fortmarek
highlighted: true
---

Re-running all tests on the CI or locally is a waste of time, resources, and money, especially as your codebase grows and your test suite suddenly has thousands of tests. Wouldn't it be great if you could run your tests _selectively_ and skip all those that were not impacted by your changes?

While Tuist has had support for selective testing for a while now, it has been available only to those organizations that used Tuist to generate their Xcode projects and used the `tuist test` command to run their tests. 

We're excited to announce that we're now making selective testing available to _all_ Xcode projects, regardless of your setup, by extending the `xcodebuild` CLI:
```sh
tuist xcodebuild test -scheme App -destination "name=iPhone 16"
```

That's really almost all you need to do to dramatically speed up running your tests on the CI or locally. And yes, this feature also works if you modularized your app with local packages 📦

## Get started

If you want to see selective testing of Xcode projects in action, check out the video below:
<iframe title="Selective testing" width="560" height="315" src="https://videos.tuist.dev/videos/embed/9ac56b06-130f-4b76-af75-3b55545c4851" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

To get started with selective testing, you need to first [install Tuist](https://docs.tuist.dev/en/guides/quick-start/install-tuist). Once installed, you can run your tests almost as if you were using the `xcodebuild` CLI. The only difference being that you need to prefix the `xcodebuild` command with `tuist`:
```sh
tuist xcodebuild test -scheme App -destination "name=iPhone 16"
```

Once your tests have run, Tuist will store your selective test results. Let's try to run the tests again:
```sh
tuist xcodebuild test -scheme App -destination "name=iPhone 16"
# There are no tests to run, exiting early...
```

...and that's it! You have now successfully used selective testing to skip running tests that have not been impacted by your changes.


If you want to test out this feature in a demo project, you can clone this [repository](https://github.com/tuist/xcode_project_with_tests) and run the commands from above.

## How it works

When you run `tuist xcodebuild test`, Tuist does a couple of things:
- Computes hashes for all your modules in your project
- Adds `-skip-testing` flags to the `xcodebuild` command with the modules that have not changed since the last successful run, based on their hash
- If the `test` command succeeds, Tuist stores selective testing results

Let's go step by step using the [sample](https://github.com/tuist/xcode_project_with_tests) posted in the previous section. We can use the `tuist graph` command to see the structure of our project (and yes, `tuist graph` now also works for any Xcode project):

![Graph of an Xcode project with tests](/marketing/images/blog/2025/02/18/selective-testing-for-xcode-projects/graph.png)

The important dependency relations are:
- `AppFrameworkTests` depends on `AppFramework`
- `AppTests` depends on `App` and transitively on `AppFramework`

When we run the tests for the first time, Tuist first converts your Xcode project to an internal representation called `XcodeGraph` (for more details, see our previous [blog post](https://tuist.dev/blog/2025/02/11/mapping-xcodeproj-to-xcodegraph) on this topic). Then Tuist computes the hashes using the same mechanism as we do for [binary cache](https://docs.tuist.dev/en/guides/develop/cache#cache), which has been battle-tested by now.

On the first successful run, we store the hashes we just computed – locally and remotely (if you have a [Tuist project](https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects) set up). On a subsequent run, Tuist can skip all tests if nothing changes. But what if something _did_ change?

Let's say we change something in the `App` module. When we run the tests again, Tuist will recompute the hashes and compare them with the stored ones. Since the `App` module has changed and `AppTests` depends on this module, Tuist will run the tests for `AppTests` – but _not_ for `AppFrameworkTests` as the hash for that module has not been impacted by our changes! 

However, if we do update the `AppFramework` module, then Tuist will run the tests both for `AppFrameworkTests` _and_ `AppTests` as `AppTests` transitively depends on `AppFramework` through `App`. 

How much can Tuist skip in your project very much depends on how it's structured. The selective testing will be more effective if your project is modular and your modules are well-separated into separate layers, reducing interdependencies between them. For example, it's a good idea to have a "feature" layer where no feature can depend on another feature, only on the "core" layer.

## Extending xcodebuild

Extending `xcodebuild` with selective testing is yet another step in meeting developers where they are by extending tools most of the community already uses, rather than building completely new abstractions. The main benefit of using `tuist xcodebuild` as of now is to get access to selective testing. However, we recommend opting in to using `tuist xcodebuild` now, so you continuously benefit from new improvements as we ship them, such as detailed analytics and insights of your tests and builds.

Optimizing projects and their interactions is key to making the most of one of the most valuable resources—engineering time. To achieve this, you need actionable insights that inform your decisions. That's why we're committed to providing you with valuable data to help you answer critical questions and create the most efficient development environment:
- Which test is the most flaky and disrupting workflow?
- What targets are becoming compilation bottlenecks, limiting parallelization?
- Which modules would benefit from additional testing?

You can expect these kinds of insights to be soon available in our Tuist dashboard, which is also getting a facelift. Here's a sneak peak, coming later this year:

![Dashboard sneak peek](/marketing/images/blog/2025/02/18/selective-testing-for-xcode-projects/dashboard-sneak-peek.png)

## Wrapping up

Selective testing is a powerful feature that can save you a lot of time and resources. It's available for all Xcode projects, regardless of your setup, and can be used both locally and on the CI. To learn more about how to use it, check out our [documentation](https://docs.tuist.dev/en/guides/develop/selective-testing).

We're also always keen to hear your feedback – if you take selective testing for a spin, let us know how it goes at:
- [Our community forum](https://community.tuist.dev/)
- [Slack](https://slack.tuist.io/)
- [Mastodon](https://fosstodon.org/@tuist)
- [Bluesky](https://bsky.app/profile/tuist.dev)
