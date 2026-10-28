---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir 테스트 인사이트 {#elixir-test-insights}

Tuist의 Hex 패키지는 각 테스트 실행 후 Elixir 프로젝트의 테스트 결과를 업로드하여, Tuist 대시보드에서 직접 테스트 성능과 불안정한 테스트(flaky tests)를 확인할 수 있게 해줍니다.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixir 시작하기</.localized_link> 완료하기

## 테스트 실행 보고하기 {#report-your-test-runs}

공유 설정은 테스트 통합 기능을 설치합니다. 동일한 인수, 출력 및 종료 코드로 `mix test`를 계속 사용하세요:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist는 실행이 완료되면 결과를 보고하므로 추가적인 테스트 별칭이 필요하지 않습니다.

Tuist 대시보드에서 테스트 인사이트에 접근하고 시간이 지남에 따라 어떻게 변화하는지 확인할 수 있습니다:

![Phoenix 애플리케이션의 테스트 대시보드](/images/guides/features/elixir/tests-dashboard.png)

## 추적 대상 {#what-is-tracked}

이 패키지는 ExUnit의 결과를 수집하며, 다음을 포함합니다:
- 개별 테스트의 통과/실패 상태 및 소요 시간
- 각 테스트가 속한 모듈과 `describe` 블록
- 각 실패의 메시지 및 위치
- 실행 간 불안정한 테스트(flaky test) 감지
- 브랜치와 커밋, 그리고 지속적 통합(CI) 환경에서는 제공자와 실행 정보
- 지속적 통합(CI) 환경에서는 체크아웃의 [Git 히스토리](#git-history)

Doctest는 다른 테스트와 마찬가지로 보고됩니다.

> [!NOTE]
> 이 패키지는 이미 사용 중인 포맷터 옆에 추가되는 ExUnit 포맷터를 통해 보고합니다. 명령줄에서 `--formatter`를 전달하면 Mix가 전체 목록을 대체하므로 실행이 보고되지 않으며, 작업이 이에 대해 경고합니다.

### Git 히스토리 {#git-history}

지속적 통합(CI) 환경에서는 이 패키지가 체크아웃의 커밋 히스토리도 업로드합니다: 커밋 SHA, 부모 커밋, 커밋 날짜, 그리고 실행과 풀 리퀘스트의 기본 브랜치가 있던 브랜치입니다. 파일 내용, 커밋 메시지 또는 작성자는 업로드되지 않습니다. 이는 Tuist가 어떤 커밋이 기본 브랜치에 병합되었는지(예: 머지 큐에서 테스트된 커밋) 알 수 있게 해줍니다. 이 패키지는 체크아웃에 이미 있는 히스토리를 읽으며, 체크아웃에 기본 브랜치가 없는 경우 원격 저장소에 최신 커밋을 요청합니다(`git ls-remote`). 코드 커버리지(`--cover`) 외부에서는 히스토리를 가져오지 않습니다.

| 변수 | 효과 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 히스토리를 읽거나 업로드하지 않습니다. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 원격 저장소에 접속하지 않고 체크아웃만 읽습니다. |

## 문제 해결 {#troubleshooting}

보고 기능은 테스트 결과에 영향을 주지 않습니다: 보고서를 보낼 수 없는 경우, 실행은 평소대로 종료되며 아무것도 출력되지 않습니다. 보고서가 전송되지 않은 이유를 확인하려면 `TUIST_DEBUG=1`를 설정하세요:

```bash
TUIST_DEBUG=1 mix test
```
