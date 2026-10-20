---
layout: home

hero:
  name: "Once"
  text: "Run once. Reuse anywhere."
  tagline: Once turns ordinary project automation into content-addressed actions with explicit inputs, outputs, environment, and runtime metadata.
  image:
    src: /logo.png
    alt: Once
  actions:
    - theme: brand
      text: Why
      link: /guide/why
    - theme: alt
      text: Scripts
      link: /guide/scripts/
    - theme: alt
      text: View on GitHub
      link: https://github.com/tuist/tuist/tree/main/once
features:
  - title: Actions stay flexible
    details: Keep existing commands, tools, and workflows in place. Add a small execution contract around the work you want to cache.
  - title: Deterministic cache keys
    details: Inputs, outputs, environment variables, working directories, and timeouts become part of the action contract.
  - title: Providers
    details: Provider implementation is decoupled from actions, so teams can choose local cache storage, Tuist, and future remote compute providers.
---
