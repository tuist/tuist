---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Swift Package와 함께 Tuist 사용 <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist는 프로젝트를 위한 DSL로 `Package.swift` 사용을 지원하며 패키지 타겟을 네이티브 Xcode 프로젝트와 타겟으로
변환합니다.

::: warning
<!-- -->
The aim of this feature is to provide an easy way for developers to assess the
impact of adopting Tuist in their Swift Packages. Therefore, we don't plan to
support the full range of Swift Package Manager features nor to bring every
Tuist's unique features like
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink> to the packages world.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist commands expect a certain
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">directory
structure</LocalizedLink> whose root is identified by a `Tuist` or a `.git`
directory.
<!-- -->
:::

## Using Tuist with a Swift Package {#using-tuist-with-a-swift-package}

We are going to use Tuist with the [TootSDK
Package](https://github.com/TootSDK/TootSDK) repository, which contains a Swift
Package. The first thing that we need to do is to clone the repository:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Once in the repository's directory, we need to install the Swift Package Manager
dependencies:

```bash
tuist install
```

Under the hood `tuist install` uses the Swift Package Manager to resolve and
pull the dependencies of the package. After the resolution completes, you can
then generate the project:

```bash
tuist generate
```

Voilà! You have a native Xcode project that you can open and start working on.
