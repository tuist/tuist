---
{
  "title": "Elixir Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track how long your Elixir project takes to compile with Mix, its warnings, and the files that hold your builds back."
}
---
# Elixir 빌드 인사이트 {#elixir-build-insights}

Tuist의 Hex 패키지는 빌드 분석 데이터를 Tuist로 전송할 수 있습니다. 빌드 시간, 파일 간 의존성 그래프, 그리고 시간이 지남에 따라 이들이 어떻게 변화하는지를 통해 빌드 그래프를 최적화하고 컴파일이 수행되는 환경에서 사용 가능한 모든 코어를 최대한 활용할 수 있습니다.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixir 시작하기</.localized_link>를 완료하세요

## 빌드 보고하기 {#report-your-builds}

공유 설정은 컴파일 통합 기능을 설치합니다. 기존에 사용하던 명령어를 계속 사용하세요:

```bash
mix compile
```

이 통합 기능은 `mix compile` 및 `mix test` 또는 `mix phx.server`와 같은 다른 작업이 트리거하는 모든 컴파일을 포함합니다. 수행할 작업이 없는 컴파일은 보고되지 않으므로, 대시보드에는 실제로 작업이 수행된 빌드만 표시됩니다.

## 액터 클레임 보고하기 {#report-actor-claim}

Mix 빌드 및 테스트 보고 요청은 라벨을 명시적으로 구성했을 때만 선택적 `x-tuist-actor-id` 헤더를 포함합니다. `TUIST_ACTOR_ID`를 조직 범위 라벨로 설정하거나 프로젝트의 `tuist` 구성에 `actor_id: "developer-label"`를 추가하세요. 해결 순서는 환경 변수, 런타임 `:actor_id` 옵션, 프로젝트 구성 순으로 우선순위가 적용됩니다. 기본적으로 라벨은 전송되지 않으며, 패키지는 운영 체제 사용자 이름을 감지하지 않습니다. 고정된 프로젝트 라벨은 해당 구성을 사용하는 모든 사람에게 적용됩니다. 비어 있거나 유효하지 않은 재정의는 폴백 대신 클레임을 생략하며, 이는 자격 증명 기반 검증된 신원을 제거하지 않습니다. custom proxy가 익숙하지 않은 헤더를 거부하는 경우, `TUIST_ACTOR_ID=""`로 옵트아웃하세요.

식별자는 공백이 아닌 인쇄 가능한 ASCII 문자 1~128바이트여야 합니다. 유효하지 않은 재정의는 폴백 없이 생략됩니다. 검증된 개별 자격 증명이 우선하며, 기타 클라이언트가 보고한 식별자는 **검증되지 않음**으로 표시되며, 액세스를 승인하지 않고 사용자와 자동으로 연결되지 않습니다. 프로젝트의 보고서를 볼 수 있는 사람은 누구나 이러한 식별자를 볼 수 있으며, 프로젝트가 공개된 경우 공개 뷰어도 포함되고 데이터 내보내기에 포함되므로 비밀 정보를 포함하지 마세요. 이전 서버는 선택적 헤더를 무시하고, 새 서버는 헤더가 없는 이전 클라이언트를 허용합니다. 식별자가 없는 새로운 공유 토큰 보고서는 게시 조직 대신 **알 수 없음**으로 표시되며, 과거 보고서는 기존 귀속 정보를 유지합니다. 빌드 및 테스트 보고는 기본적으로 인증이 필요합니다. 자체 호스팅 설치는 아래 설명대로 자격 증명 없는 보고를 명시적으로 활성화할 수 있습니다.

## 프라이빗 네트워크에서의 자격 증명 없는 보고 {#network-trusted-publishing}

