---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, and Gradle cache."
}
---
# Cache {#cache}

Build artifacts are not shared across environments, forcing you to rebuild the same code over and over. Tuist's caching feature shares artifacts remotely so your team and CI get faster builds without rebuilding what has already been built.

Learn the cache workflow that matches your project or deployment model:

<HomeCards>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Module cache"
        details="Cache individual modules as binaries for projects using Tuist's generated projects. Requires Tuist project generation."
        linkText="Set up module cache"
        link="/guides/features/cache/module-cache"/>
    <HomeCard
        icon="<img src='/images/guides/features/xcode-icon.png' alt='Xcode' width='32' height='32' />"
        title="Xcode cache"
        details="Share Xcode compilation artifacts across environments. Works with any Xcode project, no project generation required."
        linkText="Set up Xcode cache"
        link="/guides/features/cache/xcode-cache"/>
    <HomeCard
        icon="<img src='/images/guides/features/gradle-icon.svg' alt='Gradle' width='32' height='32' />"
        title="Gradle cache"
        details="Share Gradle build cache artifacts remotely. Includes build insights for performance visibility."
        linkText="Set up Gradle cache"
        link="/guides/features/cache/gradle-cache"/>
    <HomeCard
        icon="<img src='/images/logo.webp' alt='Tuist' width='32' height='32' />"
        title="Self-hosting"
        details="Run cache nodes close to CI, offices, or regional compute and connect them to hosted or self-hosted Tuist."
        linkText="Deploy self-hosted cache"
        link="/guides/features/cache/self-hosting"/>
</HomeCards>

> [!TIP]
> **Fastest on Tuist Runners**
>
> On <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, the cache is colocated on the runner's private network and shared with the same cache your developer machines use, so CI jobs get warm hits out of the box, with no separate CI cache to warm up.


## Restrict uploads to CI {#restrict-uploads-to-ci}

Account administrators can make developers read-only while allowing CI to upload cache artifacts. Open the account's **Cache** settings in Tuist and set **Cache upload access** to **CI and account tokens only**. After that, members authenticated with login sessions can still download from the cache, but uploads require CI OIDC authentication or an account token with cache write scopes such as `project:cache:write` or `ci`.

Use this when CI is the trusted cache producer and local machines should only consume the cache. The setting affects cache upload authorization only.
