---
title: "The evolution of Mobile CI: Navigating the shift to Infrastructure-as-a-Service"
category: "community"
tags: ["ci-cd", "mobile-development", "infrastructure", "github-actions", "market-trends"]
excerpt: "The mobile CI landscape is undergoing a fundamental transformation. As GitHub Actions and infrastructure providers reshape the market, we explore what this means for developers, CI providers, and the future of mobile development workflows."
author: pepicrft
og_image_path: /marketing/images/blog/2025/06/18/mobile-ci.jpg
---

At Tuist, we have the privilege of engaging with numerous organizations, understanding their challenges, and identifying their needs. One recurring theme that emerges from these conversations is continuous integration—a critical component that companies rely on not only to validate changes before merging to `main`, but also to automate release builds and App Store deployments.

I'll be candid: we've seriously considered entering the CI space ourselves to provide Tuist users with a premium, reliable solution. However, the deeper we analyzed this domain, the clearer it became that the industry is experiencing a fundamental transformation. We're witnessing the emergence of a new paradigm—one where Tuist is strategically positioned to operate at a higher abstraction layer above this evolving landscape.

## Understanding the CI Stack

From a user's perspective, CI appears straightforward: a service integrated with your repository that executes workflows triggered by specific actions (typically repository events like code pushes) and delivers results through logs, artifacts, and status updates. However, if we deconstruct CI into its fundamental layers, we discover three distinct components, starting from the foundation:

- **Infrastructure Layer:** The bedrock requiring physical hardware and virtualization technology to run tasks in isolation. Apple's ecosystem adds unique complexity here—most tasks require Apple hardware running macOS, creating scarcity since few cloud providers offer managed Apple infrastructure.

- **Orchestration Layer:** The middleware connecting infrastructure to Git platforms like GitHub, triggering workflows based on repository events. This layer manages pipeline execution, defining the sequence and logic of tasks within each workflow.

- **User Interface Layer:** The customer-facing experience for workflow management, providing real-time execution feedback, manual triggers, and analytical insights (such as average execution times and success rates).

While you might not have previously considered these architectural details, this layered approach fundamentally defines how CI systems operate.

## The Mobile DevOps Movement

Several years ago, I encountered the term "Mobile DevOps" and found myself puzzled. My initial reaction was: "Isn't Mobile DevOps essentially just Fastlane?" I questioned why this concept was suddenly gaining traction and what was driving its emergence. Initially, the movement seemed unclear, but as I gained deeper industry insights, I recognized this as a strategic evolution aimed at expanding the addressable market. In business terms, companies were seeking to grow beyond traditional CI boundaries to capture larger market opportunities.

DevOps makes intuitive sense in backend engineering, where teams manage production infrastructure and orchestrate complex deployments. This need spawned an entire ecosystem: foundations, open-source tools like Kubernetes, and specialized conferences. However, mobile development operates differently. Developers spend most of their time in Xcode, while CI workflows typically focus on building, testing, releasing, and linting code. For years, Fastlane successfully abstracted these needs and cultivated a thriving ecosystem around them.

Yet the appetite for capturing this value persisted. Companies invested heavily in proprietary solutions designed to create ecosystem lock-in and cross-sell additional products. We've seen everything from proprietary pipeline formats to visual pipeline editors, to custom step ecosystems that—lacking community contribution incentives—quickly became outdated. Today's landscape includes release automation, test analytics, caching solutions, and more—all under the Mobile DevOps umbrella. However, for many practitioners, these remain fundamentally CI companies, which creates both opportunities and challenges due to entrenched mental models.

It's worth noting that many providers outsource infrastructure and virtualization to third parties, avoiding hardware management complexities. While this simplifies operations, it significantly impacts margins, making orchestration and UI the primary value-capture layers for most providers.

## The runs-on Revolution

GitHub fundamentally disrupted the market years ago, with other platforms like GitLab and Forgejo following suit. Their decision wasn't merely to become CI providers—they opened up the architectural layers, enabling users to bring their own infrastructure or leverage specialized third-party providers.

This shift has profound implications that deserve more discussion. GitHub Actions (and equivalents on other platforms) offers tight UI integration that external CI providers simply cannot match. Third-party providers are constrained by available APIs, primarily limited to updating commit statuses and adding code annotations. Meanwhile, GitHub can ship features like declarative permissions, dynamically generating workflow-scoped tokens with precise permission boundaries.

