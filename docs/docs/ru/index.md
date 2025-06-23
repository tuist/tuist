---
title: What is Tuist?
description: Extend your Apple native tooling to better apps at scale.
---

<script setup>
import VPFeatures from "vitepress/dist/client/theme-default/components/VPFeatures.vue"
</script>

# From idea to the store

We are the only **integrated extension of Apple's native toolchain to build better apps faster.**

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
</HomeCards>

## Installation

Install Tuist and run `tuist init` to get started:

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

Check out our <LocalizedLink href="/guides/quick-start/install-tuist">installation guide</LocalizedLink> for more details.

## Discover more

Try out Tuist in minutes and learn how to get the most out of Tuist.

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

## Watch our latest talks

Explore our team's presentations. Stay informed and gain expertise.

<HomeVideos :videos="[['Tuist Registry Walkthrough', '2bd2deb4-1897-4c5b-9de6-37c8acd16fb0'],['Running latest Tuist Previews', '6872527d-4225-469d-9b89-2ec562c37603'], ['Inspect implicit imports to make Xcode more reliable and its builds more deterministic', '88696ce1-aa08-48e8-b410-bc7a57726d67'], ['Clean Xcode builds with binary XCFrameworks from Tuist Cloud', '3a15bae1-a0b2-4c6e-97f2-f78457d87099']]"/>

## Join the community

See the source code, connect with others, and get connected.

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
