---
{
  "title": "Gradle 플러그인 설치",
  "titleTemplate": ":title · 가이드 · Tuist",
  "description": "프로젝트에서 Tuist의 Gradle 플러그인을 설치하고 구성하는 방법을 알아보세요."
}
---
# Gradle 플러그인 설치 {#install-the-gradle-plugin}

Tuist는 Gradle 프로젝트와 통합되어 <.localized_link href="/guides/features/cache/gradle-cache">원격 빌드 캐싱</.localized_link> 및 <.localized_link href="/guides/features/build-insights/gradle">빌드 인사이트</.localized_link>와 같은 기능을 사용할 수 있게 해주는 Gradle 플러그인을 제공합니다. 이 가이드에서는 플러그인을 설치하고 구성하는 방법을 안내합니다.

이 플러그인은 Gradle 8.12.1 이상이 필요합니다.

## 1. Tuist 초기화 {#initialize-tuist}

Gradle 프로젝트 루트에서 다음 명령어를 실행하세요:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

이 명령어는 인증 과정, Tuist 프로젝트 생성 또는 선택, 그리고 Gradle 프로젝트용 구성 파일 생성을 안내합니다.

## 2. 플러그인 적용 {#apply-the-plugin}

`tuist init`를 실행한 후, 명령어 출력의 지시에 따라 `settings.gradle.kts`에 Tuist 플러그인을 추가해야 합니다:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. 팀 및 지속적 통합(CI) 인증 {#authenticate}

`tuist init`는 로컬 환경을 인증하지만, 팀원들과 <.localized_link href="/guides/integrations/continuous-integration">지속적 통합</.localized_link> 환경은 별도로 인증해야 합니다.

각 팀원은 자신의 머신에서 Tuist 기능에 액세스하기 위해 다음을 실행해야 합니다:

```bash
tuist auth login
```

자체 호스팅 또는 로컬 Tuist 서버를 사용하는 경우, `tuist.toml`에 구성된 것과 동일한 기본 URL을 전달하세요:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

호스트명 표기를 일관되게 유지하세요. 예를 들어, `localhost`에 저장된 로그인 정보는 `127.0.0.1`에 저장된 것과 별개입니다.

자동화된 러너의 경우, <.localized_link href="/guides/integrations/continuous-integration#authentication">지속적 통합 인증 가이드</.localized_link>를 따라 환경에 맞는 인증을 구성하세요.

## 구성 캐시 및 격리된 프로젝트 {#configuration-cache-and-isolated-projects}

이 플러그인은 Gradle의 구성 캐시와 [Isolated Projects](https://docs.gradle.org/current/userguide/isolated_projects.html)를 지원합니다. 플러그인은 `settings.gradle.kts`에 유지하면 되며, 각 하위 프로젝트에 별도로 적용할 필요는 없습니다.

Tuist는 이러한 기능을 자동으로 활성화하지 않습니다. 사용하려면 `gradle.properties`에 다음을 추가하세요:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

빌드 스크립트와 다른 플러그인들도 이러한 기능을 지원해야 합니다. Gradle은 구성 캐시를 저장할 때 호환성 문제를 보고합니다.

## 구성 참조 {#configuration-reference}

`settings.gradle.kts`의 `tuist` 확장 블록에서 다음 옵션을 사용할 수 있습니다:

| 옵션 | 유형 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (선택 사항) | `account/project` 형식의 프로젝트 식별자입니다. 설정되지 않은 경우, 플러그인은 `tuist.toml`에서 값을 읽습니다. |
| `url` | `String?` | `null` | Tuist 서버의 기본 URL입니다. 설정되지 않은 경우, 기본값은 `"https://tuist.dev"`이거나 `tuist.toml`에 정의된 값입니다. |
| `uploadInBackground` | `Boolean?` | `null` | 빌드 및 테스트 인사이트를 백그라운드에서 업로드할지 여부를 결정합니다. `null`(기본값)일 때, 로컬 빌드는 백그라운드에서 업로드되고 지속적 통합 러너에서는 포그라운드에서 업로드됩니다. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` 또는 `"enforce"`. 빌드가 추가한 테스트 케이스를 다시 실행하고 불안정한(flaky) 테스트를 표시합니다. 자세한 내용은 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">새 테스트 스트레스 테스트</.localized_link>를 참조하세요. 설정되지 않으면 비활성화됩니다. |

`http://` URL을 사용하는 로컬 서버의 경우, 해당 로컬 구성에서만 안전하지 않은 프로토콜을 허용하세요:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

호스팅되거나 기타 `https://` 서버에는 `allowInsecureProtocol`를 활성화하지 마세요.

> [!NOTE]
> **Tuist.toml**
>
> `project`(및 선택적으로 `url`)를 구성하는 권장 방법은 프로젝트 루트에 `tuist.toml` 파일을 사용하는 것입니다. 이렇게 하면 Tuist 명령줄 인터페이스와 Gradle 플러그인이 구성을 공유합니다. 필요한 경우 `settings.gradle.kts`에서 이러한 값을 재정의할 수 있습니다.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP 프록시 {#http-proxy}

네트워크가 HTTP 프록시를 통해 아웃바운드 트래픽을 라우팅하는 경우, <.localized_link href="/guides/integrations/http-proxy">HTTP 프록시 가이드</.localized_link>를 참조하세요.

## 다음 단계 {#next-steps}

플러그인이 설치되고 구성되면 다음을 활성화할 수 있습니다:

- 팀과 지속적 통합 러너 간에 빌드 아티팩트를 공유하기 위한 <.localized_link href="/guides/features/cache/gradle-cache">원격 빌드 캐시</.localized_link>
- Tuist 대시보드에서 작업 시간과 캐시 동작을 추적하기 위한 <.localized_link href="/guides/features/build-insights/gradle">빌드 인사이트</.localized_link>
- <.localized_link href="/guides/features/test-insights/gradle">테스트 인사이트</.localized_link>를 통해 테스트 성능을 추적하고 불안정한 테스트를 감지하세요.
- <.localized_link href="/guides/features/test-insights/flaky-tests">불안정한 테스트</.localized_link>를 통해 불안정한 테스트를 자동으로 감지, 추적 및 격리하세요.
