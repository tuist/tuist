---
title: Workflows
titleTemplate: :title · Automate · Develop · Guides · Tuist
description: Automate your workflows in Swift.
---

# Workflows {#workflows}

For years, the community relied on [Fastlane](https://fastlane.tools/), a [Ruby-based](https://www.ruby-lang.org/en/) automation tool focused on app development. Ruby's dynamic runtime, [Bundler](https://bundler.io/) dependency manager, and a strong community created a rich ecosystem of Gems and lanes for building workflows.

However, as the Swift community gravitates toward Swift, writing and debugging automation in Ruby poses challenges for those less familiar with the language. Swift, already used for app development and project configuration, presents a compelling alternative: **What if developers could use Swift to automate their workflows too?**

**Tuist Workflows** is our answer. It embodies principles inspired by scripting languages like Ruby and Bash:

1. **Speed:** Instant execution to maintain productivity.
2. **Stability:** Reliable foundations that work now and in the future.
3. **Portability:** Seamless use across environments.
4. **Composability:** Reuse of third-party business logic.

Our community-first approach ensures Tuist Workflows isn’t just a tool but a thriving and collaborative ecosystem.

## Workflow

A workflow is a Swift executable file under the `Tuist/Workflows` directory:

```swift
// Tuist/Workflows/build.swift

print("Hello world")
```
