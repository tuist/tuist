---
title: "monday.com cut CI time in half"
date: "2025-12-15"
url: "https://monday.com/"
onboarded_date: "2022-06-01"
founded_date: "2012"
company: "monday.com"
excerpt: "monday.com slashed CI times from 20 to 9 minutes and scaled to 200 modules with Tuist. Learn how their 20-engineer iOS team transformed their development workflow."
---

## The challenge

At [monday.com](https://monday.com), we work with a large, mixed iOS codebase that has been evolving for nearly a decade. Dozens of engineers contribute hundreds of commits every month across multiple product areas. What began as a small team eventually grew to almost 20 iOS engineers, and with that growth came real architectural and workflow challenges.

Building the project was slow and messy. We wanted a highly modular setup that allowed developers to build only what they needed, as quickly as possible. But creating modules inside Xcode was painful and error-prone, and the project naturally drifted toward a big monolithic structure. Code became tightly coupled, merge conflicts were common, and restructuring the project often felt like fighting the tool instead of building with it.

> "Restructuring the project often felt like fighting the tool instead of building with it."

The underlying Xcode project format also caused hidden configuration issues. Because everything lived in pseudo-XML, it was easy to end up with unexpected behaviors, inconsistent settings, or modules that behaved differently for reasons no one could easily trace. Understanding why something was configured in a certain way was becoming harder over time. We needed a cleaner, more reliable, and more scalable way to define the project.

## Choosing Tuist

Both [Natan](https://www.linkedin.com/in/natanrolnik/) and [Shai](https://www.linkedin.com/in/shaimishali/) had followed Tuist for years and were already fans of the team and their open source work. Each of us had contributed to Tuist in the past, and Natan had even served on the [core team](https://github.com/tuist/tuist?tab=readme-ov-file#core-alumni), so we knew the project well enough to trust its design, direction, and philosophy. On top of that, Natan and our colleague JD had used Tuist successfully at their previous company, which gave us additional confidence.

We also had the chance to meet Pedro and Marek at a few conferences and left those conversations with a strong sense of trust in both the people and the product. Seeing other large companies use Tuist to solve similar challenges reinforced that we were on the right path. For a rapidly growing project with a massive line count, Tuist felt like the right tool to help us transition from a large monolith to a more modular, scalable, and maintainable architecture.

## The approach

In mid-2022, Natan and JD kicked off a full migration of our Xcode project to Tuist [generated projects](https://docs.tuist.dev/en/guides/features/projects). They began with the leaf nodes, the ones with the fewest dependencies, and gradually worked their way up the dependency hierarchy. The initial pull request was massive, with more than 60,000 changes. Tools like [xcdiff](https://github.com/bloomberg/xcdiff) helped us validate that everything remained consistent throughout the process.

That first migration got the entire team working with Tuist. Over time, we built many of our own abstractions on top of it, including unified Framework and [Project Description Helpers](https://docs.tuist.dev/en/guides/features/projects/code-sharing) that allow anyone on the team to create new modules quickly and safely, as well as custom [Resource Synthesizers](https://docs.tuist.dev/en/guides/features/projects/synthesized-files) for Lottie animations and other specialized resources. Every module also includes its own Preview App, Tests, etc, which lets developers work in complete isolation instead of building the entire application. This was a significant improvement in quality of life and developer experience.

A bit later, we adopted Tuist’s [module cache](https://docs.tuist.dev/en/guides/features/cache). This made a noticeable difference in build times, especially in CI. Today, tuist generate has become a familiar command across the team and a natural part of our daily workflow.

## The results

- All modules, app targets, and configurations are now defined in Tuist’s Swift-based manifests. It provides a  real source of truth, far more transparent and reliable than managing settings inside a pbxproj file.
- We now maintain around 200 modules, and creating new ones is simple enough that anyone on the team feels comfortable doing it. The cost of modularizing has gone way down.
- Our CI merge workflow dropped from more than 20 minutes in 2022 to about 9 minutes today. This came from many improvements across the board, but Tuist's [module cache](https://docs.tuist.dev/en/guides/features/cache) played a significant role. The result is a faster iteration cycle and a meaningful reduction in developer hours lost to waiting on builds.
- It's also much easier to make large-scale changes or experiment with a new build configuration. Because everything is defined in code, large refactors and optimizations feel safer, more predictable, and far more approachable.

> "We now maintain around 200 modules, and creating new ones is simple enough that anyone on the team feels comfortable doing it."

## What’s next

Tuist gives us confidence that we can continue scaling the team and the codebase. Spinning up a new app is basically as simple as creating a new target and reusing the modules we already have, which opens the door for faster experimentation across the engineering team.

We're excited to keep improving the developer experience for our iOS engineers, and we're equally excited to see what the Tuist team builds next. Their work has already had a significant impact on how we ship software, and we expect that impact to continue as we grow.

> "Tuist gives us confidence that we can continue scaling the team and the codebase."
