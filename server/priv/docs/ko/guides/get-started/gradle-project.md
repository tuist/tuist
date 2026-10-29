---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Gradle 프로젝트 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

기존 Gradle 프로젝트를 Tuist에 연결하려면 이 경로를 따르세요. `dev.tuist` Gradle 플러그인은 Gradle의 로컬 빌드 캐시를 Tuist의 원격 캐시에 연결하고, `./gradlew` 명령을 하나도 변경하지 않고 빌드 및 테스트 데이터를 대시보드에 업로드합니다.

아래 각 섹션은 현재 누락된 부분으로 시작하여 그 격차를 채워주는 기능을 안내합니다.

## 사전 요구 사항

- `settings.gradle.kts`(또는 `settings.gradle`)가 있는 Gradle 프로젝트.
- <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스</.localized_link>.

## 프로젝트 연결

Gradle 프로젝트 루트에서 `tuist init`를 실행하세요. **Gradle 프로젝트 통합**을 선택한 후 브라우저에서 인증하고 프로젝트를 소유할 계정을 선택하세요.

```bash
tuist init
```

코딩 에이전트나 스크립트로 진행하는 경우, 먼저 `tuist auth login`를 실행하세요(브라우저 흐름이 Enter 키 입력을 기다립니다). 이후 비대화형 형식을 사용하세요:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist는 저장소 루트에 프로젝트 핸들이 포함된 `tuist.toml`를 작성하고 `plugins { ... }` 블록을 출력합니다. 이를 `settings.gradle.kts` 상단에 붙여넣으세요:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

`./gradlew help`로 정상 동작을 확인하세요. Gradle이 오류 없이 로드되어야 합니다. 플러그인을 찾을 수 없는 경우, 블록이 `build.gradle.kts`가 아닌 `settings.gradle.kts`에 있는지 확인하세요.

아래 내용은 모두 선택 사항이며 독립적입니다.

## 원격 빌드 캐시

Gradle의 로컬 빌드 캐시는 태스크 출력을 생성한 머신에 저장합니다. 같은 브랜치의 두 개발자는 서로의 캐시가 아닌 각각의 `~/.gradle`에서 캐시를_hit_하며, CI는 매 작업마다 새롭고 빈 캐시를 사용합니다.

Tuist 원격 캐시는 Gradle이 이미 머신 간에 사용하는 동일한 키/값 프로토콜을 확장합니다. 태스크의 출력은 처음 실행한 머신에서 업로드되며, 동일한 입력을 마주치는 다른 사용자가 다운로드합니다. `gradle.properties`에서 활성화하세요:

```properties
org.gradle.caching=true
```

그런 다음 두 환경에서 빌드하세요:

```bash
./gradlew clean build --build-cache --info
```

캐시 가능한 태스크는 두 번째 실행 시 `FROM-CACHE`를 보고합니다. 대시보드에서 **Cache**를 열어 시간 경과에 따른 히트율을 확인하세요.

## 빌드 인사이트

Gradle은 빌드 종료 시 태스크 타이밍을 출력하며, `--profile` 옵션을 사용하면 빌드별 HTML 보고서를 작성합니다. 둘 다 실행 간 집계되지 않습니다. 여러 커밋에 걸쳐 느려진 태스크는 단일 빌드 보고서에서 항상 그랬던 것처럼 동일하게 보입니다.

`dev.tuist` 플러그인이 적용되면 모든 빌드의 태스크 타이밍이 자동으로 대시보드에 업로드됩니다. 추가 구성이 필요하지 않습니다. 다음 `./gradlew build` 이후 대시보드에서 **Builds**를 열어 추세를 확인하세요.

## 테스트 인사이트

Gradle의 테스트 보고서는 `build/reports/tests/` 아래에 빌드별로 저장됩니다. 10번의 CI 실행 중 간헐적으로 실패하는 테스트는 특정 보고서에서 한 번 실패한 안정적인 테스트처럼 보입니다.

테스트 인사이트는 모든 `./gradlew test` 실행에 대해 각 태스크의 결과와 지속 시간을 기록하고 실행 간 결과를 상관관계로 분석합니다. 불안정한 테스트, 느린 테스트, 실패는 대시보드의 **Tests** 탭에 표시됩니다. 불안정성이 누적되면 대시보드에서 격리하여 병합을 차단하지 않도록 하세요.

이 플러그인은 빌드가 도입한 테스트 케이스를 다시 실행하고 안정성이 입증되기 전에 불안정한 것을 표시하는 **스트레스 테스트 모드**도 지원합니다. `settings.gradle.kts`의 `tuist` 확장에 추가하세요:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 번들 인사이트

Android Gradle Plugin은 빌드 출력에서 생성된 `.aab`의 크기를 보고합니다. 이 숫자는 브랜치와 함께 사라지며, 릴리스 간 크기 비교는 수동 회계 작업입니다. Play Console도 동일한 숫자를 보고하지만 아티팩트가 업로드된 후에만 가능합니다.

번들 인사이트는 모든 `.aab`(권장) 또는 `.apk`의 설치 및 다운로드 크기를 기록하며, 브랜치별 임계값을 초과하면 PR 검사를 실패시킬 수 있습니다. 빌드 단계 직후 CI에 이를 추가하세요:

```bash
tuist inspect bundle App.aab
```

대시보드에서 **Bundle insights → Android**을 열어 추세를 확인하고 임계값을 구성하세요.

## 프리뷰

Play Console의 내부 테스트 트랙은 공유할 때마다 검토 및 전파 지연을 추가합니다. Slack이나 이메일로 원본 `.apk`를 보내는 것이 더 빠르지만 특정 메시지가 참조하는 빌드를 추적하기 어렵습니다.

Previews는 빌드를 수신자가 한 명령으로 설치할 수 있는 공유 가능한 링크로 변환합니다:

```bash
tuist share App.apk
```

## 팀 참여 유도

캐시 히트, 인사이트, 스트레스 테스트는 모두 프로젝트에 연결된 인원 수에 따라 효과가 증폭됩니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고, <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩이 개인별 `tuist auth login` 대신 클릭 한 번으로 이루어지도록 하세요.

CI에서는 개인 로그인을 사용하지 마세요. 프로젝트 범위로 `TUIST_TOKEN`를 설정하세요(대시보드의 프로젝트 설정에서 생성).

## 플러그인 전체 참조

여기서 다루는 모든 내용은 Gradle 프로젝트에서 Tuist의 가치를 얻기 위한 최소 요구 사항입니다. `tuist` 확장 블록, `stressNewTests` 모드 및 CI 인증에 대한 구성 옵션은 [Install the Gradle plugin](https://tuist.dev/en/docs/guides/install-gradle-plugin) 참조에 있습니다.
