---
{
  "title": "Bazel 캐시",
  "titleTemplate": ":title · 캐시 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 팀과 CI 간에 Bazel 원격 캐시 항목을 공유하세요."
}
---
# Bazel 캐시 {#bazel-cache}

Tuist는 Bazel이 원격 캐시로 연결하는 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 캐시를 제공합니다. 액션의 출력이 이미 캐시에 있으면 Bazel은 해당 액션을 건너뛰고 Tuist의 캐시에서 결과를 가져와 팀과 CI 환경 전체에서 컴파일 시간을 절약합니다. GitHub Actions 설정 방법은 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)를 참조하세요. 원격 캐싱 작동 방식과 자체 호스팅 캐시 및 관리형 캐시의 비교는 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)를 참조하세요.

## 설정 {#setup}

Bazel 워크스페이스 루트에서 다음을 실행하세요:

```bash
tuist bazel setup
```

이 명령어는 가장 가까운 Tuist 캐시 리전에 연결되고 워크스페이스별 자격 증명 헬퍼로 인증되는 `.bazelrc.tuist` 파일을 `.bazelrc` 옆에 생성합니다. 또한 저장소의 `.bazelrc`에 `try-import` 줄을 추가합니다:

```text
try-import %workspace%/.bazelrc.tuist
```

가져오기를 직접 관리하려면 `--no-add-bazelrc-import`를 전달하세요.

`.bazelrc.tuist`를 `.gitignore`에 추가하고 커밋하는 대신 각 머신에서 설정을 실행하세요. 생성된 파일은 현재 사용자의 Tuist 구성 디렉터리 아래 절대 자격 증명 헬퍼 경로와 해당 파일을 생성한 머신에서 가장 가까운 캐시 리전을 가리키므로, 두 값 모두 동료나 CI 러너로 전달되지 않습니다. 모든 머신에서 동일한 `.bazelrc`의 `try-import` 줄을 커밋하세요.

설정 과정에서 Bazel 워크스페이스 마커를 찾을 수 없거나, 파일이 심볼릭 링크이거나, 이미 원격 캐시 또는 Build Event Service가 구성된 경우 기존 `.bazelrc`는 그대로 둡니다. 따라서 다시 실행해도 멱등성이 유지됩니다.

통합을 확인하기 위해 일반 Bazel 명령어를 실행하세요:

```bash
bazel build //...
```

캐시 활동은 Tuist 대시보드의 프로젝트 **Bazel Cache** 페이지에 표시되며, 여기에는 캐시 전송, 다운로드 및 업로드, 읽기 및 쓰기 지연 시간, 처리량, 액션 캐시 히트율이 포함됩니다. 프로젝트 **Overview**에는 빌드 지속 시간과 함께 동일한 액션 캐시 히트율 요약 정보가 제공됩니다.

명령어가 캐시를 어떻게 사용했는지 확인하려면 **Invocations**에서 열어보세요. 호출 페이지는 액션 캐시 조회와 콘텐츠 객체 요청을 분리하여 표시하므로, 콜드 액션 캐시와 느린 아티팩트 다운로드를 구분할 수 있습니다.

## 원격 실행 {#remote-execution}

