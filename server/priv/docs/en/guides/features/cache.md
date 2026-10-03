---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# Cache {#cache}

Build artifacts are not shared across environments, forcing you to rebuild the same code over and over. Tuist's caching feature shares artifacts remotely so your team and CI get faster builds without rebuilding what has already been built.

Learn the cache workflow that matches your project or deployment model:

<.home_cards>
  <.home_card
    title="Module cache"
    details="Cache individual modules as binaries for projects using Tuist's generated projects. Requires Tuist project generation."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode cache"
    details="Share Xcode compilation artifacts across environments. Works with any Xcode project, no project generation required."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle cache"
    details="Share Gradle build cache artifacts remotely. Includes build insights for performance visibility."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel cache"
    details="Point Bazel at Tuist's Remote Execution API cache to share action outputs across your team and CI."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Self-hosting"
    details="Run cache nodes close to CI, offices, or regional compute and connect them to hosted or self-hosted Tuist."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Fastest on Tuist Runners**
>
> On <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, the cache is colocated on the runner's private network and shared with the same cache your developer machines use, so CI jobs get warm hits out of the box, with no separate CI cache to warm up.


## Restrict uploads to CI {#restrict-uploads-to-ci}

Account administrators can make developers read-only while allowing CI to upload cache artifacts. Open the account's **Cache** settings in Tuist and set **Cache upload access** to **CI and account tokens only**. After that, members authenticated with login sessions can still download from the cache, but uploads require CI OIDC authentication or an account token with cache write scopes such as `project:cache:write` or `ci`.

Use this when CI is the trusted cache producer and local machines should only consume the cache. The setting affects cache upload authorization only.
