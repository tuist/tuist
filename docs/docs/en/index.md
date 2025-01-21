---
title: What is Tuist?
description: Extend your Apple native tooling to better apps at scale.
---

<script setup>
import VPFeatures from "vitepress/dist/client/theme-default/components/VPFeatures.vue"
</script>

# From idea to the store

Extend Apple's toolchain to build better apps faster

<HomeCards>
    <HomeCard icon="📝"
        title="Generated projects"
        details="A Swift-based DSL to make Xcode projects more managleable and scalable."
        linkText="Create or migrate project"
        link="/guides/develop/projects"/>
    <HomeCard icon="📦"
        title="Cache"
        details="Get faster compilations by skipping compilation with cached binaries."
        linkText="Speed up compilations"
        link="/guides/develop/cache"/>
    <HomeCard
        icon="✅"
        title="Selective testing"
        details="Skip test targets when the dependent-upon code hasn't changed."
        linkText="Speed up test runs"
        link="/guides/develop/selective-testing"/>
    <HomeCard
        icon="📱"
        title="Previews"
        details="Share previews of your app with a URL that launches the app on a click."
        linkText="Share your apps"
        link="/guides/share/previews"/>
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

<!-- TODO -->
<!-- - Awesome repository -->


## Watch our latest talks

Explore our team's presentations. Stay informed and gain expertise.

<!-- TODO -->

## Join the community

See the source code, connect with others, and get connected.
