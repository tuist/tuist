---
{
  "title": "릴리스 채널",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist가 카나리, 릴리스 후보, 안정 채널을 통해 CLI를 배포하는 방식과 팀이 신뢰할 수 있는 버전에 고정하는 방법"
}
---

# 릴리스 채널 {#release-channels}

Tuist CLI는 서로 다른 안정성 보장을 제공하는 세 가지 채널을 통해 배포됩니다. 권장 설치 버전은 **stable**이며 변경 속도가 느립니다: 기능이 머지될 때마다 자동으로 업데이트되지 않으므로, 업그레이드 시 관련 없는 변경 사항을 일괄 적용하지 않아도 됩니다. 얼리 어답터는 **canary**에서 커밋 단위 빌드를 실행할 수 있으며, **release candidate** 채널을 사용하면 팀이 다음 마이너 버전을 stable로 승격하기 전에 충분히 검증할 수 있습니다.

## 현재 릴리스 {#live-release-status}

Stable 승격은 매주 월요일 06:00 UTC에 예정되어 있습니다. 예정된 승격이 성공하면 다음 release candidate가 `main`에서 생성되며, 이후 canary는 다음 마이너 버전으로 이동합니다. 패치와 백포트 포함 예정 윈도우 및 최근 릴리스는 <.localized_link href="/cli/release/calendar">릴리스 캘린더</.localized_link>를 참조하세요.

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 채널 {#the-channels}

| 채널 | 버전 형식 | 주기 | 기본적으로 해결됨? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (예: `4.201.0-canary.42`) | `main`의 모든 커밋 | 아니요 — 명시적 옵트인 필요 |
| Release candidate | `X.Y.0-rc.N` (예: `4.200.0-rc.1`) | 매주 월요일 `main`에서 생성, 약 1주 동안 검증 | 아니요 — 명시적 옵트인 필요 |
| Stable | `X.Y.Z` (예: `4.200.0`, `4.200.1`) | 검증이 완료되면 매주 월요일 승격 | **예** |

Canary 및 release candidate 빌드는 프리릴리스로 게시됩니다. Mise와 Homebrew 같은 도구는 `latest`, 기본 설치 또는 라인 고정 시 프리릴리스를 제외하므로, 명시적으로 요청하지 않으면 이러한 버전을 사용하지 않게 됩니다.

### Canary {#canary}

`main`의 모든 커밋은 canary를 게시합니다. Canary는 항상 **다음 미출시 마이너 버전**을 나타냅니다: 릴리스를 위해 라인이 생성되면 `main`는 다음 마이너 버전으로 이동합니다(예: `4.200.0-canary.42`에서 `4.201.0-canary.1`로). Canary는 가장 빠른 신호를 원하는 얼리 어답터나, 보고하거나 기여한 수정 사항이 stable에 도달하기 전에 예상대로 동작하는지 확인하려는 경우에 적합한 채널입니다.

### Release candidate {#release-candidate}

마이너 버전 출시 준비가 되면 해당 라인은 보호된 `releases/<major>.<minor>.x` 브랜치로 고정되고 `X.Y.0-rc.1`로 게시됩니다. 이 라인은 기능 추가가 중단되며, 중요한 수정 사항과 회귀 문제만 체리픽됩니다. 수용된 각 수정 사항은 RC 버전을 증가시킵니다(`-rc.2`, `-rc.3`, …). 검증 기간이 문제 없이 종료되면 라인은 stable로 승격됩니다.

### Stable {#stable}

Stable은 권장 채널이며 모든 문서가 지칭하는 채널입니다. Stable 마이너 버전(`X.Y.0`)은 release candidate가 문제 없이 검증을 마친 경우에만 게시되며, 새 기능이 `main`에 머지되더라도 **업데이트되지 않습니다**. Stable 라인의 패치(`X.Y.1`, `X.Y.2`, …)에는 백포트된 수정 사항만 포함되며, 새 기능은 절대 포함되지 않습니다.

## 버전 선택 {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> 사용(권장):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew를 사용할 경우 `brew install --formula tuist`는 항상 최신 stable 버전을 설치하며, 프리릴리스는 포뮬러를 통해 배포되지 않습니다.

## 권장 전략 {#recommended-strategy}

1. **Stable 라인에 고정**하세요. 예를 들어 `tuist@4.200`와 같이 지정합니다. 해당 라인은 백포트된 수정 사항만 받고 새 기능은 추가되지 않으므로 일상적인 업그레이드의 위험이 낮습니다.
2. **새 기능을 의도적으로 도입하세요.** 다음 마이너 버전 준비가 되면 release candidate 채널에서 검증한 후, 고정을 새로운 stable 라인으로 이동하세요.
3. 가장 빠른 신호를 원하는 얼리 어답터라면 중요하지 않은 환경에서 **canary를 시도**해 보세요.

## 지원 및 백포트 {#support-and-backports}

두 개의 stable 라인이 언제든지 활발히 유지 관리됩니다:

| 라인 | 수신 내용 |
| --- | --- |
| 현재 (`X.Y.x`) | 회귀 문제 및 보안 수정 사항 |
| 이전 (`X.(Y-1).x`) | 중요 및 보안 수정 사항만 |
| 구버전 | 없음 — 유지 관리 중인 라인으로 업그레이드하세요 |

수정 사항은 먼저 `main`(canary)에 적용됩니다. 회귀 문제와 보안 수정 사항은 현재 stable 라인에 백포트되며, 이전 라인은 중요 및 보안 수정 사항만 받습니다. 다른 버그 수정 사항은 백포트되지 않으며 다음 마이너 버전과 함께 배포됩니다. 새 라인이 stable로 승격되면 기존 current 라인은 "previous"가 되고, 기존 "previous" 라인은 백포트를 받지 않게 됩니다.

채널과 무관하게 Tuist 서버는 지난 3개월 동안 릴리스된 모든 CLI와 <.localized_link href="/cli/compatibility">호환</.localized_link> 상태를 유지하므로, 해당 기간 내에 업그레이드하는 한 stable 라인에 고정해도 지원 범위에서 벗어나지 않습니다.
