---
title: "Announcing Tuist Registry."
category: "product"
tags: ["Announcement", "Previews"]
excerpt: "We're thrilled to announce the launch of the Tuist Registry – a new feature that optimizes the resolution of Swift packages in your projects."
og_image_path: /marketing/images/blog/2025/01/22/announcing-tuist-registry/og.jpg
author: fortmarek
highlighted: true
---

![Tuist Registry illustration](/marketing/images/blog/2025/01/22/announcing-tuist-registry/registry-illustration.png)

Tuist Registry is a new feature that optimizes the resolution of Swift packages in your projects. Gone are the days when you had to install the full git history of any package you wanted to use – instead, Tuist Registry, built on top of the [Swift Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) standard, allows you to download only source archives of the package versions you need – saving both time and disk space, locally or on the CI, and making the resolution more deterministic and reliable. The Tuist Registry mirrors the [Swift Package Index](https://swiftpackageindex.com/) and is available for any open source Swift package in the community – served from a global storage for low latency.

If you prefer to watch a video to learn more about the Tuist Registry, you can watch the following Tuist Registry walkthrough video:
<iframe title="Tuist Registry Walkthrough" width="560" height="315" src="https://videos.tuist.dev/videos/embed/2bd2deb4-1897-4c5b-9de6-37c8acd16fb0" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

## Swift Package Registry

The Swift Package Manager has become the de-facto standard for managing dependencies in Swift projects. However, unlike some other package managers like [Cocoapods](https://cocoapods.org/) or [npm](https://www.npmjs.com/), SwiftPM does not have a central registry for packages. Instead, it relies on the package's source repository to host the package. While it does mean there's no need for a central authority for publishing and downloading packages, it also means there are some inefficiencies in how packages are resolved.

When you add a package to your project, SwiftPM needs to do a deep clone of _any_ Swift package you want to use. This can take a long time to download and consume a lot of disk space, especially for projects with large git history. For example, a well-known app that moved to the registry reported that the disk space consumed by the registry resolution was **91 % smaller** – going from 6.6 GB to 600 MB. The time to restore and save the cached dependencies on the CI, something done on every run, dropped accordingly from 2 minutes to just 20 s. 

Apart from the performance and efficiency improvements, depending on the Git history and tags can lead to non-deterministic builds and potential security issues since the Git history is not immutable.

Luckily, SwiftPM now has the capability to centralize the resolution of packages thanks to [the Package Registry Service evolution proposal SE-0292](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md), which aims at addressing the following challenges:

- **Reproducibility**: A version tag in the Git repository for a dependency can be reassigned to another commit at any time. This can cause a project to produce different build results depending on when it was built.
- **Availability**: The Git repository for a dependency can be moved or deleted, which can cause subsequent builds to fail.
- **Efficiency**: Cloning the Git repository for a dependency downloads all versions of a package when only one is used at a time.
- **Speed**: Cloning a Git repository for a dependency can be slow if it has a large history. Also, cloning a Git repository is expensive for both the server and client, and may be significantly slower than downloading the same content using HTTP through a content delivery network (CDN).

While the registry has been used by some to allow organizations to distribute private packages through their internal registry, the usage to improve efficiency and developers' productivity remained unexplored until today.

## Security

We take security very seriously at Tuist and the Tuist Registry is no exception. For a centralized registry, security is paramount. There are a couple of security measures that we have implemented to ensure the security of the packages in the registry:
- We only sync packages available in the [Swift Package Index](https://swiftpackageindex.com/).
- Sources are always pulled directly from the original package repository.
- The `swift` CLI always verifies the downloaded package source archive checksums against the checksums provided by the registry.

Additionally, we're in the process of obtaining the [SOC 2](https://secureframe.com/hub/soc-2/what-is-soc-2) certification to have a formal verification that our security practices are up to the highest standards. If you have questions around the security, shoot us an email at [contact@tuist.dev](mailto:contact@tuist.dev) and we'll be happy to answer them.

## Get started

The Tuist Registry implements the Swift Package Registry standard and is thus compatible with any SwiftPM setup that you might have – regardless whether you use Tuist Generated Projects or not.

To start using the registry, first [install Tuist](https://docs.tuist.dev/en/guides/quick-start/install-tuist#install-tuist). Then you need to have a [Tuist Project](https://docs.tuist.dev/en/server/introduction/accounts-and-projects). You can create one by running:

```bash
tuist auth login
# Obtain your account handle by running `tuist auth whoami`
tuist project create {your-account-handle}/{your-project-handle}
```

Additionally, you need to create a `Tuist.swift` file in the root of your project with the following content:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{your-account-handle}/{your-project-handle}"
)
```

Afterwards, you need to run the following commands to enable the Tuist Registry:

```bash
# Generates a registry configuration in your project
tuist registry setup
# Creates and stores credentials to access the registry
tuist registry login
```

...and you're done!

`tuist registry setup` automatically configures your project to use the Tuist Registry. When adding a package through the Xcode UI, you will now see the Tuist Registry as an option to resolve the package from (note the `tuist.dev` registry in the top right corner):

![Adding package with the Tuist Registry](/marketing/images/blog/2025/01/22/announcing-tuist-registry/registry-add-package.png)

To learn more about the Tuist Registry, head over to our [documentation](https://docs.tuist.dev/en/guides/develop/registry).

## Building a low-latency registry for open source packages

We implemented an API that complies with the specification to serve releases of all the packages listed at [Swift Package Index](https://swiftpackageindex.com/), the default directory of community packages. Unlike decentralized resolution, developers get just the source code of every package version and do so from a global storage network that serves them with as minimum latency as possible. At the time of writing, we serve around 8.4K packages and 130k releases – and that number is growing every day.

When implementing the Tuist Registry, there were a couple of bugs that we found in the SwiftPM registry implementation. To fix these for anyone using the Swift Package Registry, we submitted the following PRs:
- [Fix resolve failing when package from registry is referenced by name](https://github.com/swiftlang/swift-package-manager/pull/8166)
- [Fix registry resolution of major alternate package manifests](https://github.com/swiftlang/swift-package-manager/pull/8188)
- [Fix registry package swizzling when package name casing differs](https://github.com/swiftlang/swift-package-manager/pull/8194)

All of these PRs have been merged and should be available as part of the next Swift 6.1 release. However, until then, we have fixed these issues in the `Package.swift` manifests when uploading a package to our registry. We plan to remove these workarounds when Swift 6.1 is used by the majority of the community.

Additionally, we also posted a [PR](https://github.com/swiftlang/swift-package-manager/pull/8220) to parallelize retrieving packages – both when using source control and registry resolution. Once this PR is merged and released, the SwiftPM clean resolution should be up to _2x faster_. For _anyone_. We love to give back to the community and make the whole Swift ecosystem better for everyone.

## Love letter to the community

The Tuist Registry is our love letter to the Swift community. It wouldn't have been possible without all the amazing work that the community has done. We're excited to see how the community will embrace the registry and how it will help to make Swift projects more efficient and reliable.

And always, feedback is welcome – if you have any suggestions or ideas on how to improve the registry, please let us know on our [community forum](https://community.tuist.dev/) or on [our GitHub](https://github.com/tuist/tuist). We're looking forward to hearing from you!
