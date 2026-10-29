---
{
  "title": "Bazel Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Bazel command duration, cache totals, and critical-path diagnostics in the Tuist dashboard."
}
---
# Bazel 빌드 인사이트 {#bazel-build-insights}

완료된 모든 `build`, `test` 및 기타 Bazel 명령은 프로젝트의 **Invocations** 대시보드에 표시됩니다: 명령 종류, 종료 상태, 시작 및 종료 시간, 지속 시간, 그리고 해당 호출에 대해 Bazel이 기록한 캐시 히트, 미스, 다운로드 및 업로드 정보.

호출 데이터는 Bazel의 [Build Event Protocol](https://bazel.build/remote/bep)을 통해 전달됩니다. `tuist bazel setup`를 실행하면 설정 과정에서 자동으로 연동되므로, 호출 정보를 확인하기 위해 추가 플래그가 필요하지 않습니다.

## 대시보드 표시 내용 {#what-the-dashboard-shows}

각 호출은 다음 정보를 기록합니다:

- Bazel이 실행한 명령, 종료 코드, 시작 및 종료 시간, 총 지속 시간.
- 액션, 타겟 및 패키지 수.
- 제한된 빌드 타임라인과 크리티컬 경로 요약.
- 해당 호출에 귀속된 캐시 히트, 미스, 다운로드 및 업로드.
- 실행 중에 캡처된 진행 로그 라인(실행 순서대로).
- Bazel 버전, Bazel이 보고하는 경우 git 브랜치와 커밋, 그리고 CI에서 실행되었는지 여부.

Bazel이 완료된 호출에 귀속시킬 수 없는 캐시 활동(예: 명령 실행 중 중단된 경우)은 원시 원격 캐시 관찰 항목으로 프로젝트 **Overview**에 계속 표시됩니다. 이는 명령 성공, 지속 시간 또는 테스트 결과의 증거로 처리되지 않습니다.

## 사용자 정의 메타데이터 {#custom-metadata}

다른 팀, 하드웨어 또는 워크플로우의 실행을 비교하기 위해 호출에 키-값 데이터를 첨부하세요. 값은 각 호출의 상세 페이지와 애플리케이션 프로그래밍 인터페이스 및 Model Context Protocol 도구를 통해 확인할 수 있습니다.

Bazel의 내장 `--build_metadata` 플래그를 사용하여 메타데이터를 설정하세요:

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

또는 `.bazelrc`에서 레인당 한 번씩 설정하세요:

```text
build:ci --build_metadata=RUNNER=macos-14
```

각 호출에는 최대 20개의 사용자 정의 항목을 포함할 수 있습니다. 키는 최대 50자, 값은 최대 500자까지 사용할 수 있습니다. 이러한 제한을 초과하는 항목은 호출이 저장되기 전에 삭제되므로, 잘못된 항목이 있어도 나머지 보고서가 기록되는 데 방해가 되지 않습니다.

Tuist가 빌드 환경에서 파생하는 컨텍스트 키(`CI`, `GIT_BRANCH`, `GIT_COMMIT` 등)는 호출의 주요 필드에 이미 채워지므로 사용자 정의 값으로 저장되지 않습니다.

사용자 정의 메타데이터는 대시보드와 애플리케이션 프로그래밍 인터페이스 및 Model Context Protocol 도구를 통해 프로젝트 구성원에게 표시됩니다. 자격 증명, 액세스 토큰 또는 기타 민감한 데이터에는 사용하지 마세요.

## 옵트아웃 {#opting-out}

Build Event Protocol 스트림에는 명령줄 인수, 환경 변수 값 및 명령 출력이 포함됩니다. Tuist는 위에 나열된 완료된 명령 필드만 유지하고 나머지는 discard하지만, 이벤트 스트림 자체를 전송하지 않으려면 다음과 같이 설정을 다시 실행하세요:

```bash
tuist bazel setup --no-build-insights
```

생성된 `.bazelrc.tuist`은 원격 캐시만 구성합니다. 호출은 더 이상 대시보드에 표시되지 않으며, 캐시 관찰 항목은 **Overview** 페이지에 남습니다.

## 데이터 보존 {#data-retention}

Tuist는 Bazel 호출과 해당 로그를 90일 동안 보관합니다. 전체 정책은 <.localized_link href="/guides/server/data-retention">데이터 보존</.localized_link>을 참조하세요.
