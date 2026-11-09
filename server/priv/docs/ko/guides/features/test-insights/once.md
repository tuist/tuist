---
{
  "title": "Once 테스트 인사이트",
  "titleTemplate": ":title · 테스트 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 대시보드에서 Once 테스트 스위트, 개별 결과, 실패 및 소요 시간을 확인하세요."
}
---
# Once 테스트 인사이트 {#once-test-insights}

Once는 테스트 결과를 Tuist에 보고하므로, 개별 워커의 리포트를 수집하지 않고도 로컬 및 CI 실행 전체에서 테스트 스위트의 진행 상황을 추적하고, 실패를 조사하며, 느린 테스트를 찾을 수 있습니다.

> [!IMPORTANT]
> **요구 사항**
>
> - <.localized_link href="/guides/get-started/once-project">Once 시작하기</.localized_link>를 완료하세요.
> - 구조화된 결과를 보고하는 테스트 타겟을 사용하세요. 제공되는 세부 정보는 타겟 종류와 테스트 러너에 따라 다릅니다.

## 테스트 실행 보고하기 {#report-your-test-runs}

전체 스위트를 실행하거나 타겟을 선택하세요:

```bash
once test
once test MyTests
```

Once는 네이티브 테스트 이벤트를 스트리밍하고 완료된 결과를 Tuist의 공유 테스트 모델로 게시합니다. **테스트**와 **테스트 실행**에서 실행 기록을 확인할 수 있으며, 개별 케이스에도 공유된 테스트 이력이 있습니다. <.localized_link href="/guides/features/test-sharding/once">호스팅된 샤딩 실행</.localized_link>은 진단 이벤트 스트림을 다시 집계하는 대신, 각 워커당 하나의 리포트를 결합된 실행으로 게시합니다.

## 추적 대상 {#what-is-tracked}

- 보고된 테스트 타겟, 스위트 및 개별 케이스.
- 러너가 제공하는 경우 지속 시간과 함께 통과, 실패 및 건너뜀 결과.
- 호스팅된 샤딩 리포트에서 러너가 제공하는 실패 메시지.
- 테스트가 실패한 후 나중에 통과할 때의 정렬된 재시도 시도 횟수와 불안정한 테스트 결과.
- Once가 제공하는 브랜치, 커밋 및 CI 컨텍스트.

테스트 식별에는 네이티브 타겟, 스위트 및 케이스 이름을 사용합니다. 샤딩 배치 ID는 스케줄링 단위이며 테스트 이름이 아닙니다.

일반적인 `once test` 보고는 결과와 재시도 시도를 보존하지만 현재 공유 테스트 이력에 실패 메시지는 포함되지 않습니다. 호스팅된 샤딩 리포트에는 실패 메시지를 포함할 수 있지만, 두 보고 경로 모두 소스 위치를 제공하지 않습니다. Tuist에서 사용할 수 없는 진단 정보를 위해 CI 로그를 보관하세요.

모든 테스트 타겟이 동일한 세부 정보를 제공하는 것은 아닙니다. 일부 러너는 개별 케이스를 보고하고, 다른 러너는 요약만 보고합니다. 정확한 파일 또는 케이스 실행은 별도의 기능입니다. 케이스별 분석이나 세분화된 스케줄링에 의존하기 전에 [Once의 테스트 생태계 지원 범위](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage)를 확인하세요.

## 불안정한 테스트 {#flaky-tests}

Tuist는 보고된 시도 횟수와 CI 이력을 사용하여 일관성 없는 결과를 식별합니다. 시도를 보고하는 것이 재시도를 활성화하는 것과 같지는 않습니다. 재시도를 지원하는 러너에서 재시도를 구성하세요. 감지 및 현재 격리 범위에 대해서는 <.localized_link href="/guides/features/test-insights/flaky-tests/once">Once 불안정한 테스트</.localized_link>를 참조하세요.

## 선택 및 코드 커버리지 {#selection-and-code-coverage}

Once는 `--changed-path`를 사용하여 로컬 그래프에서 테스트를 보수적으로 선택할 수 있습니다. 이는 Once 자체의 선택이며, Tuist의 호스팅된 커버리지 기반 테스트 선택이 아닙니다:

```bash
once test --changed-path src/library.rs
```

네이티브 Once 보고는 현재 코드 커버리지를 Tuist에 업로드하지 않습니다. 성공적인 테스트 리포트나 샤드 계획은 코드 커버리지 대시보드를 채우지 않습니다.

## 문제 해결 {#troubleshooting}

실행이 누락된 경우, 유효한 캐시 공급자가 Tuist 프로젝트를 지정하는지 확인하고 `once auth login --provider tuist`로 다시 인증하세요. 라이브 보고는 최선을 다해 제공되며, 보고 서비스를 사용할 수 없을 때 이미 성공한 테스트 명령을 실패로 전환하지 않습니다.

실행 요약과 구조화된 테스트 실패는 전체 프로세스 로그가 아닙니다. 이 서버는 현재 Once의 원본 액션 로그 스트림을 수집하지 않으므로, 구조화된 결과에 포함되지 않는 출력을 위해 CI 로그를 보관하세요.