The GitHub Actions ecosystem represents another strategic advantage. Initially, I assumed it was proprietary, but using Forgejo via Codeberg revealed that their CI solution supports GitHub Actions composition. Fundamentally, these are Node.js/JavaScript functions with configuration files declaring action behavior. GitHub's unique position allows them to incentivize developer contributions through a simple mental model: build an action, host it in a repository, and enhance your developer profile. This ecosystem effect is difficult to replicate. I'm curious to see how [Dagger](https://dagger.io/)'s attempt to decouple actions from CI providers evolves, though their Docker-centric approach may face challenges with Apple's macOS and hardware requirements.

This new model birthed a different category of companies—those focused exclusively on providing the fastest, most reliable infrastructure for CI needs. At Tuist, we recently adopted [Namespace](https://namespace.so/) for our CI requirements and will soon leverage it for product features requiring ephemeral macOS environments. The setup process is remarkably simple: install a GitHub app and update the `runs-on` attribute in your workflow files.

The `runs-on` attribute represents one of the most elegant [narrow waists](https://www.oilshell.org/blog/2022/02/diagrams.html) I've encountered recently. With a single line change, you can switch infrastructure providers within GitHub Actions. This benefits users by creating competitive pressure on runner providers to deliver superior service or risk losing customers. This stands in stark contrast to the traditional model where organizations found themselves trapped, facing days or weeks of migration effort that often resulted in vendor lock-in and price exploitation. Technology should prioritize user and organizational needs—not vendor profits.

## A Market in Transition

The comprehensive mobile CI solution market is experiencing a gradual decline. The transition's pace depends on infrastructure providers' ability to effectively market themselves within new ecosystems like mobile development. Additionally, this mental model shift—where teams return to GitHub Actions while paying only for infrastructure usage—will take time to permeate the industry. This approach isn't just superior; it's typically more cost-effective than traditional models where companies operate with constrained margins.

I've written previously about the importance of [owning your automation](/blog/2025/03/11/own-your-automation), and it bears repeating. While vendor lock-in is inevitable to some degree—even excellent developer experience creates switching costs—it exists on a spectrum. When companies recognize market decline without innovation capabilities (hello, innovator's dilemma), desperate attempts to increase lock-in often follow. Stay vigilant and maintain ownership of your automation. A key indicator of automation ownership is pipeline simplicity. Tools like [Mise](/blog/2025/02/04/mise) enable predictable environment provisioning, while [Fastlane](https://fastlane.tools/) or even bash scripts can handle automation logic. This agency is crucial in a rapidly evolving space, particularly as the infrastructure-as-a-service market accelerates. More providers will enter, prices will continue declining, and service quality will improve. If you're skeptical, I encourage you to explore Namespace's dashboard.

## An Emerging Landscape

This transformation naturally drives mobile CI companies to reinvent themselves through concepts like Mobile DevOps—evident in their expansion beyond traditional CI offerings. Suddenly, we find ourselves in a more competitive landscape, which I believe benefits the entire mobile ecosystem. The CI space had grown stagnant: everything revolved around pipelines, providers monopolized affordable macOS environments, and innovation stalled around familiar concepts (YAML pipelines, nightly releases, CI-driven deployments). The industry craves innovation, especially given the revolutionary changes in AI and agentic coding experiences.

Every company is placing strategic bets on this emerging landscape. Some maintain narrow focus—perhaps on release management or launch time optimization. We initially maintained a narrow focus too, but we're gradually expanding for one compelling reason: AI is dramatically reducing software production costs and democratizing development. Yet current workflows often require indirection and complexity that diminish the space's appeal. We need to reintroduce magic to mobile development! Imagine agents that test your changes and provide runtime intelligence, or systems that identify flaky tests and automatically open PRs to resolve issues blocking your team.

Is this Mobile DevOps? I don't believe so—that term has served its purpose. What’s emerging is something more modular and layered. We look to platforms like [Vercel](https://vercel.com/) and [Expo](https://expo.dev/) as our north stars, not just for their seamless repository integration and comprehensive tooling, but for how they abstract away infrastructure complexity while delivering a first-class developer experience.

This is where the new model shines: you can now choose any macOS runner provider in an increasingly commoditized space, thanks to the “runs-on” revolution. The infrastructure layer becomes interchangeable, and on top of that, we (and others) can build a specialized layer that provides mobile-specific insights, mobile previews, and developer-centric features. Tuist is designed to work regardless of which runner provider you choose, ensuring you’re never locked in and always able to benefit from innovation at every layer.

In this sense, the real transformation is about decoupling: the infrastructure layer is separated from the developer experience layer. This empowers teams to select the best underlying compute for their needs, while still enjoying a rich, mobile-first platform experience—on-the-go releases, preview sharing via simple links, and proactive notifications about potential test flakiness. This is the essence of the “runs-on” revolution, and it’s what sets this new era apart from the Mobile DevOps of the past.

## Looking Forward

The future holds tremendous promise, and this market transition represents the best possible outcome for our ecosystem. Organizations will simultaneously reduce costs and receive superior service, while infrastructure becomes more affordable and accessible, enabling companies like ours to compete alongside industry giants undergoing their own transformations. The result? The innovation our industry desperately needs.

For established CI providers, this shift presents both challenges and opportunities. Those who recognize and adapt to this new paradigm—focusing on their unique value propositions while embracing the infrastructure-as-a-service model—will thrive. The key lies in understanding that the market isn't disappearing; it's evolving. Success will come to those who can navigate this transition while continuing to deliver exceptional value to their users.

The mobile development landscape is ready for its next chapter. Are you?
