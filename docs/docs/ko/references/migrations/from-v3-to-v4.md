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

> [!TIP] 명명 규칙
> 우리가 따르는 명명 규칙은 모델의 이름을 정적 생성자의 이름으로 사용하는 것입니다. 예를 들어, `Target` 모델의 정적 생성자는 `Target.target`입니다.

### `--no-cache` 가 `--no-binary-cache`로 이름이 변경되었습니다. {#renamed-nocache-to-nobinarycache}

왜냐하면 `--no-cache` 플래그가 모호했기 때문에, 이를 `--no-binary-cache`로 변경하여 바이너리 캐시를 의미한다는 점을 명확히 했습니다. 만약 `--no-cache` 플래그를 사용하고 있었다면, 이제 `--no-binary-cache` 플래그를 사용하도록 프로젝트를 업데이트해야 합니다.

### `tuist fetch`가 `tuist install`로 이름이 변경되었습니다. {#renamed-tuist-fetch-to-tuist-install}

업계 표준에 맞추기 위해 `tuist fetch` 명령어를 `tuist install`로 변경했습니다. `tuist fetch` 명령어를 사용하고 있었다면 `tuist install` 명령어를 사용하도록 프로젝트를 업데이트해야 합니다.

### [종속성을 위한 DSL로 'Package.swift'를 채택합니다](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 이전에는 `Dependencies.swift` 파일에서 종속성을 정의할 수 있었습니다. 이 독자적인 형식은 [Dependabot](https://github.com/dependabot)이나 [Renovatebot](https://github.com/renovatebot/renovate)과 같은 도구에서 종속성을 자동으로 업데이트하는 기능을 지원하지 못하게 했습니다. 또한 사용자에게 불필요한 간접 경로를 도입하게 했습니다. 따라서 Tuist에서 종속성을 정의하는 유일한 방법으로 `Package.swift`를 채택하기로 결정했습니다. `Dependencies.swift` 파일을 사용하고 있었다면, `Tuist/Dependencies.swift`의 내용을 루트 디렉토리의 `Package.swift`로 이동하고, 통합을 설정하기 위해 `#if TUIST` 지시문을 사용해야 합니다. Swift Package 종속성을 통합하는 방법에 대한 자세한 내용은 <LocalizedLink href="/guides/develop/projects/dependencies#swift-packages">여기</LocalizedLink>에서 확인할 수 있습니다.

### `tuist cache warm`이 `tuist cache`로 이름이 변경되었습니다. {#renamed-tuist-cache-warm-to-tuist-cache}

간결함을 위해 `tuist cache warm` 명령어를 `tuist cache`로 이름 변경하기로 결정했습니다. `tuist cache warm` 명령어를 사용하고 있었다면, 이제 `tuist cache` 명령어를 사용하도록 프로젝트를 업데이트해야 합니다.

### `tuist cache print-hashes`가 `tuist cache --print-hashes`로 이름이 변경되었습니다. {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` 명령어를 `tuist cache --print-hashes`로 변경하여, 이것이 `tuist cache` 명령어의 플래그임을 명확히 했습니다. `tuist cache print-hashes` 명령어를 사용하고 있었다면, 이제 `tuist cache --print-hashes` 플래그를 사용하도록 프로젝트를 업데이트해야 합니다.

### caching profiles가 제거되었습니다. {#removed-caching-profiles}

Tuist 4 이전에는 Tuist/Config.swift에 캐시 구성을 포함한 caching profiles를 정의할 수 있었습니다. 이 기능은 다른 프로필을 사용하여 프로젝트를 생성할 때 혼란을 초래할 수 있기 때문에 제거하기로 결정했습니다. 게다가, 이 기능은 사용자가 디버그 프로필을 사용하여 앱의 릴리스 버전을 빌드하는 상황을 초래할 수 있어, 예상치 못한 결과를 발생시킬 수 있습니다. 그 대신, 프로젝트를 생성할 때 사용할 구성을 지정할 수 있는 `--configuration` 옵션을 도입했습니다. caching profiles을 사용하고 있었다면, 이제 `--configuration` 옵션을 대신 사용하도록 프로젝트를 업데이트해야 합니다.

### `--skip-cache` 옵션은 더 이상 사용되지 않으며, 대신 arguments를 사용하도록 변경되었습니다. {#removed-skipcache-in-favor-of-arguments}

`generate` 명령에서 `--skip-cache` 플래그를 제거하고, 대신 arguments를 사용하여 바이너리 캐시를 건너뛰어야 할 대상을 제어하도록 변경되었습니다. `--skip-cache` 플래그를 사용하고 있었다면, 이제 arguments를 사용하도록 프로젝트를 업데이트해야 합니다.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```

:::

### [Dropped signing capabilities](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

서명 기능은 이미 [Fastlane](https://fastlane.tools/)과 Xcode 자체와 같은 커뮤니티 도구들에 의해 해결되었으며, 이들이 훨씬 더 잘 처리합니다. 우리는 서명 기능이 Tuist의 추가 목표라고 판단했으며, 프로젝트의 핵심 기능에 집중하는 것이 더 좋다고 생각했습니다. If you were using Tuist signing capabilities, which consisted of encrypting the certificates and profiles in the repository and installing them in the right places at generation time, you might want to replicate that logic in your own scripts that run before project generation. In particular:

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
