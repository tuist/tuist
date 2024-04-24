---
title: What is Tuist Cloud
titleTemplate: ':title - Tuist Cloud'
description: Learn about Tuist Cloud, a service that provides a set of features to enhance the development experience with Tuist.
---

# Tuist Cloud

Utilizing a graph of dependencies for representing projects and converting them into Xcode projects showed that this approach could be **foundational for optimizing workflows**, thereby preventing unnecessary time wastage for organization's developers. Key features that leverage this foundational approach include [binary caching](/cloud/binary-caching), which enables the generation of projects with some targets replaced by their pre-compiled binary counterparts, and [selective testing](/cloud/selective-testing), which allows running tests only for the targets impacted by changes.

As we advanced towards enhancing productivity, it became evident that **certain solutions necessitated an HTTP server for state storage and building integrations with other HTTP services** like [GitHub](https://github.com), [Slack](https://slack.com), or [Apple Store Connect](https://appstoreconnect.apple.com/). For instance, caching could leverage a server to share binaries across local and CI environments, thereby accelerating build and test times. This realization led to the creation of Tuist Cloud.

Tuist Cloud, a closed-source paid service, enhances Tuist by adding server-requisite functionalities. Integration of Tuist projects with Tuist Cloud not only augments existing functionalities but also introduces new ones. This service encapsulates years of experience in developing tools for mobile developers at [Shopify](https://shopify.com) (e.g., [Mobile Tophat](https://shopify.engineering/mobile-tophatting-at-shopify-1), [Mobile Release Engineering at Scale](https://shopify.engineering/mobile-release-engineering-scale-shipit-mobile), [Scaling iOS CI with Anka](https://shopify.engineering/scaling-ios-ci-with-anka)) and is envisioned as **the copilot for your platform teams**. Our objective is to help organizations cultivate a productive development environment.

> [!IMPORTANT] PROJECT ONBOARDING
> Due to [Xcode's default to convenience](/guide/introduction/cost-of-convenience) your project might contain implicit configurations that can prevent some Tuist Cloud features from working as expected, and therefore require manual adjustments.

## Sustainability

Similar to many other open-source projects, Tuist also necessitated full-time dedicated personnel to adequately meet the demand for support and feature requests. Tuist Cloud plays a crucial role in fulfilling this requirement by enabling the financing of full-time personnel for the project.

Becoming Tuist Cloud user is synonym to supporting the the development of Tuist and many of the open source that makes Tuist and other community open source projects possible. We wished the economics of open source were much different and organizations and government recognized the value of open source and financially supported it, but at the time of write, that's unfortunately not the case, so creating a business is the only option we were left with.

> [!INFO] BUT I WANT TO USE MY CI CACHE...
> Users often don't understand the need for paying for caching when their CI provider already provides a solution. We understand it, it doesn't make sense logically, but financially, we believe it does, because Tuist has reached a point that needs funding to continue to support its development. Avoiding doing so, like we had to suffer from in the past, puts Tuist and all our efforts at risk.

<!-- > This is a comment we hear often from users. We also had to experience users trying to workaround the CLI measures to ensure exclusivity of the features with Tuist Cloud. -->

## Features

### Binary caching across environments

Tuist Cloud offers a robust storage solution for Tuist, enabling the sharing of cache artifacts between local and remote settings, such as continuous integration. This ensures that developers avoid recompiling targets they don't intend to modify, provided they've already been compiled by a teammate or in a CI setting. Leveraging this caching can yield efficiency [rates up to 90%](https://builders.travelperk.com/tuist-ing-travelperks-ios-app-for-faster-build-times-4796dcfa7809), leading to significant time and cost savings for both local development and CI processes.

> [!TIP] RETURN OF INVESTMENT (ROI)
> To assist organizations in evaluating their return on investment (ROI), we've developed an [**ROI calculator**](https://tuist.io/cloud). For instance, consider an organization with approximately 20 developers. If their clean builds take 10 minutes and they achieve a 70% cache effectiveness, they could potentially reduce development time by 24,000 hours and recover up to $6.4 million a year.

### Selective testing across environments

Once teams reach a certain scale, they often grapple with optimizing their CI process to maintain quick turnaround times. While **testing everything** continually might work for smaller teams, it becomes impractical on a larger scale. At this juncture, many teams resort to investing in superior hardware, creating custom tools, complicating their CI pipelines, or worse, accepting slower development cycles. But there's a better way.

**Tuist Cloud utilizes graph knowledge and fingerprinting technology—essential for binary caching—to discern which targets to test based on file modifications.** Not only that, as your tests will also be able to use binary caching, massively reducing the time it takes to both _build_ and _run_ your tests.

### Analytics

While optimizing workflows based on our project insights is beneficial, it's crucial to ensure that your project's evolution doesn't lead to regressions, adversely affecting the developer experience. While our ultimate goal is to harness AI technologies to offer you a virtual co-pilot, we currently provide foundational insights to enhance your understanding of your project and workflows. This allows you to identify optimization opportunities and make data-driven decisions. We firmly believe this is data that Xcode ought to supply. However, recognizing the clear demand from teams, we're stepping up to deliver it.

> [!INFO] AN INTEGRATED SOLUTION
> You might be familiar with Spotify's open-source tool, [XCMetrics](https://xcmetrics.io/). While it shares a similar objective, its integration demands extra tool installations in developers' settings, and it lacks the ability to correlate data with project specifics. In contrast, Tuist offers enhanced analytics, drawing from the synergy between data and the project graph, and is seamlessly integrated without needing any extra installations.

### Advanced actionable insights <Badge type="warning">In progress</Badge>

Regressions can easily compromise the health of a project, build, or test suites. This is primarily because CI workflows focus on ensuring successful compilation and test suite outcomes. As a result, developers tend to merge pull requests (PRs) once they're approved and both the compilation and test runs are successful. Yet, such PRs might inadvertently affect other vital aspects that directly influence developer productivity. For instance, they could:

- Introduce instability in the test suite.
- Modify build settings, causing a target's compilation time to double.
- Add a new static target to the graph, leading to a substantial increase in the final app size.

In a conventional setup, these issues often go unnoticed until they've become significant problems. By the time they're detected, teams face the daunting task of tracing back to find the root cause before implementing a fix. This becomes especially challenging in dynamic environments where changes are constantly integrated. However, there's a more efficient approach.

We aim to **gather data from builds, including build times, binary sizes, and test outcomes, and integrate this with graph information.** This consolidated data will then be transmitted to our server. From there, developers can **visually track performance trends over time**. Our goal is to not only make this information easily accessible but also **actionable**. By identifying potential deviations that might hinder productivity, we can flag them directly in PRs. This proactive approach ensures that potential regressions are intercepted before merging into the primary repository branch. In essence, Tuist Cloud is designed to serve as a vigilant co-pilot, ensuring a **consistently healthy and efficient development environment**. An optimal development environment is pivotal for maintaining developers' enthusiasm and commitment to the project.

### Test quality <Badge type="tip">Planned</Badge>

A common source of productivity loss is the time spent debugging flaky tests. Flaky tests can happen easily due to the non-functional nature of Swift, and Apple provides no tools to help developers prevent, identify, or fix them. Imagine a developer waiting for 30 minutes to get feedback on a PR, only to find out that the test failure was due to a flaky test. A retry then leads to a not-ready-to-merge green PR because someone had merged a PR that introduced conflicts. After solving the conflicts, the developer waits another 30 minutes to get feedback. This cycle can be frustrating and significantly impacts productivity.

We plan to track flakiness server-side from Tuist Cloud, and extend `tuist test` to dynamically skip the tests that are flaky based on the information provided by Tuist Cloud. Organizations will get a clear view of the sources of flakiness in the dashboard, and have tools to set up tripwires, for example to prevent the introduction of new flaky tests by making PRs fail if they introduce flaky tests.

### Team-scoped metrics <Badge type="tip">Planned</Badge>

We plan to give organizations an API to declare ownership of various parts of the project graph. For example, they'll be able to indicate which team is the owner of a given target. Thanks to this information, platform teams can make teams accountable for various health metrics, such as build times, binary sizes, and test outcomes. This will help organizations to foster a culture of ownership and accountability, and to make data-driven decisions to improve the health of their projects.