Tuist는 Linux 실행기에서 Bazel 액션을 실행할 수도 있으므로, 캐시 미스가 로컬 머신이나 CI 러너 대신 원격으로 처리됩니다. 원격 실행은 활성화된 계정에서 사용할 수 있으며, 계정에 이를 활성화하려면 [이메일 보내기](mailto:contact@tuist.dev) 또는 [상담 예약](https://cal.tuist.dev/team/tuist/tuist)를 이용하세요. 그런 다음 설정에 `--remote-execution`를 전달하세요:

```bash
tuist bazel setup --remote-execution
```

설정은 원격 캐시 옆의 `.bazelrc.tuist`에서 Bazel을 Tuist의 실행기로 지정합니다. 실행 시마다 현재 실행기와 이미지를 조회하므로, 생성된 값을 복사하는 대신 설정을 다시 실행하세요. 액션은 머신에 설치된 도구가 아닌 실행기의 Linux 툴체인으로 실행되므로, 워크스페이스에서 액션에 필요한 툴체인을 선언하세요.

설정은 또한 `--jobs`를 계정이 동시에 실행할 수 있는 원격 액션 수의 두 배로 설정하여, 각 액션이 다음 액션을 기다릴 수 있도록 합니다. 그렇지 않으면 Bazel은 머신의 코어 수만큼 액션을 병렬로 실행하며, 2코어 CI 러너는 단 두 개의 원격 액션만 진행 중 상태로 유지합니다.

다른 값을 사용하려면 명령줄에서 `--jobs`를 전달하거나 `try-import` 줄 이후의 `.bazelrc`에 설정하세요. Bazel은 마지막으로 읽은 값을 사용하므로, 해당 줄 이전의 `--jobs`는 생성된 값으로 대체됩니다.

### 실행기 크기 {#executor-sizes}

액션은 기본적으로 4GB 메모리와 2 vCPU를 사용합니다. 더 큰 VM을 요청하려면 `tuist-memory-gb` 실행 속성을 설정하세요:

| `tuist-memory-gb` | 메모리 | vCPU | 워크스페이스 디스크 |
| --- | --- | --- | --- |
| `4` (기본값) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

예를 들어, `.bazelrc`의 `try-import` 줄 **이후**에 다음을 추가하여 기본적으로 8GB를 요청하세요:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

단일 타겟의 경우 대신 Bazel 규칙에서 `exec_properties = {"tuist-memory-gb": "8"}`를 사용하세요. `4`, `8` 및 `16`만 지원됩니다. 더 큰 액션은 계정에 할당된 vCPU 및 메모리 한도를 비례적으로 더 많이 소비하므로 동시에 실행할 수 있는 액션 수가 줄어듭니다. 형태는 두 한도를 모두 충족해야 합니다. 생성된 `--jobs`는 기본 형태를 사용하므로, 더 큰 형태를 요청할 때 필요하면 이를 재정의하세요.

실행기는 현재 Tuist의 Linux amd64 이미지를 사용합니다. 임의의 컨테이너 이미지, 다른 실행 운영 체제 및 아키텍처, 영속 액션 작업자, 직접 가져온 실행기는 설정을 통해 구성할 수 없습니다. 현재 이미지와 엔드포인트를 얻으려면 설정을 다시 실행하세요.

### 실행 중인 액션 및 사용량 {#running-actions-and-usage}

프로젝트의 **Remote execution** 페이지에는 현재 실행 중인 항목과 과거 실행 항목이 표시됩니다:

- **Invocations**는 실행 중인 Bazel 호출을 먼저 나열하며, 5초마다 새로 고쳐지고 각 호출의 실행 시간과 실행 중 및 대기 중인 원격 액션 수가 표시됩니다. Kura가 타겟 패턴을 받으면 호출이 나타나며 완료된 보고서가 도착할 때까지 유지됩니다. 호출을 열면 해당 **Executions**가 표시됩니다: VM에서 실행 중이거나 대기 중인 원격 액션으로, 각 액션의 니모닉, 타겟, 머신 크기 및 현재 상태에서의 시간이 포함됩니다. 실행 게이트웨이가 사전 준비한 VM에서 실행하는 액션은 실행 중일 때 목록에 표시되지 않으며, 타이밍은 호출이 완료된 후 나타납니다. 목록을 검색하거나 필터링하는 동안에는 실행 중인 호출이 표시되지 않습니다.
- **Analytics**는 선택한 기간의 **Executions** 및 **Total execution time**으로 시작하며, 이전 기간 대비 변화량이 머신 크기별로 차트로 표시됩니다. 총 실행 시간은 각 액션의 실행기가 VM에서 실행된 시간으로, 입력 가져오기와 출력 업로드는 포함되지만 대기 또는 VM 준비 시간은 제외됩니다. 이는 **Usage** 페이지에서 청구되는 시간입니다. 캐시에서 제공된 결과는 실행으로 간주되지 않습니다.

동일한 데이터는 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` 및 `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage`(선택적 `from` 및 `to`, 기본값은 최근 30일이며 최대 366일까지)와 `get_remote_execution_activity` 및 `get_remote_execution_usage` MCP 도구에서 사용할 수 있습니다.

### 원격 액션 타이밍 {#remote-action-timings}

**Analytics**의 나머지 부분과 **Invocations** 테이블은 원격 단계가 기록된 액션을 다룹니다. 여기에는 이전 기간 대비 변화량이 포함된 평균 및 p50/p90/p99 대기 시간과 실행 시간, 추세 차트, 각 호출의 단계 타이밍 링크가 포함됩니다. 날짜별로 필터링할 수 있습니다(최대 90일). 호출 테이블은 각 호출의 평균, p50 및 p90 실행 시간을 보여줍니다. 명령어, 타겟 또는 호출 ID로 검색하고, 상태, 명령어, 타겟 또는 원격 액션 수로 필터링하며, Invocation 열을 제외한 모든 열로 정렬할 수 있습니다. 검색 및 테이블 필터는 분석 데이터가 아닌 호출 테이블에만 적용됩니다.

호출의 **Remote execution** 탭을 열어 **Executions**를 확인하세요. 여기에는 지속 시간(긴 순서) 또는 시작 시간별로 정렬된 원격 액션이 표시됩니다. 각 원격 액션은 한 행으로 표시되며, 프로필 기준 시작 시점, 지속 시간, 그리고 대기, 입력 가져오기, 실행 및 출력 업로드 시간으로 구분된 막대가 페이지에서 가장 긴 액션에 맞춰 조정되어 표시됩니다. 각 단계의 지속 시간을 확인하려면 막 위에 마우스를 올리세요. 이 테이블은 업로드된 Bazel 프로필을 사용하며, 서버 단계를 동일한 프로필 스레드에서 명확하게 식별 가능한 액션과만 연결합니다.

타이밍이 누락된 경우 **Not recorded**로 표시되며, 0이 아닙니다. 오래된 프로필, 누락된 액션 간격, Bazel이 생략한 짧은 단계로 인해 원격 작업이 발생했더라도 테이블이 비어 있을 수 있습니다. 기록된 재시도는 각 액션 내에서 합산됩니다. 서버 메타데이터는 캐시된 결과를 설명할 수 있으므로, 이러한 타이밍은 새로운 실행의 증거나 청구 대상 사용량을 나타내지 않습니다. 클라이언트 입력 업로드와 로컬에서 실행된 출력의 업로드는 출력 업로드 시간에서 제외됩니다.

동일한 데이터는 `remote_execution=true`가 포함된 빌드 단계 REST 엔드포인트와 `list_bazel_build_steps` / `get_bazel_build_step` MCP 도구에서 사용할 수 있습니다. 타이밍은 프로필 단계와 함께 90일간 보관됩니다.

## 빌드 인사이트 {#build-insights}

기본적으로 `tuist bazel setup`는 Bazel의 Build Event Service도 구성하여 완료된 명령어가 **Invocations** 대시보드에 나타나도록 합니다. 대시보드에 표시되는 내용과 custom metadata를 첨부하는 방법은 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>를 참조하세요.

원격 캐시만 사용하고 빌드 이벤트 스트림을 전송하지 않으려면 다음 옵션을 사용하여 옵트아웃하세요:

```bash
tuist bazel setup --no-build-insights
```

## 연속 통합 {#continuous-integration}

<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link>에 있는 방법 중 하나로 CI를 인증한 후, 체크아웃 단계의 일부로 `tuist bazel setup`를 한 번 실행하여 `.bazelrc.tuist`가 러너에 적합한 리전을 반영하도록 하세요. 제공업체별 예제는 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>를 참조하세요.

## 데이터 보존 {#data-retention}

Tuist는 원격 캐시 관찰 데이터를 90일간 보관합니다. 전체 정책은 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>을 참조하세요.
