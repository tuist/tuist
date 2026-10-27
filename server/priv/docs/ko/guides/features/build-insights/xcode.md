---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode 빌드 인사이트 {#xcode-build-insights}

대규모 프로젝트 작업 시 동일한 코드를 반복해서 다시 빌드할 필요가 없어야 합니다. Tuist Build Insights를 사용하면 로컬 및 CI 빌드 시간이 병목 현상이 되기 전에 추세를 파악할 수 있도록 빌드 분석을 추적할 수 있습니다.

빌드 인사이트는 일반적으로 스킴의 포스트 액션에 추가되는 `tuist inspect build` 명령어로 구동됩니다.

로컬 빌드 시간 추적을 시작하려면 스킴의 포스트 액션에 `tuist inspect build` 명령어를 추가하여 활용할 수 있습니다:

![빌드 검사용 포스트 액션](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 빌드 구성을 캡처하려면 "Provide build settings from" 필드를 실행 파일이나 주요 빌드 타겟으로 설정하세요.


> [!NOTE]
> 빌드가 실패하면 포스트 스킴 액션은 실행되지 않습니다.

>
> 이 경우 관련 `project.pbxproj` `BuildAction`에서 `runPostActionsOnFailure`을 `YES`로 설정하여 실행할 수 있습니다:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/)의 경우, 포스트 액션 환경에서 `tuist`를 활성화하세요:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 경로 해결**
>
> 환경의 `PATH`은 스킴 포스트 액션에 상속되지 않으므로 Mise의 절대 경로를 사용하세요. 이는 Mise 설치 방법에 따라 다릅니다. 빌드 설정은 타겟에서 상속되어야 하므로 `mise`가 `$SRCROOT`에서 실행될 수 있습니다.

[Homebrew](https://brew.sh/)의 경우, Homebrew 경로를 포스트 액션 환경에 추가하세요:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

액터 클레임은 기본적으로 비활성화되어 있습니다. 스킴 포스트 액션용 클레임을 구성하려면 셸 내보내기에 의존하지 않고 해당 스크립트에서 `TUIST_ACTOR_ID`을 설정하세요. Dock에서 실행된 Xcode는 `~/.zshrc`의 변수를 상속하지 않습니다. Homebrew로 구성된 클레임을 명시적으로 억제하려면 다음을 사용하세요:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Mise의 경우, Mise가 환경을 로드한 후 값을 재정의하세요:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

옵트인하려면 빈 값 대신 명시적 라벨을 사용하세요.

로그인하면 로컬 빌드가 추적되며 Tuist 대시보드에서 확인할 수 있습니다:

> [!TIP]
> 대시보드에 빠르게 접근하려면 CLI에서 `tuist project show --web`을 실행하세요.


![빌드 인사이트가 포함된 대시보드](/images/guides/features/build-insights/builds-dashboard.png)

## CI에서의 빌드 인사이트 {#continuous-integration}

CI에서 빌드 인사이트를 추적하려면 CI가 <.localized_link href="/guides/integrations/continuous-integration#authentication">인증됨</.localized_link>인지 확인하세요.

Xcodebuild 기반 CI의 경우 다음이 필요합니다:
- `xcodebuild` 액션을 호출할 때 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>를 사용하세요.
- `xcodebuild` 명령어에 `-resultBundlePath`을 추가하세요.

`-resultBundlePath`이 없으면 필요한 활동 로그와 결과 번들이 생성되지 않으며 `tuist inspect build`가 빌드를 분석할 수 없습니다.

## 프라이빗 네트워크에서의 자격 증명 없는 보고 {#network-trusted-publishing}

자체 호스팅 배포는 개발자가 로그인 없이 완료된 보고서를 게시할 수 있도록 허용할 수 있습니다. 운영자는 인스턴스에서 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true`을 구성하고 <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">자체 호스팅 가이드</.localized_link>에 설명된 대로 재시작해야 합니다. 이는 지원되는 모든 프로젝트에 적용되며 대시보드 설정은 없습니다. 스킴 포스트 액션이나 터미널에서 사용되는 환경에서 자체 호스팅 URL과 프로젝트를 구성하세요. CLI는 자격 증명이 없을 때 인스턴스 정책을 자동으로 발견합니다:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

자격 증명이 실제로 없는 경우, 활동 로그와 XCResult 번들은 로컬에서 파싱되어 구조화된 보고서로 전송됩니다. 원본 아카이브, 첨부 파일, 커버리지/히스토리 업로드, 원격 프로세서, 샤드 참조 또는 선택적 실행 증거는 제출되지 않습니다. 보고서는 계속 표시되지만 인증된 테스트 케이스 상태를 업데이트하거나 격리/실패 자동화를 트리거할 수는 없습니다. 대시보드, 캐시 및 기타 인증된 명령어는 여전히 로그인이 필요합니다. 자격 증명이 프로비저닝되지 않은 경우 캐시 통합을 비활성화된 상태로 유지하세요.

현재 자격 증명은 인증된 상태로 유지됩니다. 유효하지 않거나 손상되었거나 공백이거나 갱신이 거부된 자격 증명은 안전하게 실패하며 디스크에 남아 있으므로 이후 명령어가 자동으로 서명되지 않은 상태가 되지 않습니다. 의도적인 복구 조치로 다시 로그인하거나 명시적으로 로그아웃하세요. 자격 증명 없는 클라이언트를 업그레이드하기 전에 모든 서버 복제본을 검색 가능한 버전으로 업그레이드하고 리디렉션 없이 최종 서버 URL을 구성하세요. 검색 기능이 없는 이전 서버, 비활성화된 인스턴스 및 검색 실패는 여전히 인증이 필요합니다. 클라이언트 측 옵트인은 필요하지 않습니다. 구성된 액터 클레임을 생략하려면 `TUIST_ACTOR_ID=""`을 독립적으로 설정하세요. 검증된 자격 증명 신원은 영향을 받지 않습니다.

## 머신 메트릭 {#machine-metrics}

빌드 인사이트에는 빌드 중에 캡처된 머신 수준 성능 메트릭(CPU, 메모리, 네트워크 및 디스크 사용량)이 포함될 수 있습니다. 이를 활성화하려면 시스템 메트릭을 지속적으로 샘플링하는 경량 백그라운드 데몬을 설정하세요:

```bash
tuist setup insights
```

이는 백그라운드에서 메트릭을 샘플링하는 로컬 데몬을 실행합니다. 데이터는 `tuist inspect build`에 의해 자동으로 수집되어 빌드 보고서와 함께 업로드됩니다.

> [!TIP]
> **CI**
>
> 머신 메트릭도 캡처하려면 빌드 전에 CI 머신에서 `tuist setup insights`을 실행하세요.

머신 메트릭 수집을 중지하려면 다음을 실행하세요:

```bash
tuist teardown insights
```

이는 데몬의 LaunchAgent를 언로드하고 plist를 제거하며 `~/.local/state`에서 샘플링된 메트릭과 데몬 로그를 삭제하므로 백그라운드에서 실행 중인 항목이 남지 않습니다.


## 보고서 액터 클레임 {#report-actor-claim}

보고서 생성 요청은 `TUIST_ACTOR_ID`을 조직 범위 라벨로 명시적으로 설정한 경우에만 선택적 `x-tuist-actor-id` 헤더를 포함합니다(예: `TUIST_ACTOR_ID=employee-123 tuist inspect build`). 기본적으로 라벨은 전송되지 않으며 Tuist는 운영 체제 사용자 이름을 감지하지 않습니다. 빈 `TUIST_ACTOR_ID`는 보고된 식별자를 생략하지만 자격 증명 기반 검증된 신원을 제거하지는 않습니다. 식별자는 공백이 아닌 인쇄 가능한 ASCII 1~128바이트여야 하며 유효하지 않은 재정의는 대체 없이 생략됩니다. custom proxy가 익숙하지 않은 헤더를 거부하는 경우 빈 환경 재정으로 옵트아웃하세요.

검증된 개인 자격 증명이 우선하며, 그렇지 않으면 클라이언트가 보고한 식별자는 **검증되지 않음**으로 표시되며 권한을 부여하거나 사용자와 자동으로 연결되지 않습니다. 식별자는 프로젝트의 보고서를 볼 수 있는 모든 사람(프로젝트가 공개된 경우 공개 뷰어 포함)에게 보이며 데이터 내보내기에 포함되므로 비밀 정보를 포함하지 마세요. 이는 빌드, 테스트 및 명령어 이벤트 보고서에 적용됩니다. 이전 서버는 선택적 헤더를 무시하고 새 서버는 해당 헤더 없이 이전 클라이언트를 허용합니다. 식별자가 없는 새로운 공유 토큰 보고서는 게시 조직 대신 **알 수 없음**으로 표시되며 기존 보고서는 이전 속성을 유지합니다. 빌드 및 테스트 목록은 검증된 사용자와 검증되지 않은 보고된 식별자를 구분합니다. 자체 호스팅 인스턴스가 명시적으로 자격 증명 없는 보고를 활성화하고 클라이언트가 해당 정책을 발견하지 않는 한 인증이 필요합니다.

## custom metadata {#custom-metadata}

필터링을 개선하기 위해 환경 변수를 사용하여 빌드에 메타데이터를 첨부할 수 있습니다.

### 환경 변수

| 변수 | 형식 | 설명 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 쉼표로 구분 | 하나의 변수에 여러 태그를 지정합니다. |
| `TUIST_BUILD_VALUE_*` | 단일 값 | 접미사가 키인 키-값 쌍입니다. |

### 예시

빌드를 실행하기 전에 CI 또는 셸에서 이러한 값을 설정하세요:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
