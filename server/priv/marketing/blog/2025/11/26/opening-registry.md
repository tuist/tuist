---
title: "Opening up the Tuist Registry"
category: "product"
tags: ["product"] 
excerpt: "Tuist Registry is now available to all – no authentication or account required."
author: fortmarek
og_image_path: /marketing/images/blog/2025/11/26/opening-registry/og.png
highlighted: false
---

We [released](/blog/2025/01/22/announcing-tuist-registry/) Tuist Registry earlier this year, helping teams to resolve their packages more reliably, efficiently, and **faster**.

Since launch, the registry has grown to serve almost 10,000 packages and more than 160,000 releases. Teams using the registry have seen disk space savings of up to 91% – from 6.6 GB down to 600 MB – and CI cache restore times dropping from 2 minutes to less than 20 seconds.

As teams started to integrate the registry, one point of friction has become clear: the registry required a Tuist account and authentication. Something developers are not used to when downloading open source packages from other registries in ecosystems like npm or CocoaPods. Having now understood better how teams use the registry, we have decided to remove the need for authentication and account creation. Now, anyone can use the registry without any additional steps. The same security measures remain in place – packages are sourced directly from their original repositories and the Swift CLI or Xcode verifies checksums on every download.

## Setting up the Tuist registry

Thanks to the registry being open now, the only thing you need to do is to run the following command in your project (install the CLI first by following [these instructions](https://docs.tuist.dev/en/guides/quick-start/install-tuist)):

```sh
tuist registry setup
```

This command will configure the Tuist Registry for your project – regardless of your setup. This command works with standard Xcode projects, generated Xcode projects, and Swift packages. For Swift packages, you can even use directly the `swift` CLI:

```sh
swift package-registry set https://tuist.dev/api/registry/swift
```

Either of these commands will create a configuration file, with its location depending on your setup. For Swift packages, this would be in `.swiftpm/configuration/registries.json`, for Xcode projects, it would be in `YourProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/registries.json`. Make sure to commit this configuration file, so all your colleagues and your CI have access to the registry.

When unauthenticated, you will be rate-limited to 10,000 requests per minute – more than enough for resolving hundreds of packages in a typical clean build. If you are running into limits, you can still authenticate with your Tuist account to increase your rate limit to 100,000 requests per minute:

```sh
tuist registry login
```

But for typical workflows, the current limits should be more than enough. If not, please [reach out to us](mailto:contact@tuist.dev), we'd love to know, so we can adjust the rate limits to accommodate typical workflows.

If you're already using the registry, we recommend re-running `tuist registry setup` to update your configuration file with the new endpoint that allows unauthenticated access.

## What's next?

We believe that to provide the best experience, we need to use our own tools daily. Opening the registry has allowed us to integrate the registry in our [monorepository](https://github.com/tuist/tuist) where all of our Swift packages are installed via the Tuist Registry, which we've done as part of [this PR](https://github.com/tuist/tuist/pull/8712).

Now that the registry is open, our next step will be to allow authenticated organizations to publish their own packages to a private registry, so they can move _all_ of their packages away from the source control resolution and improve the resolution of both open source and internal packages.

And as always, we're keen to hear your feedback – do you have any suggestions or ideas for how we can improve the registry? We'd love to [hear from you](mailto:contact@tuist.dev)!
