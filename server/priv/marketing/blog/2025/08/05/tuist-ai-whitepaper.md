---
title: "Tuist's AI whitepaper"
category: "product"
tags: ["vision", "ai", "agents"] 
excerpt: "AI is transforming Apple development. We're exploring agentic coding, QA automation, instant previews, and data accessibility to make Swift development faster and more accessible."
author: pepicrft
---

The level of innovation that AI technologies are unlocking is unprecedented and impossible to ignore. New solutions are challenging existing mental models that were previously constrained by technical limitations or cost structures.

The Tuist team has been closely monitoring developments both within and outside the Apple ecosystem, exploring ideas we could iterate on with the community. We believe these innovations will significantly impact making Swift app development more accessible and helping teams ship better apps.

Drawing inspiration from [Penpot’s excellent AI whitepaper](https://penpot.app/blog/penpot-ai-whitepaper/), this document distills how our team thinks about AI’s role in Apple development. Our vision takes an incremental approach that builds upon our existing investments while deeply acknowledging Apple’s responsibilities in their toolchain and the direction they’re signaling through public repositories. We aim to extend Apple’s tools rather than abstract away from them.

## It starts with an idea

Apps and features begin with ideas. These ideas can emerge anywhere and often carry an energy that fades if left unmaterialized on endless todo lists. _Wouldn’t it be transformative if you could bring them to life the moment inspiration strikes?_

The industry has been building toward this reality. One key concept is remote development environments, which separate the frontend (where coding happens) from the backend (where code is executed and compiled). This pattern emerged to solve challenges around reproducibility, security, and environment telemetry. Tools like [GitPod](https://www.gitpod.io/) and [GitHub Codespaces](https://github.com/features/codespaces) pioneered browser-based development environments, promising you could build from anywhere with just an internet connection.

However, there was a fundamental friction that made these solutions less compelling for rapid idea materialization: bringing ideas to life still required coding, and coding shifted focus away from the idea itself. The experience became particularly challenging on devices with small viewports—_nobody wants to write Swift on an iPhone._

But agentic coding solutions and advanced context engineering have introduced something revolutionary: the ability to build through conversation. You can use your voice to guide the development process while an agent handles the implementation. When you first experience this, especially using voice commands, it feels magical. This opens possibilities for separating the human interface from the technical execution—having an agent work in a remote environment while you interact with it and observe results from anywhere.

This is the premise behind [VibeTunnel](https://vibetunnel.sh/), and if agentic coding feels magical, this approach is even more so. You can build from anywhere, and since you’re guiding rather than coding, it becomes an ideal tool for exploring ideas.

Now, let’s consider how this applies to Apple development. Unlike web projects where browsers serve as the distribution platform (requiring only a server and IP address), Apple maintains a controlled distribution system. You either build and test locally on your device or simulator, or navigate the complex signing process to enable others to test your work. This rigid model challenges the remote development concept because while you can direct an agent to work remotely, you can’t easily preview the results to provide effective guidance.

What if we could solve this challenge? We believe it’s entirely possible. Creating bidirectional streaming that enables embedding and interacting with simulators in browsers is a solved problem—it’s been implemented proprietary and proven legally compliant with Apple’s terms of service. VibeTunnel has demonstrated that running remote agents with browser-based interfaces is feasible. By combining these approaches, we see an opportunity to create a unique prototyping experience accessible from any browser, enabling Apple platform development from non-macOS systems. You’d be developing in a macOS environment while interfacing with it from elsewhere—not just browsers, but potentially iOS itself. Imagine previewing your app, shaking your phone, and using voice commands to request features, then waiting for the agent to complete the implementation.

While this sounds straightforward, significant challenges remain. For instance, if simulators become the rendering platform via video streaming, latency can make the difference between a beloved feature and an abandoned one. Some [React Native](https://reactnative.dev/) solutions use cross-platform components that simulate apps through DOM manipulation, but this approach breaks down when platform-specific capabilities like subscription management are needed. We’ve also seen approaches using dynamic SwiftUI APIs for in-app iteration, but questions remain about whether these produce maintainable codebases developers can continue working with.

Many options exist for exploration in this rapidly evolving space. We’ve seen solutions spanning from editors like [Cursor](https://cursor.com/) to terminals like [Warp](https://www.warp.dev/). Rather than creating another agentic coding solution, we’d like to invest creative energy in exploring what an alternative coding experience to Xcode—designed specifically for igniting ideas—might look like. We don’t envision replacing Xcode or Xcode projects, but we definitely see growing demand for idea exploration without navigating Xcode’s interface. **Just you, your ideas, and a conversational interface.**

Imagine something like [Swift Playgrounds](https://www.apple.com/de/swift/playgrounds/), but reimagined for the AI and agentic world—a place where ideas can be explored through conversation rather than traditional coding patterns. With the space evolving so rapidly, we’re dedicating significant creative energy to exploring this vision, while remaining mindful of the broader landscape and our core mission.

We’ve begun experimenting with [Ignite](https://github.com/tuist/ignite), initially focusing on bundling frontend and backend into an executable that opens the building experience in a browser. This serves as our playground, and once refined, we plan to separate these components so Ignite runs on your system while you interface with it through the [Tuist iOS application](https://github.com/tuist/tuist/tree/main/app).

## A great agentic coding experience

Since Tuist’s inception, we’ve been dedicated to alleviating painful aspects of app development—from interfacing with [undocumented formats designed exclusively for Xcode](https://github.com/tuist/xcodeproj/) to providing alternatives for incremental builds and test runs across environments through binary caching and selective testing. This focus exists because poor experiences make platforms less accessible to newcomers and less enjoyable for experienced developers who want to maintain focus and productivity.

It quickly became apparent that these pain points transfer to agents in agentic coding experiences. Agents require rapid feedback to ensure their work progresses in the right direction. When incremental builds work unreliably, causing unexpectedly long compilation times, the experience degrades. Similarly, if previewing changes requires building the app, installing it in a simulator, and launching it, the slow feedback loop compromises the entire experience.

Agents need fast feedback from multiple sources: the build system, running applications, live previews, and more. Some information can be collected because it exists in the system and either the model has learned about it or accesses it through [Model Context Protocols (MCPs)](https://modelcontextprotocol.io/docs/getting-started/intro). However, agents often lack access to crucial information, such as SwiftUI preview trees resolved at runtime or how the build system processes graphs to generate artifacts.

Some improvements remain outside our direct control, such as enhancing framework documentation, minimizing major Swift changes, or Apple decoupling Xcode’s layers and providing programmatic APIs for extension. Whether these changes occur likely depends on Apple’s willingness to trust their developer community beyond just app creation to include tool enhancement.

The community is actively bridging the gap between agents and official tools. This includes [MCPs that expose CRUD APIs for Xcode projects](https://github.com/giginet/xcodeproj-mcp-server) and solutions that approximate hot-reloading workflows by managing xcodebuild and simulator tools. Until underlying tools provide better APIs and documentation, these translations remain essential.

This brings us to our role. As mentioned earlier, shortening feedback loops is crucial, and we believe this should be our primary contribution. Today, this means binary caching based on project generation, but in the future, when caching is built into the build system, we’re working toward creating the fastest, lowest-latency cache solution that agents can access regardless of their location.

Think of it as edge Xcode build cache. We aim to become the infrastructure enabling agents (and developers) to build apps quickly with Xcode. Beyond speed, we’ll automatically collect diagnostic data from underlying tools to help you understand what went wrong or didn’t proceed as planned. This is why we made [ClickHouse](https://clickhouse.com/) a core infrastructure requirement.

## Work done, it’s time to test it

We believe that in coming years, most coding work will be performed by agents with human guidance and additional context sources. As part of this workflow, you’ll want to verify that work has been completed correctly. Traditionally, this involved running tests in CI pipelines, where feature merging depended on human code approval and CI confirmation of passing tests.

However, agents are already assuming code review responsibilities and excel at this task due to their comprehensive codebase understanding. Agents can also write and execute tests in CI, but there’s one category of particularly valuable tests that companies historically under-invested in due to development and maintenance costs: acceptance tests. These tests most closely mirror actual user experiences.

Acceptance tests are expensive to develop because they require learning imperative interfaces for UI interaction through accessibility APIs. Moreover, the contract and use case being tested often remain implicit, making tests fragile and difficult to fix when they break. While Xcode 26 reduces the cost of writing these tests, it addresses only part of the challenge.

An alternative is QA testing, but this approach is equally or more expensive. Human testers are costly, and the process doesn’t scale effectively. As variability increases, scenarios multiply, and QA teams often end up testing less critical scenarios because they lack business context to prioritize effectively. When issues arise, the diagnostic information they provide is limited—typically written reports and screenshots without logs, network requests, or database and keychain state information. This leads to significant developer time spent on QA interactions.

Consequently, many companies rely solely on unit tests and solid architecture to prevent certain issues, but this approach cannot catch all scenarios. While no solution is perfect, we believe you can approximate comprehensive testing with minimal cost.

_What if an agent could test your app?_ It turns out agents excel at this task. A QA agent needs the app artifact, the device model, and a macOS environment for test execution—exactly what local development environments provide. However, you’ll likely want testing triggered by remote actions, such as PR comments, similar to how pipeline jobs compile changes. In an agent-driven world, we might have various coding options and multiple QA solutions, each operating in dedicated environments.

We have all the necessary components for agentic QA. We support [previews](https://docs.tuist.dev/en/guides/features/previews) for app bundle uploads with associated commit and branch tracking. We integrate with GitHub for event-driven actions. We’re building integration with Namespace for spinning up macOS environments where agents can operate. Early results are promising.

You mention us in a PR, and we respond shortly after with a summary and link to a detailed testing report that includes logs, screenshots, and all necessary diagnostic information. We gather context from PRs and other sources, such as `QA.md` files.

Instead of developing and maintaining expensive acceptance test suites, you can simply tag us to test work, and we handle the rest.

## Share the work

We believe previews will play a crucial role in an agent-driven world where AI handles building and testing. You’ll want to run applications or share them with others to gather feedback for agents to improve features before merging.

Current preview solutions resemble nightly builds or [App Center](https://appcenter.ms/) alternatives, all suffering from the same limitation: without enterprise certificates, if target devices aren’t included in certificates, you must re-sign apps, often retriggering entire pipelines and re-exports. This process is quite inconvenient.

For this reason, we’re investing in on-demand signing. We’ll sign previews during installation when needed, ensuring target devices are included in certificates. This shifts signing responsibility from the build process to the installation phase. We aim to make this so fast and transparent that it feels magical.

**Everyone in your organization will be one tap away from trying previews and helping agents improve their work.** We’ll also build an SDK that collects feedback and forwards it to places where agents can access context, whether Slack channels or GitHub PRs. If we develop an alternative experience for idea ignition, you’ll have a “share” button that completes with “here’s your link, share it with the world”—because that’s how we believe developer experience should work.

## Making data accessible

Apple development has traditionally kept formats and compile-time/runtime data proprietary, undocumented, and coupled to their tools. This creates transitive dependence on Apple for building interfaces to this data, which in the AI era represents a crucial context source for guiding agentic workflows.

Fortunately, collecting, standardizing, and making data accessible has been our focus for some time. From bundle analysis built on standard schemas that [Rosalind](https://github.com/tuist/Rosalind) generates from paths, to build insights parsed from .xcactivitylog files generated at compile time—this information proves indispensable for human decision-making and, as you might expect, valuable for agents. We’ll continue seeking opportunities to derive this data (we’re currently working on test insights) and make it accessible so agents can access precisely what they need.

If you’ve used tools like [Claude Code](https://www.anthropic.com/claude-code), you’ve likely noticed it knows how to interface with GitHub CLI to view PR comments and address them. GitHub provides data and makes it accessible through CLI for agent consumption. We’re adopting a similar approach, where agents can plan work by examining flaky tests in test suites or optimize project build parallelization by analyzing project graphs and build result data.

As mentioned earlier, since these formats and internal layers are designed to feed upper internal layers rather than external tools that could enhance development experience, Apple may be hesitant to expose them. Opening these systems might enable ecosystem development around alternative coding experiences, as we’re seeing with increased Cursor adoption for iOS development. While we believe such openness would be hugely beneficial, Apple’s approach continues to evolve in interesting ways that suggest growing openness to developer tool innovation.

## The journey ahead

What dominates discussions today may be obsolete tomorrow. The pace of change in this space is extraordinary, which is why we approach these ideas with an exploratory mindset, discussing and refining them weekly as a team. We remain open-minded in some areas while focusing our energy where we see solid opportunities, like Tuist QA.

Moreover, some problems like coding can be well-addressed by generic solutions like Claude Code that have learned Swift and can interface with external systems through MCPs. However, other challenges benefit from vertical solutions built upon existing platforms, specifically designed for app development and requiring ecosystem knowledge and expertise—which we’ve developed over years of building tools for Xcode and Swift.

We’ll focus on areas where we can bring exceptional value within our vertical—value that organizations can perceive instantly and that wouldn’t make economic sense for generic solutions to pursue. Our deep understanding of Apple’s ecosystem, combined with years of solving developer pain points, positions us to deliver specialized solutions that generic tools simply can’t justify building.

We built Tuist to help teams and developers address existing challenges, but also to explore ideas that make development more enjoyable and accessible to everyone. We want more people building more apps for the Apple ecosystem.

-----

**Get involved:** If you’re intrigued by any of these ideas or would like to try the experiences we’re building, we’d love to hear from you. Reach out to us at [contact@tuist.dev](mailto:contact@tuist.dev) or join the conversation in our community. The future of Apple development is being written now, and we believe it’s better when we write it together.
