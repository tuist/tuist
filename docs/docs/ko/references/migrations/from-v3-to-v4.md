---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Tuist v3에서 v4로 전환 {#from-tuist-v3-to-v4}

Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0)의 출시와 함께, 장기적으로 프로젝트를
더 쉽게 사용하고 유지 관리할 수 있도록 프로젝트에 몇 가지 획기적인 변경 사항을 도입할 기회를 가졌습니다. 이 문서에서는 Tuist 3에서
Tuist 4로 업그레이드하기 위해 프로젝트에 적용해야 할 변경 사항을 간략하게 설명합니다.

### `tuistenv를 통한 삭제된 버전 관리` {#dropped-version-management-through-tuistenv}

Tuist 4 이전에는 설치 스크립트가 설치 시 `tuist` 로 이름이 변경되는 도구( `tuistenv`)를 설치했습니다. 이 도구는 여러
환경에서 결정성을 보장하는 Tuist 버전을 설치하고 활성화하는 작업을 처리했습니다. Tuist의 기능 표면을 줄이기 위해 같은 작업을
수행하지만 더 유연하고 여러 도구에서 사용할 수 있는 [Mise](https://mise.jdx.dev/)를 위해 `tuistenv` 를
삭제하기로 결정했습니다. ` tuistenv` 를 사용 중이었다면 `curl -Ls https://uninstall.tuist.io |
bash` 를 실행하여 현재 버전의 Tuist를 제거한 다음 원하는 설치 방법을 사용하여 설치해야 합니다. Mise는 여러 환경에서 결정론적으로
버전을 설치하고 활성화할 수 있으므로 사용을 강력히 권장합니다.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: 경고 CI 환경 및 XCODE 프로젝트에서 오류 발생
<!-- -->
Mise가 제공하는 결정론을 전반적으로 수용하기로 결정했다면 [CI
환경](https://mise.jdx.dev/continuous-integration.html) 및 [Xcode
프로젝트](https://mise.jdx.dev/ide-integration.html#xcode)에서 Mise를 사용하는 방법에 대한 설명서를
확인하는 것이 좋습니다.
<!-- -->
:::

::: info HOMEBREW SUPPORTED
<!-- -->
macOS에서 널리 사용되는 패키지 관리자인 Homebrew를 사용하여 Tuist를 설치할 수 있습니다. 홈브루를 사용하여 Tuist를 설치하는
방법은
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">설치 가이드</LocalizedLink>에서 확인할 수 있습니다.
<!-- -->
:::

### 삭제됨 `init` 생성자를 `ProjectDescription에서 삭제됨` models {#dropped-init-constructors-from-projectdescription-model}

API의 가독성과 표현력을 개선하기 위해 모든 `ProjectDescription` 모델에서 `init` 생성자를 제거하기로 결정했습니다. 이제
모든 모델은 모델의 인스턴스를 생성하는 데 사용할 수 있는 정적 생성자를 제공합니다. ` init` 생성자를 사용 중이었다면 정적 생성자를
사용하도록 프로젝트를 업데이트해야 합니다.

::: 팁 네이밍 규칙
<!-- -->
우리가 따르는 명명 규칙은 모델 이름을 정적 생성자의 이름으로 사용하는 것입니다. 예를 들어 `Target` 모델의 정적 생성자는
`Target.target` 입니다.
<!-- -->
:::

### `--no-cache` 이름을 `--no-binary-cache` {#renamed-nocache-to-nobinarycache}로 변경했습니다.

`--no-cache` 플래그가 모호하기 때문에, 바이너리 캐시를 가리킨다는 것을 명확히 하기 위해 `--no-binary-cache` 로
이름을 변경하기로 했습니다. ` --no-cache` 플래그를 사용했다면 프로젝트를 `--no-binary-cache` 플래그 대신 사용하도록
업데이트해야 합니다.

### `튜스트 가져오기` 를 `튜스트 설치` {#renamed-tuist-fetch-to-tuist-install}로 이름 변경

업계 관례에 따라 `tuist fetch` 명령의 이름을 `tuist install` 으로 변경했습니다. ` tuist fetch` 명령을 사용
중이었다면 대신 `tuist install` 명령을 사용하도록 프로젝트를 업데이트해야 합니다.

### [ `Package.swift` 를 종속성용 DSL로 채택](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Tuist 4 이전에는 `Dependencies.swift` 파일에서 종속성을 정의할 수 있었습니다. 이 독점적인 형식은 종속성을 자동으로
업데이트하는 [Dependabot](https://github.com/dependabot) 또는
[Renovatebot](https://github.com/renovatebot/renovate)과 같은 도구의 지원을 중단시켰습니다. 또한
사용자에게 불필요한 간접 경로를 도입했습니다. 따라서 저희는 `Package.swift` 를 Tuist에서 종속성을 정의하는 유일한 방법으로
채택하기로 결정했습니다. ` Dependencies.swift` 파일을 사용 중이었다면, `Tuist/Dependencies.swift` 의
내용을 루트의 `Package.swift` 로 옮기고 `#if TUIST` 지시문을 사용하여 통합을 구성해야 합니다. Swift 패키지 종속성
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">을 통합하는 방법에 대한 자세한 내용은 여기에서 확인할 수 있습니다.</LocalizedLink>

### `tuist-cache warm` 을 `tuist-cache` {#renamed-tuist-cache-warm-to-tuist-cache}로 이름 변경

간결성을 위해 `tuist cache warm` 명령의 이름을 `tuist cache` 로 변경하기로 결정했습니다. ` tuist cache
warm` 명령을 사용 중이었다면, 대신 `tuist cache` 명령을 사용하도록 프로젝트를 업데이트해야 합니다.


### 이름 변경 `tuist cache print-hashes` 에서 `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}로 변경되었습니다.

`tuist cache` 명령의 플래그임을 명확히 하기 위해 `tuist cache print-hashes` 명령의 이름을 `tuist
cache --print-hashes` 로 바꾸기로 결정했습니다. ` tuist cache print-hashes` 명령을 사용 중이었다면 대신
`tuist cache --print-hashes` 플래그를 사용하도록 프로젝트를 업데이트해야 합니다.

### 제거된 캐싱 프로필 {#removed-caching-profiles}

Tuist 4 이전에는 캐시에 대한 구성이 포함된 `Tuist/Config.swift` 에서 캐싱 프로필을 정의할 수 있었습니다. 이 기능을
제거하기로 결정한 이유는 프로젝트 생성 과정에서 프로젝트 생성에 사용된 프로필이 아닌 다른 프로필을 사용할 때 혼동을 일으킬 수 있기
때문입니다. 또한 사용자가 디버그 프로필을 사용하여 앱의 릴리스 버전을 빌드할 때 예기치 않은 결과가 발생할 수 있습니다. 대신 프로젝트를
생성할 때 사용할 구성을 지정하는 데 사용할 수 있는 `--configuration` 옵션을 도입했습니다. 캐싱 프로필을 사용 중이었다면 대신
`--configuration` 옵션을 사용하도록 프로젝트를 업데이트해야 합니다.

### 인수를 위해 `--skip-cache` 제거됨 {#removed-skipcache-in-favor-of-arguments}

인수를 사용하여 바이너리 캐시를 건너뛸 대상을 제어할 수 있도록 `generate` 명령에서 `--skip-cache` 플래그를 제거했습니다.
` --skip-cache` 플래그를 사용했다면 대신 인수를 사용하도록 프로젝트를 업데이트해야 합니다.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [삭제된 서명 기능](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

서명 작업은 이미 [Fastlane](https://fastlane.tools/)과 같은 커뮤니티 도구와 Xcode 자체에서 훨씬 더 잘
해결하고 있습니다. 저희는 서명이 Tuist의 확장 목표이며 프로젝트의 핵심 기능에 집중하는 것이 더 낫다고 생각했습니다. 저장소에 있는
인증서와 프로필을 암호화하고 생성 시 적절한 위치에 설치하는 것으로 구성된 Tuist 서명 기능을 사용 중이라면 프로젝트 생성 전에 실행되는
자체 스크립트에서 해당 로직을 복제하고 싶을 수 있습니다. 특히
  - 파일 시스템 또는 환경 변수에 저장된 키를 사용하여 인증서 및 프로필을 해독하고 키 체인에 인증서를 설치하고 디렉터리
    `~/Library/MobileDevice/Provisioning\ Profiles` 에 프로비저닝 프로필을 설치하는 스크립트입니다.
  - 기존 프로필 및 인증서를 가져와서 암호화할 수 있는 스크립트입니다.

::: 팁 서명 요구 사항
<!-- -->
서명하려면 키체인에 올바른 인증서가 있어야 하고 프로비저닝 프로필이 `~/Library/MobileDevice/Provisioning\ 프로필`
디렉터리에 있어야 합니다. ` security` 명령줄 도구를 사용하여 키체인에 인증서를 설치하고 `cp` 명령을 사용하여 프로비저닝 프로필을
올바른 디렉터리에 복사할 수 있습니다.
<!-- -->
:::

### `Dependencies.swift를 통해 삭제된 카르타고 통합` {#dropped-carthage-integration-via-dependenciesswift}

Tuist 4 이전에는 Carthage 종속성을 `Dependencies.swift` 파일에 정의할 수 있었고, 사용자는 `tuist
fetch` 를 실행하여 가져올 수 있었습니다. 특히 Swift 패키지 관리자가 종속성 관리의 기본 방법이 될 미래를 고려할 때, 이는
Tuist의 장기적인 목표라고 생각했습니다. Carthage 종속성을 사용하는 경우 `Carthage` 를 직접 사용하여 미리 컴파일된
프레임워크와 XCFramework를 Carthage의 표준 디렉토리로 가져온 다음 `TargetDependency.xcframework` 및
`TargetDependency.framework` 사례를 사용하여 태그셋에서 해당 바이너리를 참조해야 합니다.

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
일부 사용자는 카르타고 지원을 중단한 것으로 이해했습니다. 그렇지 않습니다. Tuist와 Carthage의 결과물 간의 계약은 시스템에 저장된
프레임워크와 XCFrameworks에 대한 것입니다. 변경된 유일한 사항은 종속성을 가져오는 책임이 있는 사람입니다. 이전에는 튜이스트가
카르타고를 통해 가져왔지만 이제는 카르타고가 가져옵니다.
<!-- -->
:::

### `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}를 삭제했습니다.

튜이스트 4 이전에는 `TargetDependency.packagePlugin` 케이스를 사용하여 패키지 플러그인 종속성을 정의할 수
있었습니다. Swift 패키지 관리자가 새로운 패키지 유형을 도입하는 것을 본 후, 우리는 더 유연하고 미래에 대비할 수 있는 방향으로 API를
반복하기로 결정했습니다. ` TargetDependency.packagePlugin` 을 사용했다면, 대신
`TargetDependency.package` 를 사용하고 인자로 사용하려는 패키지 유형을 전달해야 합니다.

### [사용 중단된 API](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

튜이스트 3에서 더 이상 사용되지 않는 것으로 표시된 API를 제거했습니다. 더 이상 사용되지 않는 API를 사용 중이었다면 프로젝트를
업데이트하여 새 API를 사용해야 합니다.
