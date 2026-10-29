---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle 빌드 인사이트 {#gradle-build-insights}

Tuist의 Gradle 플러그인은 빌드 분석 데이터를 Tuist로 전송하여 태스크 실행 및 빌드 성능에 대한 가시성을 제공합니다.

## 업로드 동작 구성 {#configure-upload-behavior}

기본값:
- 로컬 빌드의 경우 빌드 분석 데이터가 백그라운드로 업로드됩니다.
- CI 실행의 경우 짧은 수명의 에이전트에서 텔레메트리 손실을 방지하기 위해 빌드 분석 데이터가 포그라운드로 업로드됩니다.

`tuist` 확장 내에서 `uploadInBackground`를 사용하여 이 동작을 제어할 수 있습니다:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## 구성 참조 {#configuration-reference}

`settings.gradle.kts`의 `tuist` 확장 블록에서 `uploadInBackground` 옵션을 사용할 수 있습니다:

| 옵션 | 유형 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (로컬에서는 백그라운드, CI에서는 포그라운드) | 로컬 빌드에 대해 빌드 인사이트를 백그라운드로 업로드할지 여부입니다. |

이 설정은 `buildCache` 블록의 원격 캐시 설정에 영향을 주지 않습니다.

## 보고서 액터 클레임 {#report-actor-claim}

빌드 및 테스트 보고서 요청에는 조직 범위 라벨로 `TUIST_ACTOR_ID`를 명시적으로 설정하거나 설정에서 `buildInsights.actorId`를 구성한 경우에만 선택적 `x-tuist-actor-id` 헤더가 포함됩니다. 기본적으로 라벨은 전송되지 않으며, 플러그인은 운영 체제 사용자 이름을 감지하지 않습니다. 환경 변수 재정의가 우선합니다. 보고된 식별자를 생략하려면 재정의 값을 빈 문자열로 설정하세요. 이는 개별 자격 증명으로 확립된 신원을 제거하지 않습니다. 잘못된 재정의는 폴백 대신 클레임을 생략합니다.カスタム 프록시가 익숙하지 않은 헤더를 거부하는 경우 `TUIST_ACTOR_ID=""`로 옵트아웃하세요.

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

액터 식별자는 공백이 없는 인쇄 가능한 ASCII 문자 1~128바이트여야 합니다. 프로젝트가 공개된 경우 공개 뷰어를 포함하여 프로젝트 보고서를 볼 수 있는 모든 사람에게 표시되며 보고서와 함께 내보내집니다. 공개하고 싶지 않은 비밀 정보나 개인 정보는 포함하지 마세요. 대시보드에서는 검증된 개별 자격 증명이 우선하며, 그렇지 않으면 클라이언트가 전송한 식별자는 명시적으로 **검증되지 않음**으로 표시됩니다. 이러한 식별자는 권한을 부여하거나 Tuist 사용자와 자동으로 연결되지 않습니다. 이전 서버는 속성 헤더를 무시하며, 새 서버는 해당 헤더 없이도 이전 클라이언트를 계속 수용합니다. 식별자가 없는 새로운 공유 토큰 보고서는 게시 조직 대신 **알 수 없음**으로 표시되며, 과거 보고서는 기존 속성을 유지합니다. 빌드 및 테스트 목록은 검증된 사용자 필터와 검증되지 않은 보고 식별자 필터를 구분합니다.

## 네트워크 신뢰 게시 {#network-trusted-publishing}

자체 호스팅 배포는 개발자 자격 증명 없이 신뢰할 수 있는 네트워크의 Gradle 빌드 및 테스트 보고서를 명시적으로 허용할 수 있습니다. 운영자는 인스턴스에서 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`를 구성하고 먼저 다시 시작해야 합니다. 이는 지원되는 모든 프로젝트에 적용되며 대시보드 설정은 없습니다. <.localized_link href="/guides/server/self-host/server#network-trusted-access">자체 호스팅 가이드</.localized_link>를 참조하세요.

리포지토리에서 대상을 한 번 구성하세요:

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

빌드 및 테스트 보고에는 인증된 캐시 엔드포인트 검색이 필요하지 않습니다. 인스턴스가 별도로 네트워크 신뢰 캐시 액세스를 활성화하거나 개발자가 토큰을 제공하지 않는 한 캐시를 비활성화하세요. 서명되지 않은 테스트 보고서는 샤드 및 기존 빌드 참조를 생략하며 격리 또는 불안정성 자동화를 트리거하지 않습니다. 자격 증명이 실제로 없는 경우 격리 조회를 건너뜁니다. 유효한 자격 증명이 있으면 기존 인증 동작이 유지됩니다. 자격 증명이 있는 경우 여전히 사용되며, 잘못된 자격 증명은 자격 증명 없는 게시로 폴백하지 않고 실패합니다. 자격 증명이 없는 경우 플러그인은 자체 호스팅 서버가 자격 증명 없는 보고를 허용하는지 자동으로 검색합니다. 클라이언트 플래그나 `buildInsights` 설정이 필요하지 않습니다. 자격 증명 없는 클라이언트를 업그레이드하기 전에 모든 서버 복제본을 검색 가능 버전으로 업그레이드하세요. 검색 기능이 없는 이전 서버, 비활성화된 인스턴스 및 검색 오류는 여전히 인증이 필요하며 인증된 게시는 호환됩니다. 명시적으로 빈 `TUIST_TOKEN`는 자격 증명 없는 게시를 활성화하지 않고 차단적으로 실패합니다. 시크릿이 없는 포크 또는 Dependabot 작업의 경우 해당 변수를 빈 문자열로 정의하는 대신 제거하세요.

서버는 자격 증명 없는 보고서 ID를 할당합니다. 제출을 반복하면 두 번째 보고서가 생성될 수 있으며, 이 모드는 멱등적인 재시도나 인증된 테스트 보고서와의 상관관계를 보장하지 않습니다. 이러한 보고서는 VCS 댓글이나 자동 실패 에이전트 이벤트를 트리거할 수 없습니다. 네트워크 액세스는 게시 신뢰 경계이며, 보고된 액터의 신원 증명이 아닙니다.

## 사용자 정의 메타데이터 {#custom-metadata}

다른 팀, 하드웨어 또는 워크플로우의 실행을 비교하기 위해 Gradle 빌드에 태그와 키-값 데이터를 첨부하세요. 태그는 대시보드 필터로 사용할 수 있으며, 값은 각 빌드의 상세 페이지와 애플리케이션 프로그래밍 인터페이스 및 Model Context Protocol 도구에 표시됩니다.

환경 변수로 메타데이터를 설정하세요:

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

`settings.gradle.kts`에서도 메타데이터를 구성할 수 있습니다:

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

양쪽 장소에 동일한 값이 구성된 경우 `settings.gradle.kts`의 값이 우선합니다.

태그는 문자, 숫자, 하이픈 및 밑줄만 포함해야 합니다. 빌드에는 최대 50개의 태그를 사용할 수 있으며 각 태그는 최대 50자까지 포함할 수 있습니다. 빌드에는 최대 20개의 키-값 항목을 사용할 수 있으며 각 키는 최대 50자, 각 값은 최대 500자까지 포함할 수 있습니다. 이는 Xcode 빌드 메타데이터에 사용되는 것과 동일한 서버 측 제한 사항입니다. 플러그인은 보고서를 전송하기 전에 잘못된 태그와 크기 초과 또는 빈 메타데이터 항목을 건너뛰므로 잘못된 구성으로 인해 나머지 빌드 인사이트 보고서가 저장되지 않는 것을 방지할 수 있습니다. 태그 제약 조건을 충족하지 않는 값에는 키-값 메타데이터를 사용하세요.

사용자 정의 메타데이터는 대시보드와 애플리케이션 프로그래밍 인터페이스 및 Model Context Protocol 도구를 통해 프로젝트 멤버에게 표시됩니다. 자격 증명, 액세스 토큰 또는 기타 민감한 데이터에는 사용하지 마세요. Tuist는 이 메타데이터를 포함한 Gradle 빌드 데이터를 90일 동안 보관합니다. 자세한 내용은 <.localized_link href="/guides/server/data-retention">데이터 보존 정책</.localized_link>을 참조하세요.
