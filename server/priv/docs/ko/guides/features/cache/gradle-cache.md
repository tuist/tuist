---
{
  "title": "Gradle 빌드 캐시: CI와 팀을 위한 원격 캐시 설정",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist 플러그인과 org.gradle.caching=true를 사용하여 Gradle 원격 빌드 캐시를 설정하면, CI와 개발자가 작업을 다시 실행하는 대신 작업 결과를 재사용할 수 있습니다."
}
---
# Gradle 빌드 캐시 {#gradle-cache}

Tuist는 Gradle 원격 빌드 캐시입니다. Tuist의 Gradle 플러그인은 [Gradle 내장 빌드 캐시](https://docs.gradle.org/current/userguide/build_cache.html)를 공유 서버에 연결하여, CI와 각 개발자 머신이 태스크를 다시 실행하는 대신 태스크 결과를 재사용할 수 있게 합니다. 태스크 결과가 이미 캐시되어 있으면 Gradle은 실행을 건너뛰고 Tuist에서 결과를 가져오므로, 팀과 CI 환경 전반에서 빌드 시간을 절약할 수 있습니다. Tuist가 Gradle 빌드에 추가하는 다른 기능(빌드 인사이트 및 테스트 인사이트 등)에 대해서는 [Gradle with Tuist](https://tuist.dev/build-systems/gradle)를 참고하세요. Develocity와 비교 중이라면 [Develocity vs Tuist](https://tuist.dev/compare/develocity)를 확인하세요. Gradle의 로컬 및 원격 빌드 캐시가 최신 상태 확인(up-to-date checks) 및 구성 캐시(configuration cache)와 어떻게 다른지 알아보려면 <.localized_link href="/references/concepts/build-cache#gradle">What is a build cache?</.localized_link>를 참조하세요. 느린 빌드의 어느 부분을 캐시가 제거하는지, 그리고 프로젝트에서 먼저 수정해야 할 항목이 무엇인지 확인하려면 [Slow builds](https://tuist.dev/solutions/slow-builds)를 참고하세요.

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 플러그인</.localized_link>을 설치한 후에는 `gradle.properties` 파일에서 Gradle의 빌드 캐시를 활성화해야 합니다:

```properties
org.gradle.caching=true
```

이 설정이 없으면 Gradle은 빌드 캐시 하위 시스템을 활성화하지 않습니다. 원격 캐시가 구성되어 있더라도 모든 태스크는 캐시 히트나 캐시 채우기 없이 실행됩니다. 활성화되면 Gradle은 Tuist를 원격 빌드 캐시로 사용하여, 캐시 히트 시 캐시된 태스크 결과를 다운로드하고 태스크 실행 후에 업로드합니다.

## 캐시 업로드 정책 {#cache-upload-policy}

기본적으로 이 플러그인은 아티팩트를 원격 캐시에 다운로드하고 업로드합니다. `buildCache` 블록의 `push` 옵션으로 업로드를 제어할 수 있습니다:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

일반적인 패턴은 빌드가 재현 가능한 CI에서만 아티팩트를 푸시하고, 로컬 환경은 읽기 전용으로 유지하는 것입니다:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

이 설정을 사용하면 로컬 빌드는 업로드 없이 캐시된 아티팩트의 이점을 얻으며, CI 빌드는 나머지 팀을 위해 캐시를 채웁니다.

## 지속적 통합 {#continuous-integration}

CI 환경에서는 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>에 설명된 방법 중 하나로 인증하세요. 제공업체별 CI 예제는 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>를 참조하세요.

### 로컬 빌드 캐시 비활성화 {#disabling-the-local-build-cache}

Gradle은 로컬 빌드 캐시와 원격 빌드 캐시를 모두 유지합니다. 로컬 빌드 캐시는 디스크의 `~/.gradle/caches/build-cache-1` 아래에 태스크 출력을 저장합니다.

Tuist를 원격 빌드 캐시로 구성한 경우, CI에서 로컬 빌드 캐시를 비활성화하는 것이 좋습니다. 이렇게 하면 CI 러너에 중복 아티팩트가 저장되는 것을 방지하고, 빌드가 항상 나머지 팀을 위해 새로운 항목으로 원격 캐시를 채우도록 보장합니다.

`settings.gradle.kts`에서 CI 환경의 Gradle 로컬 빌드 캐시를 비활성화하세요:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

이렇게 하면 로컬 개발에서는 로컬 빌드 캐시를 사용할 수 있고, Tuist의 원격 캐시가 아티팩트 공유를 처리하는 CI에서는 비활성화된 상태로 유지됩니다.

## 구성 참조 {#configuration-reference}

`buildCache` 블록은 다음을 지원합니다:

| 옵션 | 유형 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 원격 빌드 캐시 활성화 여부입니다. |
| `push` | `Boolean` | `true` | 태스크 출력을 원격 캐시에 업로드할지 여부입니다. |
| `allowInsecureProtocol` | `Boolean` | `false` | 안전하지 않은 HTTP 연결을 허용할지 여부입니다. |
