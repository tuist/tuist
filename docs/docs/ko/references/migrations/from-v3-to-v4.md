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

Tuist 4 이전에는 `Dependencies.swift` 파일에서 종속성을 정의할 수 있었습니다. 이 독자적인 형식은 [Dependabot](https://github.com/dependabot)이나 [Renovatebot](https://github.com/renovatebot/renovate)과 같은 도구에서 종속성을 자동으로 업데이트하는 기능을 지원하지 못하게 했습니다. 또한 사용자에게 불필요한 간접 경로를 도입하게 했습니다. 따라서 Tuist에서 종속성을 정의하는 유일한 방법으로 `Package.swift`를 채택하기로 결정했습니다. `Dependencies.swift` 파일을 사용하고 있었다면, `Tuist/Dependencies.swift`의 내용을 루트 디렉토리의 `Package.swift`로 이동하고, 통합을 설정하기 위해 `#if TUIST` 지시문을 사용해야 합니다. Swift Package 종속성을 통합하는 방법에 대한 자세한 내용은 <LocalizedLink href="/guides/features/projects/dependencies#swift-packages">여기</LocalizedLink>에서 확인할 수 있습니다.

### `tuist cache warm`이 `tuist cache`로 이름이 변경되었습니다. {#renamed-tuist-cache-warm-to-tuist-cache}

간결함을 위해 `tuist cache warm` 명령어를 `tuist cache`로 이름 변경하기로 결정했습니다. `tuist cache warm` 명령어를 사용하고 있었다면, 이제 `tuist cache` 명령어를 사용하도록 프로젝트를 업데이트해야 합니다.

### `tuist cache print-hashes`가 `tuist cache --print-hashes`로 이름이 변경되었습니다. {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

`tuist cache print-hashes` 명령어를 `tuist cache --print-hashes`로 변경하여, 이것이 `tuist cache` 명령어의 플래그임을 명확히 했습니다. `tuist cache print-hashes` 명령어를 사용하고 있었다면, 이제 `tuist cache --print-hashes` 플래그를 사용하도록 프로젝트를 업데이트해야 합니다.

### caching profiles가 제거되었습니다. {#removed-caching-profiles}

Tuist 4 이전에는 Tuist/Config.swift에 캐시 구성을 포함한 caching profiles를 정의할 수 있었습니다. 이 기능은 다른 프로필을 사용하여 프로젝트를 생성할 때 혼란을 초래할 수 있기 때문에 제거하기로 결정했습니다. 게다가, 이 기능은 사용자가 디버그 프로필을 사용하여 앱의 릴리스 버전을 빌드하는 상황을 초래할 수 있어, 예상치 못한 결과를 발생시킬 수 있습니다. 그 대신, 프로젝트를 생성할 때 사용할 구성을 지정할 수 있는 `--configuration` 옵션을 도입했습니다. caching profiles을 사용하고 있었다면, 이제 `--configuration` 옵션을 대신 사용하도록 프로젝트를 업데이트해야 합니다.

### {#removed-skipcache-in-favor-of-arguments}

`generate` 명령에서 `--skip-cache` 플래그를 제거하고, 대신 arguments를 사용하여 바이너리 캐시를 건너뛰어야 할 대상을 제어하도록 변경되었습니다. `--skip-cache` 플래그를 사용하고 있었다면, 이제 arguments를 사용하도록 프로젝트를 업데이트해야 합니다.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```

:::

### [중단된 서명 기능](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

서명 기능은 이미 [Fastlane](https://fastlane.tools/)과 Xcode 자체와 같은 커뮤니티 도구들에 의해 해결되었으며, 이들이 훨씬 더 잘 처리합니다. 우리는 서명 기능이 Tuist의 추가 목표라고 판단했으며, 프로젝트의 핵심 기능에 집중하는 것이 더 좋다고 생각했습니다. 만약 Tuist의 서명 기능을 사용하고 있었다면, 이는 저장소에서 인증서와 프로필을 암호화하여 프로젝트 생성 시 올바른 위치에 설치하는 방식이었습니다. 이제 이 기능이 제거되었기 때문에, 프로젝트 생성 전에 실행되는 스크립트에서 해당 로직을 직접 구현해야 할 수 있습니다. 특히:

- 파일 시스템이나 환경 변수에 저장된 키를 사용하여 인증서와 프로필을 복호화하고, 인증서를 키체인에 설치하며, 프로비저닝 프로필은 `~/Library/MobileDevice/Provisioning\ Profiles` 디렉토리에 설치하는 스크립트를 작성해야 할 수 있습니다.
- 기존의 프로필과 인증서를 받아서 암호화하는 스크립트를 작성해야 할 수 있습니다.

> [!TIP] 서명 요구 사항
> 서명은 키체인에 올바른 인증서가 있어야 하고, 프로비저닝 프로필은 `~/Library/MobileDevice/Provisioning\ Profiles` 디렉토리에 있어야 합니다. `security` 명령어를 사용하여 인증서를 키체인에 설치하고, `cp` 명령어를 사용하여 프로비저닝 프로필을 올바른 디렉토리에 복사할 수 있습니다.

### `Dependencies.swift`를 통한 Carthage 통합이 제거되었습니다. {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 이전에는 Carthage 의존성을 `Dependencies.swift` 파일에 정의할 수 있었으며, 사용자는 `tuist fetch` 명령을 실행하여 이를 가져올 수 있었습니다. 우리는 또한 이것이 Tuist의 추가 목표라고 생각했으며, 특히 앞으로 Swift Package Manager가 의존성을 관리하는 기본적인 방법이 될 것이라는 점을 고려했습니다. 만약 Carthage 의존성을 사용하고 있었다면, 이제 `Carthage`를 직접 사용하여 미리 컴파일된 프레임워크와 XCFramework를 Carthage의 표준 디렉토리로 가져온 후, `TargetDependency.xcframework`와 `TargetDependency.framework` 케이스를 사용하여 해당 바이너리를 타겟에서 참조해야 합니다.

> 일부 사용자들은 우리가 Carthage 지원을 중단했다고 이해했습니다. 우리는 그렇지 않았습니다. Tuist와 Carthage의 출력 간의 계약은 시스템에 저장된 프레임워크와 XCFramework에 관한 것입니다. 변경된 유일한 점은 의존성을 가져오는 책임이 누구에게 있는지입니다. 이전에는 Tuist가 Carthage를 통해 의존성을 가져왔지만, 이제는 Carthage가 직접 의존성을 가져옵니다.

### `TargetDependency.packagePlugin` API가 제거되었습니다. {#dropped-the-targetdependencypackageplugin-api}

Tuist 4 이전에는 `TargetDependency.packagePlugin` 케이스를 사용하여 패키지 플러그인 의존성을 정의할 수 있었습니다. Swift Package Manager가 새로운 패키지 유형을 도입하는 것을 본 후, 우리는 API를 더 유연하고 미래 지향적으로 발전시키기로 결정했습니다. 만약 `TargetDependency.packagePlugin`을 사용하고 있었다면, 대신 `TargetDependency.package`를 사용해야 하며, 사용하려는 패키지 유형을 인수로 전달해야 합니다.

### [더 이상 사용되지 않는 API가 제거되었습니다.](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

우리는 Tuist 3에서 더 이상 사용되지 않는 것으로 표시된 API들을 제거했습니다. 만약 더 이상 사용되지 않는 API를 사용하고 있었다면, 새로운 API를 사용하도록 프로젝트를 업데이트해야 합니다.
