---
title: Tuist란?
description: Apple의 기본 도구를 확장하여 더 나은 앱을 효과적으로 개발하세요.
---

<script setup>
import VPFeatures from "vitepress/dist/client/theme-default/components/VPFeatures.vue"</script>

# From idea to the store

우리는 **더 나은 앱을 더 빠르게 개발할 수 있도록 Apple의 기본 도구와 통합된 확장 도구**입니다.

<br/>

<HomeCards>
    <HomeCard icon="📝"
        title="Generated projects"
        details="A Swift-based DSL to make Xcode projects more managleable and scalable."
        linkText="Create or migrate project"
        link="/guides/features/projects"/>
    <HomeCard icon="📦"
        title="Cache"
        details="Get faster compilations by skipping compilation with cached binaries."
        linkText="Speed up compilations"
        link="/guides/features/cache"/>
    <HomeCard
        icon="✅"
        title="Selective testing"
        details="Skip test targets when the dependent-upon code hasn't changed."
        linkText="Speed up test runs"
        link="/guides/features/selective-testing"/>
    <HomeCard
        icon="📱"
        title="Previews"
        details="Share previews of your app with a URL that launches the app on a click."
        linkText="Share your apps"
        link="/guides/features/previews"/>
    <HomeCard
        icon="📦"
        title="Registry"
        details="Cut down the size of your resolved packages and the resolution time. From minutes to seconds."
        linkText="Speed up package resolution"
        link="/guides/features/registry"/>
    <HomeCard
        icon="📊"
        title="Insights"
        details="Get project insights to maintain a productive developer environment."
        linkText="Track project health"
        link="/guides/features/insights"/>
    <HomeCard
        icon="🧰"
        title="Bundle size"
        details="Find out how to make and keep your app's memory footprint as small as possible."
        linkText="Analyze your app bundle"
        link="/guides/features/bundle-size"/>
    <HomeCard
        icon="🤖"
        title="Agentic Coding"
        details="Bridge the gap between Apple development and AI-powered coding. Our tools integrate seamlessly with AI assistants and coding agents."
        linkText="Explore AI integration"
        link="/guides/features/agentic-coding/mcp"/>
</HomeCards>

## Installation

Tuist를 설치하고 `tuist init`을 수행해 시작합니다:

::: code-group

```bash [Homebrew]
brew tap tuist/tuist
brew install --formula tuist

tuist init
```

```bash [Mise]
mise x tuist@latest -- tuist init
```

:::

더 자세한 내용은 <LocalizedLink href="/guides/quick-start/install-tuist">설치 가이드</LocalizedLink> 를 확인하세요.

## Why Tuist? Four compelling reasons

### Simplify complex projects 🌱

As projects grow and span multiple platforms, modularization becomes crucial. Tuist streamlines this complexity, offering tools to optimize and better understand your project's structure.

### Optimize your workflows 🚀

Leveraging project information, Tuist enhances efficiency through selective test execution and deterministic binary reuse across builds - cutting build times by up to 65%.

### Foster healthy project evolution 📈

We provide insights into your project's dynamics and expert guidance for informed decision-making. This prevents the frustration and productivity loss associated with unhealthy projects, which can lead to developer attrition and missed business goals.

### Break down development silos 💜

Unlike platform-specific ecosystems (e.g., Xcode's contained environment), Tuist offers web-centric experiences and integrates seamlessly with popular tools like Slack, Prometheus, and GitHub, enhancing cross-tool collaboration.

---

## Solving the platform team problem

In Apple platform development, organizations often encounter **productivity roadblocks** - sluggish compilation times, unreliable tests, and intricate automation workflows that drain resources. Traditionally, companies address these issues by forming dedicated platform teams. However, this approach can be expensive and risky, as the departure of key team members can severely impact productivity.

**Tuist serves as your virtual platform team.** We integrate seamlessly with official Apple tools and systems, meeting developers in familiar territory. By shouldering the burden of tool and system integration, we enable teams to channel their energy into feature development and improving the developer experience.

Tuist is comprised of a [CLI](https://github.com/tuist/tuist), which is the main entry point for developers, and a server that the CLI integrates with to persist state and integrate with other publicly available services.

## 더 알아보기

몇 분 안에 Tuist를 사용해 보고, Tuist를 최대한 활용하는 방법을 배워봅니다.

<HomeCards type="carousel">
    <HomeCard icon="⚙️"
        title="Examples"
        details="Check out examples of generated Xcode projects."
        linkText="Show me examples"
        link="/references/examples/app_with_airship_sdk"/>
    <HomeCard
        icon="🌈"
        title="awesome-tuist"
        details="A community-driven collection of Tuist related blog posts, tasks, projects, and more."
        linkText="Show me the awesomeness"
        link="https://github.com/tuist/awesome-tuist"/>
    <HomeCard
        icon="📚"
        title="Handbook"
        details="Learn more about the open company behind Tuist."
        linkText="Read the hadnbook"
        link="https://handbook.tuist.dev"/>
</HomeCards>

## 최신 내용 확인

우리 팀의 발표를 확인하세요. 최신 정보를 얻고 전문성을 키워보세요.

<HomeVideos/>

## 커뮤니티 참여

소스 코드를 확인하고, 다른 사람들과 교류하며 소통하세요.

<HomeCommunity>
    <HomeCommunityItem title="Forum" description="Interact with other community members in a synchronous manner" href="https://community.tuist.dev">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="Slack" description="Interact with other community members in a synchronous manner" href="https://slack.tuist.io/">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="Videos" description="Watch talks from the Tuist team and the community" href="https://videos.tuist.dev/">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="GitHub" description="Check out our contributions to open source" href="https://github.com/tuist">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="Bluesky" description="Follow us on Bluesky to stay up to date with our work" href="https://bsky.app/profile/tuist.dev">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="Mastodon" description="Follow us on Bluesky to stay up to date with our work" href="https://fosstodon.org/@tuist">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="LinkedIn" description="Follow Tuist on LinkedIn for news and updates" href="https://www.linkedin.com/company/tuistio">
        <template v-slot:logo></template>
    </HomeCommunityItem>
    <HomeCommunityItem title="Reddit" description="Get the latest updates on r/tuist" href="https://www.reddit.com/r/tuist/">
        <template v-slot:logo></template>
    </HomeCommunityItem>
</HomeCommunity>