운영자가 인스턴스에서 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`를 구성하고 <.localized_link href="/guides/server/self-host/server#network-trusted-access">자체 호스팅 가이드</.localized_link>에 설명된 대로 재시작한 후, 대상 환경을 구성하세요. SDK는 자격 증명이 없을 때 인스턴스가 자격 증명 없는 보고를 허용하는지 자동으로 발견합니다. 인스턴스 설정은 지원되는 모든 프로젝트를 포함하며 대시보드 토글이 없습니다:

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

자격 증명이 실제로 없고 검색을 통해 서버가 이를 허용함이 확인되면, `mix tuist.compile` 및 `mix tuist.test`는 로그인 없이 구조화된 보고서를 게시합니다. 클라이언트 플래그나 프로젝트 옵트인이 필요하지 않습니다. 제공된 CI OIDC 신원을 포함한 현재 자격 증명은 사용되거나 거부되며, 서명 없는 보고로 다운그레이드하기 위해 무시되지 않습니다. 공백만 포함된 `TUIST_TOKEN`는 오류입니다. 빈 `TUIST_TOKEN`는 유효한 저장된 자격 증명이나 제공된 OIDC로 폴백할 수 있으며, 만료된 저장된 자격 증명도 제공된 OIDC로 폴백할 수 있습니다. 두 경로 모두 인증 상태를 유지하며 서명 없는 보고를 활성화하지 않습니다. 사용할 수 없는 자격 증명은 보존되며, 인증된 폴백이 성공하지 않으면 실패합니다. 자격 증명 없는 클라이언트를 업그레이드하기 전에 모든 서버 복제본을 검색 가능 버전으로 업그레이드하세요. 검색 기능이 없는 이전 서버, 비활성화된 인스턴스, 검색 실패는 여전히 인증이 필요합니다.

서명되지 않은 실행은 신뢰할 수 있는 불안정성, 격리, 커버리지 또는 선택적 실행 증거가 아닌 텔레메트리입니다. 샤드 계획, 빌드 아카이브, 커버리지/아티팩트 엔드포인트는 여전히 자격 증명이 필요합니다. 구성된 액터 클레임을 생략하려면 `TUIST_ACTOR_ID=""`를 독립적으로 설정하세요. 검증된 자격 증명 신원은 영향을 받지 않습니다.

## 추적 내용 {#what-is-tracked}

각 빌드에 대해 패키지는 다음을 수집합니다:
- 지속 시간, 성공 여부, 그리고 실행된 Elixir, Erlang/OTP 및 Mix 환경
- 파일과 줄 번호가 포함된 모든 경고 및 오류
- 각 파일의 컴파일 소요 시간과 정의된 모듈
- 각 파일이 의존하는 파일들과 컴파일 타임에만 필요한지 런타임에만 필요한지 여부
- 파일 컴파일 외에 빌드가 수행한 작업(예: 타입 체크, 디스크 쓰기, 기타 Mix 컴파일러)
- 빌드 동안 머신의 프로세서, 메모리, 네트워크 및 디스크 사용량
- 브랜치와 커밋, 그리고 지속적 통합 환경에서는 제공자와 실행 정보

## 빌드 속도를 저하시키는 요소 찾기 {#find-what-slows-a-build-down}

대시보드의 **빌드 → 빌드 실행**에서 빌드를 엽니다. 빌드, 진단 카운트 및 의존성 캐시 요약은 `tuist build mix list` 및 `tuist build mix show`, `GET /api/projects/{account_handle}/{project_handle}/mix/builds`, 그리고 `list_mix_builds` 및 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 도구</.localized_link>를 통해서도 이용할 수 있습니다.

**개요** 탭에는 빌드가 컴파일한 파일들이 나열됩니다. 모듈별로 그룹화하거나 검색하고, 다음 기준으로 정렬할 수 있습니다:
- **컴파일 지속 시간**: 자체적으로 느린 파일을 찾습니다.
- **컴파일 타임 의존자**: 이 파일이 컴파일될 때까지 컴파일할 수 없는 파일의 수입니다. 의존자가 많은 느린 파일은 나머지 빌드를 지연시키며, 이를 변경하면 모든 의존 파일이 다시 컴파일됩니다.
- **컴파일 타임 의존성**: 이 파일이 기다리는 파일의 수입니다.

![Phoenix 애플리케이션의 Mix 빌드 개요](/images/guides/features/elixir/build.png)

**타임라인** 탭은 시간 경과에 따른 동일한 빌드를 보여줍니다: 어떤 파일이 병렬로 컴파일되었는지, 빌드가 타입 체크와 디스크 쓰기를 어디에서 수행했는지, 그리고 각 순간에 머신의 상태가 어떠했는지. 단일 바가 있는 구간은 빌드가 사용 가능한 코어를 활용하지 못한 구간입니다.

![Phoenix 애플리케이션의 전체 Mix 빌드 타임라인](/images/guides/features/elixir/build-timeline.png)

**경고** 및 **오류** 탭에는 빌드의 진단 정보가 나열됩니다.

## 사용자 정의 메타데이터 {#custom-metadata}

Mix 빌드에 태그와 키-값 데이터를 첨부하여 다양한 팀, 하드웨어 또는 워크플로우의 실행을 구분하세요. 둘 다 각 빌드의 상세 페이지에 표시됩니다.

환경 변수로 메타데이터를 설정하세요:

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

`mix.exs`에서도 메타데이터를 구성할 수 있습니다:

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

두 위치의 태그는 결합됩니다. 동일한 키가 두 곳 모두에 구성된 경우 환경 변수의 값이 우선합니다.

태그는 문자, 숫자, 하이픈 및 밑줄만 포함해야 합니다. 빌드에는 최대 50개의 태그를 사용할 수 있으며, 각 태그는 최대 50자의 문자를 포함할 수 있습니다. 빌드에는 최대 20개의 키-값 항목을 가질 수 있으며, 각 키는 최대 50자, 각 값은 최대 500자를 포함할 수 있습니다. 이는 Xcode 빌드 메타데이터에 사용되는 서버 측 제한과 동일합니다. 패키지는 보고서를 전송하기 전에 유효하지 않은 태그와 크기가 너무 크거나 비어 있는 메타데이터 항목을 건너뛰므로, 잘못된 구성으로 인해 나머지 빌드 인사이트 보고서가 저장되지 않는 것을 방지할 수 없습니다. 태그 제약 조건을 충족하지 않는 값에는 키-값 메타데이터를 사용하세요.

사용자 정의 메타데이터는 테스트 실행이 아닌 빌드에 첨부됩니다.

사용자 정의 메타데이터는 대시보드에서 프로젝트 구성원에게 표시됩니다. 자격 증명, 액세스 토큰 또는 기타 민감한 데이터에는 사용하지 마세요. Tuist는 이 메타데이터를 포함한 Mix 빌드 데이터를 90일 동안 보관합니다. 자세한 내용은 <.localized_link href="/guides/server/data-retention">데이터 보존 정책</.localized_link>을 참조하세요.

## 문제 해결 {#troubleshooting}

보고서는 빌드 결과를 변경하지 않습니다: 보고서를 보낼 수 없는 경우 빌드는 평소대로 완료되며 아무 것도 출력되지 않습니다. 보고서가 전송되지 않은 이유를 확인하려면 `TUIST_DEBUG=1`을 설정하세요:

```bash
TUIST_DEBUG=1 mix compile --force
```
