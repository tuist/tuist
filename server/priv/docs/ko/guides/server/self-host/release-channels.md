---
{
  "title": "릴리스 채널",
  "titleTemplate": ":title | 셀프 호스팅 | 서버 | 가이드 | Tuist",
  "description": "Tuist가 카나리, 릴리스 후보, 안정 채널에 걸쳐 서버 및 Kura Docker 이미지를 어떻게 배포하는지, 그리고 신뢰할 수 있는 배포 버전을 고정하는 방법을 설명합니다."
}
---

# 릴리스 채널 {#release-channels}

Tuist 서버와 Kura 캐시 서버는 서로 다른 안정성 보장을 제공하는 세 가지 GHCR 이미지 채널을 통해 배포됩니다. 권장 설치 버전은 **stable**이며 주 단위로 업데이트됩니다: 기능이 `main`에 병합될 때마다 자동으로 진행되지 않으므로, 업그레이드 시 관련 없는 변경 사항을 일괄적으로 수용할 필요가 없습니다. 얼리 어답터는 여전히 **canary**에서 커밋 단위 빌드를 실행할 수 있으며, **release candidate** 채널을 사용하면 upcoming 라인이 stable이 되기 전에 미리 검증할 수 있습니다.

서버와 Kura는 동일한 주간 릴리스 주기를 따르며, 둘 다 [Tuist CLI의 릴리스 일정](/en/cli/release-channels)과 동기화되어 동작합니다.

## 채널 {#the-channels}

| 채널 | 버전 형식 | 주기 | `:latest` 이동 여부? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (예: `1.351.0-canary.5`) | `main`로의 모든 커밋 | 아니요, 명시적 옵트인 필요 |
| Release candidate | `X.Y.0-rc.N` (예: `1.351.0-rc.1`) | 매주 월요일 `main`에서 분기, 약 1주일간 검증 | 아니요, 명시적 옵트인 필요 |
| Stable | `X.Y.Z` (예: `1.350.2`, `1.351.0`) | 깨끗한 검증 후 매주 월요일 승격 | **예** |

Canary 및 release candidate 빌드는 GitHub 프리릴리스로 게시됩니다. `:latest` 해결 시 프리릴리스를 제외하는 도구는 이를 건너뛰므로, 명시적으로 요청하지 않는 한 이러한 버전에 도달하지 않습니다.

### Canary {#canary}

`main`로의 모든 커밋은 canary 이미지를 게시합니다. Canary는 항상 **다음 출시되지 않은 마이너 버전**을 나타냅니다: 릴리스용 라인이 분기되면 `main`는 다음 마이너 버전으로 진행됩니다(예: `1.350.0-canary.42`에서 `1.351.0-canary.1`로). Canary는 프로덕션을 미러링하고 회귀 문제에 대한 가장 빠른 신호를 제공하거나, 보고한 수정 사항이 stable에 도달하기 전에 예상대로 동작하는지 확인하려는 스테이징 환경에 적합한 채널입니다.

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

