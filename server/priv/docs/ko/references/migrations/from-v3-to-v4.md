---
{
  "title": "v3에서 v4로",
  "titleTemplate": ":title · 마이그레이션 · 참조 · Tuist",
  "description": "이 페이지에서는 Tuist CLI를 버전 3에서 버전 4로 마이그레이션하는 방법을 설명합니다."
}
---
# Tuist v3에서 v4로 {#from-tuist-v3-to-v4}

[Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0) 출시와 함께, 장기적으로 프로젝트의 사용과 유지 관리를 더 쉽게 만들 것이라고 믿었던 몇 가지 호환성 중단 변경 사항을 도입했습니다. 이 문서에서는 Tuist 3에서 Tuist 4로 업그레이드하기 위해 프로젝트에 적용해야 할 변경 사항을 설명합니다.

## `tuistenv`를 통한 버전 관리 제거 {#dropped-version-management-through-tuistenv}

Tuist 4 이전에는 설치 스크립트가 `tuistenv`라는 도구를 설치했으며, 이 도구는 설치 시점에 `tuist`로 이름이 변경되었습니다. 이 도구는 Tuist 버전을 설치하고 활성화하여 환경 간 결정론을 보장하는 역할을 했습니다. Tuist의 기능 범위를 줄이기 위해, 우리는 `tuistenv`를 제거하고 동일한 작업을 수행하지만 더 유연하며 다양한 도구에서 사용할 수 있는 [Mise](https://mise.jdx.dev/)를 채택하기로 결정했습니다. `tuistenv`를 사용하고 있었다면, `curl -Ls https://uninstall.tuist.io | bash`를 실행하여 현재 버전의 Tuist를 제거한 후 원하는 설치 방법을 사용하여 다시 설치해야 합니다. Mise는 환경 간에 버전을 결정론적으로 설치하고 활성화할 수 있으므로 사용을 강력히 권장합니다.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **CI 환경 및 Xcode 프로젝트에서의 Mise**
>
> Mise가 제공하는 전반적인 결정론을 수용하기로 결정했다면, [CI 환경](https://mise.jdx.dev/continuous-integration.html) 및 [Xcode 프로젝트](https://mise.jdx.dev/ide-integration.html#xcode)에서 Mise를 사용하는 방법에 대한 문서를 확인하는 것을 권장합니다.


> [!NOTE]
> **Homebrew 지원**
>
> macOS용 인기 패키지 관리자 Homebrew를 사용하여 Tuist를 계속 설치할 수 있습니다. Homebrew를 사용하여 Tuist를 설치하는 방법은 <.localized_link href="/guides/install-tuist#recommended-homebrew">설치 가이드</.localized_link>에서 확인할 수 있습니다.


## `ProjectDescription` 모델에서 `init` 생성자 제거 {#dropped-init-constructors-from-projectdescription-models}

API의 가독성과 표현력을 향상시키기 위해, 모든 `ProjectDescription` 모델에서 `init` 생성자를 제거하기로 결정했습니다. 이제 모든 모델은 모델 인스턴스를 생성하는 데 사용할 수 있는 정적 생성자를 제공합니다. `init` 생성자를 사용하고 있었다면, 대신 정적 생성자를 사용하도록 프로젝트를 업데이트해야 합니다.

> [!TIP]
> **명명 규칙**
>
> 우리가 따르는 명명 규칙은 모델 이름을 정적 생성자의 이름으로 사용하는 것입니다. 예를 들어, `Target` 모델의 정적 생성자는 `Target.target`입니다.


## `--no-cache`에서 `--no-binary-cache`로 이름 변경 {#renamed-nocache-to-nobinarycache}

`--no-cache` 플래그가 모호했기 때문에, 바이너리 캐시를 참조한다는 점을 명확히 하기 위해 `--no-binary-cache`로 이름을 변경하기로 결정했습니다. `--no-cache` 플래그를 사용하고 있었다면, 대신 `--no-binary-cache` 플래그를 사용하도록 프로젝트를 업데이트해야 합니다.

## `tuist fetch`에서 `tuist install`로 이름 변경 {#renamed-tuist-fetch-to-tuist-install}

업계 관례에 맞추기 위해 `tuist fetch` 명령어를 `tuist install`로 이름을 변경했습니다. `tuist fetch` 명령어를 사용하고 있었다면, 대신 `tuist install` 명령어를 사용하도록 프로젝트를 업데이트해야 합니다.

## [의존성 DSL로 `Package.swift` 채택](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 이전에는 `Dependencies.swift` 파일에서 의존성을 정의할 수 있었습니다. 이 독점 형식은 [Dependabot](https://github.com/dependabot)이나 [Renovatebot](https://github.com/renovatebot/renovate)과 같은 도구에서 의존성을 자동으로 업데이트하는 기능을 손상시켰습니다. 또한 사용자에게 불필요한 간접성을 초래했습니다. 따라서 Tuist에서 의존성을 정의하는 유일한 방법으로 `Package.swift`를 채택하기로 결정했습니다. `Dependencies.swift` 파일을 사용하고 있었다면, `Tuist/Dependencies.swift`의 내용을 루트의 `Package.swift`로 이동하고, `#if TUIST` 지시문을 사용하여 통합을 구성해야 합니다. Swift Package 의존성 통합 방법에 대한 자세한 내용은 <.localized_link href="/guides/features/projects/dependencies#swift-packages">여기</.localized_link>에서 확인할 수 있습니다.

## `tuist cache warm`에서 `tuist cache`로 이름 변경 {#renamed-tuist-cache-warm-to-tuist-cache}

간결함을 위해 `tuist cache warm` 명령어의 이름을 `tuist cache`로 변경하기로 결정했습니다. `tuist cache warm` 명령어를 사용하고 있었다면, 대신 `tuist cache` 명령어를 사용하도록 프로젝트를 업데이트해야 합니다.


## `tuist cache print-hashes`에서 `tuist cache --print-hashes`로 이름 변경 {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` 명령어를 `tuist cache --print-hashes`로 변경하여 `tuist cache` 명령어의 플래그임을 명확히 했습니다. `tuist cache print-hashes` 명령어를 사용 중이었다면, 프로젝트에서 대신 `tuist cache --print-hashes` 플래그를 사용하도록 업데이트해야 합니다.

## 캐싱 프로필 제거 {#removed-caching-profiles}

Tuist 4 이전에는 `Tuist/Config.swift`에서 캐시 구성을 포함하는 캐싱 프로필을 정의할 수 있었습니다. 프로젝트를 생성할 때 사용한 프로필과 다른 프로필을 생성 과정에서 사용하면 혼란을 초래할 수 있으므로 이 기능을 제거하기로 결정했습니다. 또한 사용자가 앱의 릴리스 버전을 빌드할 때 디버그 프로필을 사용하여 예상치 못한 결과를 초래할 수도 있었습니다. 이를 대신하여, 프로젝트 생성 시 사용할 구성을 지정할 수 있는 `--configuration` 옵션을 도입했습니다. 캐싱 프로필을 사용하고 있었다면, 대신 `--configuration` 옵션을 사용하도록 프로젝트를 업데이트해야 합니다.

## 인수 지원을 위해 `--skip-cache` 제거 {#removed-skipcache-in-favor-of-arguments}

바이너리 캐시를 건너뛸 타겟을 인수를 사용하여 제어하기 위해 `generate` 명령어에서 `--skip-cache` 플래그를 제거했습니다. `--skip-cache` 플래그를 사용하고 있었다면, 대신 인수를 사용하도록 프로젝트를 업데이트해야 합니다.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

## [서명 기능 제거](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

서명은 [Fastlane](https://fastlane.tools/)과 Xcode 자체와 같은 커뮤니티 도구에 의해 이미 해결되었으며, 이러한 도구들이 해당 작업을 훨씬 더 잘 수행합니다. 우리는 서명이 Tuist에게는 과도한 목표라고 느꼈으며, 프로젝트의 핵심 기능에 집중하는 것이 더 낫다고 판단했습니다. 저장소의 인증서와 프로필을 암호화하고 생성 시점에 올바른 위치에 설치하는 Tuist 서명 기능을 사용하고 있었다면, 프로젝트 생성 전에 실행되는 자체 스크립트에서 해당 로직을 복제하는 것을 고려할 수 있습니다. 구체적으로:
  - 파일 시스템 또는 환경 변수에 저장된 키를 사용하여 인증서와 프로필을 복호화하고, 인증서를 키체인에 설치하며, 프로비저닝 프로필을 `~/Library/MobileDevice/Provisioning\ Profiles` 디렉터리에 설치하는 스크립트.
  - 기존 프로필과 인증서를 가져와 암호화할 수 있는 스크립트.

> [!TIP]
> **서명 요구 사항**
>
> 서명하려면 키체인에 올바른 인증서가 있고 `~/Library/MobileDevice/Provisioning\ Profiles` 디렉터리에 프로비저닝 프로필이 있어야 합니다. `security` 명령줄 도구를 사용하여 키체인에 인증서를 설치하고, `cp` 명령을 사용하여 프로비저닝 프로필을 올바른 디렉터리에 복사할 수 있습니다.


## `Dependencies.swift`를 통한 Carthage 통합 제거 {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 이전에는 Carthage 종속성을 `Dependencies.swift` 파일에 정의할 수 있었고, 사용자는 `tuist fetch`를 실행하여 이를 가져올 수 있었습니다. 또한 Swift Package Manager가 종속성 관리를 위한 선호되는 방식이 될 미래를 고려할 때, 이는 Tuist에게는 과도한 목표라고 느꼈습니다. Carthage 종속성을 사용하고 있었다면, `Carthage`를 직접 사용하여 사전 컴파일된 프레임워크와 XCFramework를 Carthage의 표준 디렉터리로 가져온 후, `TargetDependency.xcframework` 및 `TargetDependency.framework` 케이스를 사용하여 타겟에서 해당 바이너리를 참조해야 합니다.

> [!NOTE]
> **Carthage는 여전히 지원됩니다**
>
> 일부 사용자는 우리가 Carthage 지원을 중단했다고 오해했습니다. 그렇지 않습니다. Tuist와 Carthage 출력 간의 계약은 시스템에 저장된 프레임워크와 XCFramework를 대상으로 합니다. 변경된 유일한 사항은 종속성을 가져오는 책임 주체입니다. 이전에는 Carthage를 통해 Tuist가 담당했지만, 이제는 Carthage가 담당합니다.


## `TargetDependency.packagePlugin` API 제거 {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 이전에는 `TargetDependency.packagePlugin` 케이스를 사용하여 패키지 플러그인 종속성을 정의할 수 있었습니다. Swift Package Manager가 새로운 패키지 유형을 도입하는 것을 보고, 우리는 더 유연하고 미래 지향적인 방향으로 API를 개선하기로 결정했습니다. `TargetDependency.packagePlugin`를 사용하고 있었다면, 대신 `TargetDependency.package`를 사용하고 사용하려는 패키지 유형을 인수로 전달해야 합니다.

## [사용 중단된 API 제거](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Tuist 3에서 사용 중단으로 표시된 API를 제거했습니다. 사용 중단된 API 중 하나라도 사용하고 있었다면, 새로운 API를 사용하도록 프로젝트를 업데이트해야 합니다.
