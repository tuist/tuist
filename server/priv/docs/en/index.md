---
{
  "title": "What is Tuist?",
  "description": "Tuist is a build platform for engineering teams and their coding agents. It supports build and test workflows across Xcode, Gradle, Bazel, Elixir, and Rust; Once support is in canary. Features vary by toolchain, and Rust compilation caching is experimental."
}
---

# A build platform for teams and their coding agents

**Tuist is a build platform for engineering teams and their coding agents.** It supports build and test workflows across Xcode, Gradle, Bazel, Elixir, and Rust; Once support is in canary. It works with the build systems you already use instead of replacing them. Available features depend on your toolchain: Rust projects get Cargo build and test insights, including doctests, flaky test detection, and experimental compilation caching. Once connects natively for shared caching, build and test insights, sharding, and supported application previews.

Follow one of the <.localized_link href="/guides/get-started">Get Started paths</.localized_link> for your build system. Once connects directly without the Tuist CLI; other paths explain which Tuist tooling to install.

<br/>

<.home_cards>
  <.home_card
    title="Cache"
    details="Share build outputs across your team and CI. Works with Xcode's compilation cache, Tuist's module cache, Gradle's build cache, Bazel's remote cache, Elixir's dependency cache, Rust's experimental compilation cache, and Once's shared action cache."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="Build & test insights"
    details="Track build and test duration, failures, flakiness, and regressions across Xcode, Gradle, Bazel, Elixir, Rust, and Once projects."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Selective testing"
    details="Skip unchanged test targets in generated Xcode projects, with an early-access coverage strategy for individual XCTest/XCUITest selection."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Run CI on managed macOS and Linux runners, close to the same cache your developer machines use."
    link="/guides/features/runners"
/>
  <.home_card
    title="Previews"
    details="Share supported mobile apps, macOS apps, and macOS/Linux command-line tools through a URL. Build, signing, and recipient compatibility requirements apply."
    link="/guides/features/previews"
/>
  <.home_card
    title="Generated projects"
    details="Describe Xcode projects in Swift and generate them consistently. Reduce project-file conflicts and unlock the module cache."
    link="/guides/features/projects"
/>
  <.home_card
    title="Package Registry"
    details="Retrieve supported Swift packages through the registry protocol instead of cloning their Git repositories."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Bundle size"
    details="Track supported Apple and Android bundle sizes over time and investigate size regressions."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Trusted by teams shipping at scale

Read [customer stories](https://tuist.dev/customers) for the workflows teams adopted and the results they reported.