마이너 버전 출시 준비가 되면 해당 라인은 보호된 `releases/server-<major>.<minor>.x` (또는 `releases/kura-<major>.<minor>.x`) 브랜치로 고정되고 `X.Y.0-rc.1`로 게시됩니다. 이 라인은 기능 추가가 중단되며, 중요한 수정 사항과 회귀 문제만 체리픽되어 적용되고, 각 수용된 수정 사항은 release candidate를 반복합니다(`-rc.2`, `-rc.3` 등). 검증 기간이 깔끔하게 종료되면 해당 라인은 다음 주 월요일에 stable로 승격됩니다.

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable은 권장 채널이며 모든 문서가 참조하는 채널입니다. Stable 마이너 버전(`X.Y.0`)은 release candidate가 깔끔하게 검증된 경우에만 게시되며, 새로운 기능이 `main`에 병합되더라도 **진행되지 않습니다**. Stable 라인의 패치 버전(`X.Y.1`, `X.Y.2` 등)은 백포트된 수정 사항만 포함하며 새로운 기능은 절대 포함되지 않습니다. `:latest`는 stable 승격 시에만 이동합니다.

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 월요일 릴리스 열차 {#the-monday-train}

매주 월요일 UTC 06:00에 세 구성 요소의 릴리스 열차가 동기화되어 실행됩니다:

1. **UTC 06:00** — 승격 작업이 실행됩니다. 각 작업은 아직 stable이 아닌 최신 release candidate 라인을 승격시키며(일반적으로 전 주 월요일에 분기된 라인), 해당 라인이 없으면 아무 작업도 수행하지 않습니다.
2. **각 승격 완료 후** — release candidate 작업이 `main`에서 다음 라인을 분기하므로, 새로 분기된 라인은 동일한 실행에서 승격되지 않습니다.

승격 실패 시 분기가 보류됩니다: 최신 stable 위의 가장 높은 release candidate 라인만 선택되므로, 실패 상태에서 다음 라인을 분기하면 배포되지 않은 라인이 고립될 수 있습니다. 다음 주 월요일에 보류된 라인이 자동으로 재시도됩니다.

## 채널 고정 {#pinning-a-channel}

배포 매니페스트, Helm 값 또는 Docker Compose 파일에서 원하는 특정 태그를 고정하세요. 예시(Helm 차트 사용):

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

`:latest`는 `ghcr.io/tuist/tuist`와 `ghcr.io/tuist/kura` 모두에서 최신 stable 버전을 추적하며, 월요일 승격 시에만 이동합니다. `:latest`를 고정하면 태그를 업데이트하지 않고도 주간 stable 주기를 따를 수 있으며, 특정 버전을 고정하면 업그레이드 시기를 완전히 제어할 수 있습니다.

## 권장 전략 {#recommended-strategy}

채널은 "최신 수정 사항 가져오기"와 "최신 기능 가져오기"를 분리할 수 있도록 존재합니다. 안전하고 노력이 적은 기본 전략은 다음과 같습니다:

1. **프로덕션을 stable 마이너 라인에 고정**하세요. 예를 들어 `ghcr.io/tuist/tuist:1.351`입니다. 해당 라인은 백포트된 수정 사항만 수신하며 새로운 기능은 포함되지 않으므로 일상적인 업그레이드의 위험이 낮습니다. 다음 마이너 버전을 도입할 준비가 되면 고정 버전을 업데이트하세요.
2. **스테이징 환경을 canary 또는 특정 release candidate 태그에서 실행**하세요. 스테이징은 사용자에게 도달할 수 있는 회귀 문제를 사전에 발견하며, `main`에 가까울수록 더早く 문제를 찾을 수 있습니다. 현재 release candidate 라인에서 스테이징 환경을 운영하는 것은 좋은 중간 지점입니다: 다음 주 월요일에 stable이 될 정확한 바이트를 검증할 수 있습니다.
3. **실제로 배포된 내용을 확인하려면 [Server changelog](/changelog)를 참고**하세요. 모든 stable 승격은 포함된 풀 리퀘스트 목록과 함께 여기에 공지됩니다.

새로운 기능이 stable이 되면 자동으로 프로덕션에 배포되기를 원한다면, 프로덕션을 `:latest`로 유지하세요. 태그는 매주 월요일 아침에 업데이트되므로 이에 맞춰 배포 일정을 조정해야 합니다.

## 백포트 {#backports}

두 개의 stable 서버(및 Kura) 라인이 항상 활발히 유지됩니다: 현재 라인은 회귀 문제와 보안 수정 사항을 백포트 풀 리퀘스트로 수용하며, 이전 라인은 중요 및 보안 수정 사항만 수용합니다. 더 오래된 라인은 백포트되지 않으므로 수정 사항을 받으려면 유지 중인 라인으로 업그레이드하세요. 새 라인이 stable로 승격되면 기존 current 라인은 "previous"가 되며, 기존 "previous" 라인은 백포트 수신을 중단합니다.

백포트는 필요에 따라 `X.Y.(Z+1)` 패치 릴리스로 분기됩니다. 이들은 `:latest`를 이동시키지 않습니다.
