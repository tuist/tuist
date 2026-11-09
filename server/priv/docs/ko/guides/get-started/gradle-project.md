---
{
  "title": "Gradle 프로젝트",
  "titleTemplate": ":title · 시작하기 · 가이드 · Tuist",
  "description": "Gradle 프로젝트를 Tuist에 연결하여 공유 원격 빌드 캐시, CI 전반의 빌드 및 테스트 인사이트, 번들 크기 추적, 미리보기 링크를 활용하세요."
}
---
# Gradle 프로젝트 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

기존 Gradle 프로젝트를 Tuist와 연결하려면 다음 단계를 따르세요. `dev.tuist` Gradle 플러그인은 Gradle의 로컬 빌드 캐시를 Tuist의 원격 캐시에 연결하고, `./gradlew` 명령을 하나도 변경하지 않고도 빌드 및 테스트 데이터를 대시보드로 업로드합니다.

아래 각 섹션은 현재 부족한 점을 설명한 후, 그 격차를 채워주는 기능을 소개합니다.

## 필수 조건

- `settings.gradle.kts`(또는 `settings.gradle`) 파일이 있는 Gradle 프로젝트
- <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스</.localized_link>.

## 프로젝트 연결

Gradle 프로젝트 루트에서 `tuist init`를 실행하세요. **Gradle 프로젝트 통합**을 선택한 후, 브라우저에서 인증하고 프로젝트를 소유할 계정을 선택하세요.

```bash
tuist init
```

코딩 에이전트나 스크립트로 이 작업을 수행하려면 먼저 `tuist auth login`를 실행하세요(브라우저 흐름에서 Enter 키를 누르길 기다립니다). 그다음 비대화형 형식을 사용하세요:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist는 저장소 루트에 프로젝트 핸들이 포함된 `tuist.toml` 파일을 작성하고 `plugins { ... }` 블록을 출력합니다. 이를 `settings.gradle.kts` 파일 상단에 붙여넣으세요:

<!-- @snippet: ../_gradle-plugin-block -->

`./gradlew help`로 정상 동작 여부를 확인하세요. Gradle이 오류 없이 로드되어야 합니다. 플러그인을 찾을 수 없다면 해당 블록이 `build.gradle.kts`가 아닌 `settings.gradle.kts`에 있는지 확인하세요.

아래 내용은 모두 선택 사항이며 서로 독립적입니다.

## 원격 빌드 캐시

Gradle의 로컬 빌드 캐시는 태스크 출력을 생성한 머신에 저장합니다. 같은 브랜치를 사용하는 두 개발자는 각각의 `~/.gradle` 디렉터리에서만 캐시를.hit하며 서로의 캐시는 사용하지 않습니다. CI는 매번 새롭고 빈 캐시로 시작합니다.

Tuist 원격 캐시는 Gradle이 이미 머신 간에 사용하는 동일한 키/값 프로토콜을 확장합니다. 태스크의 출력물은 처음 실행한 머신에서 업로드되며, 동일한 입력을 마주하는 다른 사용자가 다운로드합니다. `gradle.properties`에서 이를 활성화하세요:

```properties
org.gradle.caching=true
```

그런 다음 두 환경에서 빌드하세요:

```bash
./gradlew clean build --build-cache --info
```

캐시 가능한 태스크는 두 번째 실행 시 `FROM-CACHE`로 보고됩니다. 대시보드에서 **캐시**를 열어 시간 경과에 따른 히트율을 확인하세요.

## 빌드 인사이트

Gradle은 빌드 종료 시 태스크 소요 시간을 출력하며, `--profile` 옵션을 사용하면 빌드별 HTML 보고서를 작성합니다. 하지만 둘 다 여러 실행에 걸쳐 집계하지 않습니다. 일련의 커밋 동안 느려진 태스크는 단일 빌드 보고서에서 항상 동일하게 보입니다.

`dev.tuist` 플러그인이 적용되면 모든 빌드의 태스크 소요 시간이 자동으로 대시보드로 업로드됩니다. 추가 구성이 필요하지 않습니다. 다음 `./gradlew build` 실행 후 대시보드에서 **빌드**를 열어 추이를 확인하세요.

