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
    details="Run only the tests affected by a change in generated Xcode projects, so feedback lands in seconds."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Run CI on managed macOS and Linux runners, close to the same cache your developer machines use."
    link="/guides/features/runners"
/>
  <.home_card
    title="Previews"
    details="Share your app instantly with a URL. No store review delays, no complex setup."
    link="/guides/features/previews"
/>
  <.home_card
    title="Generated projects"
    details="Describe Xcode projects in Swift and generate them consistently. Eliminate merge conflicts and unlock the module cache."
    link="/guides/features/projects"
/>
  <.home_card
    title="Package Registry"
    details="Resolve Swift packages in seconds instead of minutes with a registry backed by Tuist's cache network."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Bundle size"
    details="Analyze and keep your app lean so users get faster downloads and you clear store guidelines."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Trusted by teams shipping at scale

**Teams at [Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/), and 100+ other companies** ship faster with Tuist across their iOS and Android codebases.
