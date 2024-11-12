---
title: 버전 3에서 버전 4로
titleTemplate: :title · Migrations · References · Tuist
description: 이 페이지에서는 Tuist CLI를 버전 3에서 버전 4로 마이그레이션하는 방법을 설명합니다.
---

# 버전 3에서 버전 4로 {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0)의 출시와 함께, 프로젝트를 장기적으로 더 쉽게 사용하고 유지보수할 수 있도록 몇 가지 획기적인 변경 사항을 도입했습니다. 이 문서는 Tuist 3에서 Tuist 4로 업그레이드하기 위해 프로젝트에 필요한 변경 사항을 설명합니다.

### `tuistenv`를 통한 버전 관리가 삭제되었습니다. {#dropped-version-management-through-tuistenv}

Tuist 4 이전에는 설치 스크립트가 `tuistenv`라는 도구를 설치했으며, 설치 시 이 도구는 `tuist`로 이름이 변경되었습니다. 이 도구는 Tuist의 버전을 설치하고 활성화하여 환경 간의 일관성을 보장하는 역할을 했습니다. Tuist의 기능 범위를 줄이기 위해, 동일한 작업을 수행하지만 더 유연하고 다양한 도구에서 사용할 수 있는 [Mise](https://mise.jdx.dev/)로 대체하면서 `tuistenv` 지원을 중단하기로 결정했습니다. `tuistenv`를 사용하고 있었다면, 현재 버전의 Tuist를 `curl -Ls https://uninstall.tuist.io | bash` 명령어로 제거한 후, 원하는 설치 방법을 사용하여 다시 설치해야 합니다. 환경 간에 일관된 방식으로 버전을 설치하고 활성화할 수 있기 때문에 Mise 사용을 강력히 권장합니다.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```

:::

> [!IMPORTANT] CI 환경과 Xcode 프로젝트에서 Mise 사용
> Mise가 제공하는 일관성을 활용하기로 했다면, [CI 환경](https://mise.jdx.dev/continuous-integration.html)과 [Xcode 프로젝트](https://mise.jdx.dev/ide-integration.html#xcode)에서 Mise를 사용하는 방법에 대한 문서를 확인해 보시기를 권장합니다.

> [!NOTE] Homebrew 지원됨
> macOS용 인기 패키지 관리자인 Homebrew를 통해 Tuist를 설치할 수 있다는 점을 참고하세요. Homebrew를 사용하여 Tuist를 설치하는 방법은 <LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">설치 가이드</LocalizedLink>에서 확인할 수 있습니다.

### `ProjectDescription` 모델에서 `init` 생성자가 제거되었습니다. {#dropped-init-constructors-from-projectdescription-models}

API의 가독성과 표현력을 높이기 위해, 모든 `ProjectDescription` 모델에서 `init` 생성자를 제거하기로 결정했습니다. 이제 각 모델은 인스턴스를 생성할 수 있는 정적 생성자를 제공합니다. 만약 `init` 생성자를 사용하고 있었다면, 이제 정적 생성자를 사용하도록 프로젝트를 업데이트해야 합니다.

> [!TIP] NAMING CONVENTION
> The naming convention that we follow is to use the name of the model as the name of the static constructor. For example, the static constructor for the `Target` model is `Target.target`.

### Renamed `--no-cache` to `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

Because the `--no-cache` flag was ambiguous, we decided to rename it to `--no-binary-cache` to make it clear that it refers to the binary cache. If you were using the `--no-cache` flag, you'll have to update your project to use the `--no-binary-cache` flag instead.

### Renamed `tuist fetch` to `tuist install` {#renamed-tuist-fetch-to-tuist-install}

We renamed the `tuist fetch` command to `tuist install` to align with the industry convention. If you were using the `tuist fetch` command, you'll have to update your project to use the `tuist install` command instead.

### [Adopt `Package.swift` as the DSL for dependencies](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Before Tuist 4, you could define dependencies in a `Dependencies.swift` file. This proprietary format broke the support in tools like [Dependabot](https://github.com/dependabot) or [Renovatebot](https://github.com/renovatebot/renovate) to automatically update dependencies. Moreover, it introduced unnecessary indirections for users. Therefore, we decided to embrace `Package.swift` as the only way to define dependencies in Tuist. If you were using the `Dependencies.swift` file, you'll have to move the content from your `Tuist/Dependencies.swift` to a `Package.swift` at the root, and use the `#if TUIST` directive to configure the integration. You can read more about how to integrate Swift Package dependencies <LocalizedLink href="/guides/develop/projects/dependencies#swift-packages">here</LocalizedLink>

### Renamed `tuist cache warm` to `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

For brevity, we decided to rename the `tuist cache warm` command to `tuist cache`. If you were using the `tuist cache warm` command, you'll have to update your project to use the `tuist cache` command instead.

### Renamed `tuist cache print-hashes` to `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

We decided to rename the `tuist cache print-hashes` command to `tuist cache --print-hashes` to make it clear that it's a flag of the `tuist cache` command. If you were using the `tuist cache print-hashes` command, you'll have to update your project to use the `tuist cache --print-hashes` flag instead.

### Removed caching profiles {#removed-caching-profiles}

Before Tuist 4, you could define caching profiles in `Tuist/Config.swift` which contained a configuration for the cache. We decided to remove this feature because it could lead to confusion when using it in the generation process with a profile other than the one that was used to generate the project. Moreover, it could lead to users using a debug profile to build a release version of the app, which could lead to unexpected results. In its place, we introduced the `--configuration` option, which you can use to specify the configuration you want to use when generating the project. If you were using caching profiles, you'll have to update your project to use the `--configuration` option instead.

### Removed `--skip-cache` in favor of arguments {#removed-skipcache-in-favor-of-arguments}

We removed the flag `--skip-cache` from the `generate` command in favor of controlling for which targets the binary cache should be skipped by using the arguments. If you were using the `--skip-cache` flag, you'll have to update your project to use the arguments instead.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```

:::

### [Dropped signing capabilities](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

Signing is already solved by community tooling like [Fastlane](https://fastlane.tools/) and Xcode itself, which do a much better job at that. We felt that signing was an stretch goal for Tuist, and that it was better to focus on the core features of the project. If you were using Tuist signing capabilities, which consisted of encrypting the certificates and profiles in the repository and installing them in the right places at generation time, you might want to replicate that logic in your own scripts that run before project generation. In particular:

- A script that decrypts the certificates and profiles using a key either stored in the file-system or in an environment variable, and installs certificates in the keychain, and the provisioning profiles in the directory `~/Library/MobileDevice/Provisioning\ Profiles`.
- A script that can take an existing profiles and certificates and encrypt them.

> [!TIP] SIGNING REQUIREMENTS
> Signing requires the right certificates to be present in the keychain and the provisioning profiles to be present in the directory `~/Library/MobileDevice/Provisioning\ Profiles`. You can use the `security` command-line tool to install certificates in the keychain and the `cp` command to copy the provisioning profiles to the right directory.

### Dropped Carthage integration via `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

Before Tuist 4, Carthage dependencies could be defined in a `Dependencies.swift` file, which users could then fetch by running `tuist fetch`. We also felt that this was a stretch goal for Tuist, specially considering a future where Swift Package Manager would be the preferred way to manage dependencies. If you were using Carthage dependencies, you'll have to use `Carthage` directly to pull the pre-compiled frameworks and XCFrameworks into Carthage's standard directory, and then reference those binaries from your tagets using the `TargetDependency.xcframework` and `TargetDependency.framework` cases.

> [!NOTE] CARTHAGE IS STILL SUPPORTED
> Some users understood that we dropped Carthage support. We didn't. The contract between Tuist and Carthage's output is to system-stored frameworks and XCFrameworks. The only thing that changed is who is responsible for fetching the dependencies. It used to be Tuist through Carthage, now it's Carthage.

### Dropped the `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

Before Tuist 4, you could define a package plugin dependency using the `TargetDependency.packagePlugin` case. After seeing the Swift Package Manager introducing new package types, we decided to iterate on the API towards something that would be more flexible and future-proof. If you were using `TargetDependency.packagePlugin`, you'll have to use `TargetDependency.package` instead, and pass the type of package you want to use as an argument.

### [Dropped deprecated APIs](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

We removed the APIs that were marked as deprecated in Tuist 3. If you were using any of the deprecated APIs, you'll have to update your project to use the new APIs.