## 테스트 인사이트

Gradle의 테스트 보고서는 빌드별로 `build/reports/tests/` 아래에 저장됩니다. 열 번의 CI 실행 중 간헐적으로 실패하는 테스트는 특정 보고서에서는 한 번 실패한 안정적인 테스트처럼 보입니다.

테스트 인사이트는 모든 `./gradlew test` 실행에 대해 각 태스크의 결과와 지속 시간을 기록하고 실행 간 결과를 상관관계로 분석합니다. 불안정한 테스트, 느린 테스트, 실패는 대시보드의 **테스트** 탭에 표시됩니다. 불안정성이 누적되면 대시보드에서 격리하여 머지를 차단하지 않도록 하세요.

이 플러그인은 빌드가 도입한 테스트 케이스를 다시 실행하고 안정성이 입증되지 않은 경우 플래그를 지정하는 **스트레스 테스트 모드**도 지원합니다. 이를 `settings.gradle.kts`의 `tuist` 확장 블록에 추가하세요:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 번들 인사이트

Android Gradle 플러그인은 빌드 출력에서 생성된 `.aab`의 크기를 보고합니다. 이 숫자는 브랜치와 함께 사라지며, 릴리스 간 크기 비교는 수동으로 처리해야 합니다. Play Console도 동일한 숫자를 보고하지만, 아티팩트가 업로드된 후에만 가능합니다.

번들 인사이트는 모든 `.aab`(권장) 또는 `.apk`의 설치 및 다운로드 크기를 기록하며, 브랜치별 임계값을 초과하면 PR 검사를 실패시킬 수 있습니다. 빌드 단계 직후 CI에 이를 추가하세요:

```bash
tuist inspect bundle App.aab
```

대시보드에서 **번들 인사이트 → Android**를 열어 추이를 확인하고 임계값을 구성하세요.

## 프리뷰

Play Console의 내부 테스트 트랙은 공유할 때마다 검토 및 전파 지연 시간을 추가합니다. Slack이나 이메일로 원본 `.apk`을 보내는 것이 더 빠르지만, 특정 메시지가 어떤 빌드를 참조하는지 추적하기 어렵습니다.

이 플러그인은 별도의 CLI 업로드 없이 애플리케이션 변형을 직접 빌드하고 게시할 수 있습니다:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`tuistShare<Variant>` 태스크를 요청하면 해당 호출이 게시 대상이 됩니다. 일반 빌드는 프리뷰를 업로드하지 않습니다. 지원되는 APK, 서명 및 설치 방법은 <.localized_link href="/guides/features/previews/gradle">Gradle 프리뷰</.localized_link>를 참조하세요.

## 팀 참여 유도

캐시 히트, 인사이트, 스트레스 테스트는 프로젝트에 연결된 인원 수가 늘어날수록 효과가 증폭됩니다. 대시보드의 계정 설정에서 팀원을 조직에 초대하고, <.localized_link href="/guides/integrations/authentication/sso">싱글 사인온</.localized_link>(Google, Okta, Microsoft)을 설정하여 온보딩을 개인별 `tuist auth login` 대신 클릭 한 번으로 완료할 수 있게 하세요.

CI에서는 개인 로그인을 사용하지 마세요. CI 제공자의 OIDC 신원으로 인증하거나, 대시보드에서 **CI** 프리셋으로 계정 토큰을 생성하여 `TUIST_TOKEN`로 설정하세요. 자세한 내용은 <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle 플러그인 인증</.localized_link>을 참조하세요.

## 플러그인 전체 참조

여기서 다루는 내용은 Gradle 프로젝트에서 Tuist의 가치를 얻기 위한 최소 요구사항입니다. `tuist` 확장 블록, `stressNewTests` 모드 및 CI 인증에 대한 구성 옵션은 [Gradle 플러그인 설치](https://tuist.dev/en/docs/guides/install-gradle-plugin) 참조 문서에 있습니다.
