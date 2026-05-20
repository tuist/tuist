---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, and Gradle cache."
}
---
# Cache {#cache}

Build artifacts are not shared across environments, forcing you to rebuild the same code over and over. Tuist's caching feature shares artifacts remotely so your team and CI get faster builds without rebuilding what has already been built.

Pick the caching solution that matches your build system:

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
</HomeCards>
