---
title: What is Tuist?
description: Extend your Apple native tooling to better apps at scale.
layout: home
hero:
  name: Tuist
  text: From idea to the store
  tagline: Extend Apple's toolchain to build better apps faster
  image:
    src: /logo.png
    alt: Tuist
  actions:
    - theme: brand
      text: What is Tuist?
      link: /ko/guides/tuist/about
    - theme: alt
      text: Quick start
      link: /ko/guides/quick-start/install-tuist
    - theme: alt
      text: View on GitHub
      link: https://github.com/tuist/tuist
features:
  - icon: 📝
    title: Projects
    details: A Swift-based DSL to make Xcode projects more managleable and scalable.
    linkText: "Create or migrate project"
    link: "/ko/guides/develop/projects"
  - icon: 📦
    title: Cache
    details: |
      <div style="margin-bottom: 1rem; background: var(--vp-custom-block-tip-code-bg); color: var(--vp-c-tip-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">Requires a Tuist project</div>
      <p>
      Get faster compilations by skipping compilation with cached binaries.
      </p>
    linkText: "Speed up compilations"
    link: "/ko/guides/develop/cache"
  - icon: ✅
    title: Selective testing
    details: |
      <div style="margin-bottom: 1rem; background: var(--vp-custom-block-tip-code-bg); color: var(--vp-c-tip-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">Requires a Tuist project</div>
      <p>
      Skip test targets when the dependent-upon code hasn't changed.
      </p>
    linkText: "Speed up test runs"
    link: "/ko/guides/develop/selective-testing"
  - icon: 📱
    title: Previews
    details: Share previews of your app with a URL that launches the app on a click.
    linkText: "Share your apps"
    link: "/ko/guides/share/previews"
---

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
