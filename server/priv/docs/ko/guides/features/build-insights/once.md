---
{
  "title": "Once 빌드 인사이트",
  "titleTemplate": ":title · 빌드 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Once 실행의 동작, 지속 시간, 실패, 캐시 결정을 실시간으로 확인하세요."
}
---
# Once 빌드 인사이트 {#once-build-insights}

Once는 실행 중에 Tuist로 런 데이터를 스트리밍하므로, 최종 CI 로그를 기다리지 않고도 진행 상황을 추적할 수 있습니다. 런 시작 시 출력되는 대시보드 링크를 열어 그래프, 액션 상태 및 캐시 결정을 확인하세요.

> [!IMPORTANT]
> **필수 조건**
>
> - <.localized_link href="/guides/get-started/once-project">Once 시작하기</.localized_link>를 완료하고 Once를 실행하는 머신을 인증하세요.

## 빌드 보고하기 {#report-your-builds}

기존 Once 명령어를 계속 사용하세요:

```bash
once build MyApplication
```

실시간 보고는 최선을 다해 제공됩니다. 보고 엔드포인트가 사용 불가능하거나 세션이 만료되어도 빌드가 실패하지 않습니다. 세션이 만료되면 `once auth login --provider tuist`으로 다시 로그인하세요.

## 대시보드 표시 내용 {#what-the-dashboard-shows}

**빌드**와 **빌드 런**을 사용하여 시간, 브랜치, 로컬 또는 CI 환경 전반에 걸쳐 런을 비교하세요. 각 런에는 다음 정보가 포함될 수 있습니다:

- 요청된 명령어, 상태, 시작 시간 및 소요 시간.
- Once 버전과 보고된 호스트 정보.
- 액션과 해당 의존성, 상태, 소요 시간 및 캐시 결과.
- 보고된 액션 오류.
- 클라이언트에서 보고되는 경우 Git 브랜치, 커밋 및 CI 컨텍스트.

실패하거나 느린 작업을 찾기 위해 액션을 검색하고 필터링하세요. 보고된 액션 이름과 소스 파일은 작업을 코드와 연결하는 데 도움이 되며, 이전 클라이언트는 더 적은 세부 정보를 제공할 수 있습니다. 캐시되거나 건너뛴 액션은 실행된 작업이 아니며, 타이밍 정보가 없는 것은 실행 시간이 0인 것을 의미하지 않습니다.

Tuist는 현재 Once의 원시 액션 로그 스트림을 수집하지 않습니다. 전체 프로세스 출력을 위해 CI 로그를 보관하세요. 런 요약과 구조화된 오류는 해당 로그를 대체하지 않습니다.

**캐시** 뷰는 액션 결정과 콘텐츠 객체 전송을 구분합니다. 캐시 활동을 해석하는 방법은 <.localized_link href="/guides/features/cache/once">Once 캐시</.localized_link>를 참조하세요.

## 테스트 {#tests}

테스트 명령어도 Once 런을 생성합니다. 보고된 스위트와 케이스는 **테스트** 아래에 표시되며, 호스팅된 샤드는 추가로 결합된 테스트 런을 게시합니다. <.localized_link href="/guides/features/test-insights/once">Once 테스트 인사이트</.localized_link>를 참조하세요.

## 코딩 에이전트와 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol 도구</.localized_link>를 사용하면 에이전트가 Once 런 목록을 조회하고 런의 액션 및 캐시 합계를 읽을 수 있습니다. 동일한 읽기 작업은 HTTP API를 통해서도 가능합니다.

최종 확정된 Once 빌드 건강도 지표를 위해 <.localized_link href="/guides/integrations/grafana">Grafana 통합</.localized_link>을 사용하세요. Once는 현재 경과된 캐시 시간 절감량을 보고하지 않으므로, 해당 측정값은 0이 아닌 사용 불가 상태로 유지됩니다.
