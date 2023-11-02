# What is Tuist Cloud

Addressing large-scale challenges necessitates persisting state and service integration, for which Tuist Cloud is key. This paid solution is vital for Tuist project integration and its open-source project's longevity.

## Overview

Utilizing a graph of dependencies for representing projects and converting them into Xcode projects showed that this approach could be **foundational for optimizing workflows**, thereby preventing unnecessary time wastage for organization's developers. Key features that leverage this foundational approach include **local binary caching**, which enables the generation of projects with some targets replaced by their pre-compiled binary counterparts, and selective testing, which allows running tests only for the targets impacted by changes.

As we advanced towards enhancing productivity, it became evident that **certain solutions necessitated an HTTP server for state storage and building integrations with other HTTP services** like [GitHub](https://github.com), [Slack](https://slack.com), or [Apple Store Connect](https://appstoreconnect.apple.com/). For instance, caching could leverage a server to share binaries across local and CI environments, thereby accelerating build and test times. This realization led to the creation of Tuist Cloud.

Tuist Cloud, a closed-source paid service, enhances Tuist by adding server-requisite functionalities. Integration of Tuist projects with Tuist Cloud not only augments existing functionalities but also introduces new ones. This service encapsulates years of experience in developing tools for mobile developers at [Shopify](https://shopify.com) (e.g., [Mobile Tophat](https://shopify.engineering/mobile-tophatting-at-shopify-1), [Mobile Release Engineering at Scale](https://shopify.engineering/mobile-release-engineering-scale-shipit-mobile), [Scaling iOS CI with Anka](https://shopify.engineering/scaling-ios-ci-with-anka)) and is envisioned as **the copilot for your platform teams**. Our objective is to help organizations cultivate a productive development environment.

> Note: Similar to many other open-source projects, Tuist also necessitated full-time dedicated personnel to adequately meet the demand for support and feature requests. Tuist Cloud plays a crucial role in fulfilling this requirement by enabling the financing of full-time personnel for the project.

## Features

### Available

#### 📦 Binary caching across environments

Tuist Cloud offers a robust storage solution for Tuist, enabling the sharing of cache artifacts between local and remote settings, such as continuous integration. This ensures that developers avoid recompiling targets they don't intend to modify, provided they've already been compiled by a teammate or in a CI setting. Leveraging this caching can yield efficiency rates up to 90%, leading to significant time and cost savings for both local development and CI processes.

> Tip: To assist organizations in evaluating their return on investment (ROI), we've developed an [**ROI calculator**](https://tuist.io/cloud). For instance, consider an organization with approximately 20 developers. If their clean builds take 10 minutes and they achieve a 70% cache effectiveness, they could potentially reduce development time by 24,000 hours and recover up to $6.4 million a year.

#### Incremental build and test execution across environments ✅

Once teams reach a certain scale, they often grapple with optimizing their CI process to maintain quick turnaround times. While **building and testing everything** continually might work for smaller teams, it becomes impractical on a larger scale. At this juncture, many teams resort to investing in superior hardware, creating custom tools, complicating their CI pipelines, or worse, accepting slower development cycles. But there's a better way.

**Tuist Cloud utilizes graph knowledge and fingerprinting technology—essential for binary caching—to discern which targets to build and test based on file modifications.** Best of all, this behavior can be fine-tuned using additional hashing keys. For instance, while you might choose to build and test everything on the `main` branch, you can adopt an incremental approach from the primary trunk when development diverges. This approach is not only efficient but also cost-effective for teams.

#### Basic insights 📈

While optimizing workflows based on our project insights is beneficial, it's crucial to ensure that your project's evolution doesn't lead to regressions, adversely affecting the developer experience. While our ultimate goal is to harness AI technologies to offer you a virtual co-pilot, we currently provide foundational insights to enhance your understanding of your project and workflows. This allows you to identify optimization opportunities and make data-driven decisions. We firmly believe this is data that Xcode ought to supply. However, recognizing the clear demand from teams, we're stepping up to deliver it.

> Info: You might be familiar with Spotify's open-source tool, [XCMetrics](https://xcmetrics.io/). While it shares a similar objective, its integration demands extra tool installations in developers' settings, and it lacks the ability to correlate data with project specifics. In contrast, Tuist offers enhanced analytics, drawing from the synergy between data and the project graph, and is seamlessly integrated without needing any extra installations.


### In development

#### Advanced actionable insights 📈

Regressions can easily compromise the health of a project, build, or test suites. This is primarily because CI workflows focus on ensuring successful compilation and test suite outcomes. As a result, developers tend to merge pull requests (PRs) once they're approved and both the compilation and test runs are successful. Yet, such PRs might inadvertently affect other vital aspects that directly influence developer productivity. For instance, they could:

- Introduce instability in the test suite.
- Modify build settings, causing a target's compilation time to double.
- Add a new static target to the graph, leading to a substantial increase in the final app size.

In a conventional setup, these issues often go unnoticed until they've become significant problems. By the time they're detected, teams face the daunting task of tracing back to find the root cause before implementing a fix. This becomes especially challenging in dynamic environments where changes are constantly integrated. However, there's a more efficient approach.

We aim to **gather data from builds, including build times, binary sizes, and test outcomes, and integrate this with graph information.** This consolidated data will then be transmitted to our server. From there, developers can **visually track performance trends over time**. Our goal is to not only make this information easily accessible but also **actionable**. By identifying potential deviations that might hinder productivity, we can flag them directly in PRs. This proactive approach ensures that potential regressions are intercepted before merging into the primary repository branch. In essence, Tuist Cloud is designed to serve as a vigilant co-pilot, ensuring a **consistently healthy and efficient development environment**. An optimal development environment is pivotal for maintaining developers' enthusiasm and commitment to the project.

### Planned

#### Previews 🔎

In many standard setups, developers might forgo testing feature implementations within a pull request to avoid the compilation cycle. As a result, non-developers often rely on nightly builds to conduct their tests. By the time they identify a bug or regression, the pull request has usually been merged, necessitating an interruption for the original developer to investigate and address the issue. But imagine if testing new features were so swift and seamless that anyone within the organization could experience and provide feedback on enhancements within moments of their creation?

The idea of **"previews" is a familiar one in the web domain**. At Shopify, we introduced a version termed ["tophat."](https://shopify.engineering/mobile-tophatting-at-shopify-1) Its speed and fluidity ensured developers consistently tested changes during the review phase. This fostered such efficient cross-team and cross-role collaboration that it became a regular occurrence. Our goal with Tuist is to emulate this efficiency. With just a couple of commands, developers will obtain a shareable URL. Colleagues can then use this link to effortlessly run the app on a simulator or launch Xcode with the necessary framework/library linked, facilitating hands-on exploration. **It's next-level collaborative efficiency.**

## Plans

One of the initial decisions you or your organization must make is **determining the plan that best suits your needs**. Below is a breakdown of the available plans along with some recommendations to help you assess whether a particular plan aligns with your requirements:

#### Indie

If you are an **individual developer** working on a project, this is the advised option. It provides access to the complete feature set, however, it does not permit granting access to the project to others. It's important to note that the support available under this plan is community-based, hence it does not have as high a priority as the support provided in the plans listed below.

#### Team

If there are **multiple people working on the project**, this is the recommended option. You will be able to create organizations that serve as the umbrella for multiple projects and invite people to join the organization. This plan provides access to the complete feature set and also includes community-based support, similar to the Indie plan.

#### Enterprise

For organizations that prefer to host the software on their own infrastructure, require SAML Single-Sign-On, and seek additional, prioritized support and advice from the creators of Tuist and Tuist Cloud, we offer an enterprise plan. If this option interests you, please reach out to [sales@tuist.io](mailto:sales@tuist.io).
If you are already an enterprise customer of Tuist Cloud, you can follow our <doc:Tuist-Cloud-Tutorial> tutorials to run Tuist Cloud on your infrastructure.
