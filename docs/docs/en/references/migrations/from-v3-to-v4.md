---
title: From v3 to v4
description: This page documents how to migrate the Tuist CLI from the version 3 to version 4.
---

# From Tuist v3 to v4

With the release of [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0), we took the opportunity to introduce some breaking changes to the project, which we believed would make the project easier to use and maintain in the long run. This document outlines the changes you will need to make to your project to upgrade from Tuist 3 to Tuist 4.

### Dropped version management through `tuistenv`

Prior to Tuist 4, the installation script installed a tool, `tuistenv`, that would get renamed to `tuist` at installation time. The tool would take care of installing and activating versions of Tuist ensuring determinism across environments. With the aim of reducing the feature surface of Tuist, we decided to drop `tuistenv` in favor of [Mise](https://mise.jdx.dev/), a tool that does the same job but is more flexible and can be used across different tools. If you were using `tuistenv`, you'll have to uninstall the current version of Tuist by running `curl -Ls https://uninstall.tuist.io | bash` and then install it using the installation method of your choice. We strongly recommend the usage of Mise because it's able to install and activate versions deterministically across environments.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
:::

> [!IMPORTANT] MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
> If you decide to embrace the determinism that Mise brings across the board, we recommend checking out the documentation for how to use Mise in [CI environments](https://mise.jdx.dev/continuous-integration.html) and [Xcode projects](https://mise.jdx.dev/ide-integration.html#xcode).

> [!NOTE] HOMEBREW IS SUPPORTED
> Note that you can still install Tuist using Homebrew, which is a popular package manager for macOS. You can find the instructions on how to install Tuist using Homebrew in the [installation guide](/guides/quick-start/install-tuist#alternative-homebrew).

### Dropped `init` constructors from `ProjectDescription` models

With the aim of improving the readability and expressiveness of the APIs, we decided to remove the `init` constructors from all the `ProjectDescription` models. Every model now provides a static constructor that you can use to create instances of the models. If you were using the `init` constructors, you'll have to update your project to use the static constructors instead.

> [!TIP] NAMING CONVENTION
> The naming convention that we follow is to use the name of the model as the name of the static constructor. For example, the static constructor for the `Target` model is `Target.target`.

### Renamed `--no-cache` to `--no-binary-cache`

Because the `--no-cache` flag was ambiguous, we decided to rename it to `--no-binary-cache` to make it clear that it refers to the binary cache. If you were using the `--no-cache` flag, you'll have to update your project to use the `--no-binary-cache` flag instead.

### Renamed `tuist fetch` to `tuist install`

We renamed the `tuist fetch` command to `tuist install` to align with the industry convention. If you were using the `tuist fetch` command, you'll have to update your project to use the `tuist install` command instead.

### [Adopt `Package.swift` as the DSL for dependencies](https://github.com/tuist/tuist/pull/5862)

Before Tuist 4, you could define dependencies in a `Dependencies.swift` file. This proprietary format broke the support in tools like [Dependabot](https://github.com/dependabot) or [Renovatebot](https://github.com/renovatebot/renovate) to automatically update dependencies. Moreover, it introduced unnecessary indirections for users. Therefore, we decided to embrace `Package.swift` as the only way to define dependencies in Tuist. If you were using the `Dependencies.swift` file, you'll have to move the content from your `Tuist/Dependencies.swift` to a `Package.swift` at the root, and use the `#if TUIST` directive to configure the integration. You can read more about how to integrate Swift Package dependencies [here](/guides/develop/projects/dependencies#swift-packages)

### Renamed `tuist cache warm` to `tuist cache`

For brevity, we decided to rename the `tuist cache warm` command to `tuist cache`. If you were using the `tuist cache warm` command, you'll have to update your project to use the `tuist cache` command instead.


### Renamed `tuist cache print-hashes` to `tuist cache --print-hashes`

We decided to rename the `tuist cache print-hashes` command to `tuist cache --print-hashes` to make it clear that it's a flag of the `tuist cache` command. If you were using the `tuist cache print-hashes` command, you'll have to update your project to use the `tuist cache --print-hashes` flag instead.

### Removed caching profiles

Before Tuist 4, you could define caching profiles in `Tuist/Config.swift` which contained a configuration for the cache. We decided to remove this feature because it could lead to confusion when using it in the generation process with a profile other than the one that was used to generate the project. Moreover, it could lead to users using a debug profile to build a release version of the app, which could lead to unexpected results. In its place, we introduced the `--configuration` option, which you can use to specify the configuration you want to use when generating the project. If you were using caching profiles, you'll have to update your project to use the `--configuration` option instead.

### Removed `--skip-cache` in favor of arguments

We removed the flag `--skip-cache` from the `generate` command in favor of controlling for which targets the binary cache should be skipped by using the arguments. If you were using the `--skip-cache` flag, you'll have to update your project to use the arguments instead.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
:::

### [Dropped signing capabilities](https://github.com/tuist/tuist/pull/5716)

Signing is already solved by community tooling like [Fastlane](https://fastlane.tools/) and Xcode itself, which do a much better job at that. We felt that signing was an stretch goal for Tuist, and that it was better to focus on the core features of the project. If you were using Tuist signing capabilities, which consisted of encrypting the certificates and profiles in the repository and installing them in the right places at generation time, you might want to replicate that logic in your own scripts that run before project generation. In particular:
  - A script that decrypts the certificates and profiles using a key either stored in the file-system or in an environment variable, and installs certificates in the keychain, and the provisioning profiles in the directory `~/Library/MobileDevice/Provisioning\ Profiles`.
  - A script that can take an existing profiles and certificates and encrypt them.

> [!TIP] SIGNING REQUIREMENTS
> Signing requires the right certificates to be present in the keychain and the provisioning profiles to be present in the directory `~/Library/MobileDevice/Provisioning\ Profiles`. You can use the `security` command-line tool to install certificates in the keychain and the `cp` command to copy the provisioning profiles to the right directory.

### Dropped Carthage integration via `Dependencies.swift`

Before Tuist 4, Carthage dependencies could be defined in a `Dependencies.swift` file, which users could then fetch by running `tuist fetch`. We also felt that this was a stretch goal for Tuist, specially considering a future where Swift Package Manager would be the preferred way to manage dependencies. If you were using Carthage dependencies, you'll have to use `Carthage` directly to pull the pre-compiled frameworks and XCFrameworks into Carthage's standard directory, and then reference those binaries from your tagets using the `TargetDependency.xcframework` and `TargetDependency.framework` cases.

> [!NOTE] CARTHAGE IS STILL SUPPORTED
> Some users understood that we dropped Carthage support. We didn't. The contract between Tuist and Carthage's output is to system-stored frameworks and XCFrameworks. The only thing that changed is who is responsible for fetching the dependencies. It used to be Tuist through Carthage, now it's Carthage.

### Dropped the `TargetDependency.packagePlugin` API

Before Tuist 4, you could define a package plugin dependency using the `TargetDependency.packagePlugin` case. After seeing the Swift Package Manager introducing new package types, we decided to iterate on the API towards something that would be more flexible and future-proof. If you were using `TargetDependency.packagePlugin`, you'll have to use `TargetDependency.package` instead, and pass the type of package you want to use as an argument.

### [Dropped deprecated APIs](https://github.com/tuist/tuist/pull/5560)

We removed the APIs that were marked as deprecated in Tuist 3. If you were using any of the deprecated APIs, you'll have to update your project to use the new APIs.
