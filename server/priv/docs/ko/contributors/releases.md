---
{
  "title": "릴리스",
  "titleTemplate": ":title | 기여자 | Tuist",
  "description": "Tuist의 지속적 릴리스 프로세스가 어떻게 작동하는지 알아보세요"
}
---
# 릴리스

변경 사항이 main 브랜치에 병합되면 Tuist는 새 버전을 자동으로 게시합니다. CLI, 서버, Kura 캐시 서버는 모두 릴리스 채널(카나리, 릴리스 후보, 안정)을 통해 배포되므로 권장 설치 버전은 안정적이고 변경 주기가 느립니다. 릴리스 후보를 생성하고 이를 안정으로 승격하는 것은 의도적인 주간 단계입니다. 앱은 지속적으로 릴리스됩니다(iOS 앱은 TestFlight에만 지속적으로 배포되며, 자세한 내용은 [여기](#app-store-release) 참조).

## 개요

다음 주요 구성 요소를 릴리스합니다:
- **Tuist CLI** - 카나리, 릴리스 후보, 안정 [채널](#release-channels)을 통해 배포되는 명령줄 도구
- **Tuist Server** - CLI와 동일한 채널 모델을 통해 배포되는 백엔드 서비스
- **Kura** - CLI와 동일한 채널 모델을 통해 배포되는 캐시 서버
- **Tuist App** - macOS 및 iOS 앱, 지속적으로 릴리스됨(iOS 앱은 TestFlight에만 지속적으로 배포되며, 자세한 내용은 [여기](#app-store-release) 참조)

`main`에 대한 모든 푸시는 CLI, 서버, Kura용 카나리 사전 릴리스를 게시합니다. 각 구성 요소의 안정 릴리스는 관리자가 충분히 검증된 릴리스 후보를 승격할 때만 생성되며, 주간 일정에 따라 세 가지 릴리스 열차가 동시에 실행됩니다([릴리스 채널](#release-channels) 참조). 앱은 `main`에 대한 모든 푸시에 대해 안정 버전을 게시합니다.

## 작동 방식

### 1. 커밋 규칙

커밋 메시지를 구조화하기 위해 [Conventional Commits](https://www.conventionalcommits.org/)를 사용합니다. 이를 통해 도구가 변경 사항의 성격을 이해하고, 버전 상승을 결정하며, 적절한 변경 로그를 생성할 수 있습니다.

형식: `type(scope): description`

#### 커밋 유형과 영향

| 유형 | 설명 | 버전 영향 | 예시 |
|------|-------------|----------------|---------|
| `feat` | 새로운 기능 또는 능력 | 마이너 버전 상승(x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 버그 수정 | 패치 버전 상승(x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 문서 변경 | 릴리스 없음 | `docs: update installation guide` |
| `style` | 코드 스타일 변경 | 릴리스 없음 | `style: format code with swiftformat` |
| `refactor` | 코드 리팩토링 | 릴리스 없음 | `refactor(server): simplify auth logic` |
| `perf` | 성능 개선 | 패치 버전 상승 | `perf(cli): optimize dependency resolution` |
| `test` | 테스트 추가/변경 | 릴리스 없음 | `test: add unit tests for cache` |
| `chore` | 유지보수 작업 | 릴리스 없음 | `chore: update dependencies` |
| `ci` | CI/CD 변경 | 릴리스 없음 | `ci: add workflow for releases` |

CLI의 경우, 이러한 버전 상승은 카나리 버전과 변경 로그 그룹화를 결정합니다. 안정 CLI 버전은 마이너 라인(`X.Y.0`)은 수동으로 생성되며, 안정 패치(`X.Y.Z`)는 백포트에서만 제공되므로 `feat` 또는 `fix`는 즉시 안정 릴리스로 제공되지 않고 아래의 채널 흐름을 통해 CLI 사용자에게 전달됩니다.

#### 주요 변경 사항

주요 변경 사항은 메이저 버전 상승(X.0.0)을 유발하며 커밋 본문에 표시해야 합니다:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 변경 감지

각 구성 요소는 [git cliff](https://git-cliff.org/)를 사용하여 다음 작업을 수행합니다:
- 마지막 릴리스 이후의 커밋 분석
- 범위별 커밋 필터링(cli, app, server)
- 릴리스 가능한 변경 사항 여부 결정
- 변경 로그 자동 생성

### 3. 릴리스 파이프라인

릴리스 가능한 변경 사항이 감지되면:

1. **버전 계산**: 파이프라인이 다음 버전 번호를 결정합니다
2. **변경 로그 생성**: git cliff가 커밋 메시지에서 변경 로그를 생성합니다
3. **빌드 프로세스**: 구성 요소가 빌드되고 테스트됩니다
4. **아티팩트 생성**: CLI 번들, 체크섬 및 `tuist --experimental-dump-help`에서 생성된 `tuist.spec.json` CLI 사양과 같은 릴리스 전용 자산이 생성됩니다
5. **릴리스 생성**: 아티팩트가 포함된 GitHub 릴리스가 생성됩니다
6. **배포**: 업데이트가 패키지 관리자로 푸시됩니다(예: CLI용 Homebrew)

앱의 경우 모든 병합 시 안정 릴리스가 생성됩니다. CLI, 서버 및 Kura의 경우 이 동일한 자동 파이프라인은 **카나리** 사전 릴리스만 생성하며, 릴리스 후보 및 안정 릴리스는 주간 릴리스 열차에서 생성됩니다([릴리스 채널](#release-channels) 참조).

### 4. 범위 필터링

각 구성 요소는 관련 변경 사항이 있을 때만 릴리스됩니다:

- **CLI**: `(cli)` 범위가 있거나 범위가 없는 커밋
- **App**: `(app)` 범위가 있는 커밋
- **Server**: `(server)` 범위가 있는 커밋

## 릴리스 채널

CLI, 서버 및 Kura는 `main`에 대한 모든 푸시마다 안정 릴리스로 승격되지 않습니다. 각각 세 가지 채널을 통해 배포되므로 권장 설치 버전은 안정적이고 변경 속도가 느린 반면, 얼리 어답터는 커밋 단위 빌드를 유지할 수 있습니다. 사용자 대상 문서는 <.localized_link href="/cli/release-channels">CLI 릴리스 채널</.localized_link> 및 <.localized_link href="/guides/server/self-host/release-channels">서버 릴리스 채널</.localized_link>에 있으며, 이 섹션은 관리자 운영 가이드입니다.

모든 구성 요소는 동일한 세 가지 채널을 사용합니다:

| 채널 | 버전 | 생성 주체 |
|---------|---------|--------|
| 카나리 | `X.Y.0-canary.N` | 자동으로, `main`에 영향을 주는 모든 푸시 시 (`<component>-release.yml`; Kura의 경우 `kura/` 변경 시 `server-production-deployment.yml`에 의해 호출됨) |
| 릴리스 후보 | `X.Y.0-rc.N` | 매주 월요일 또는 수동으로, `releases/<component>-<major>.<minor>.x` 브랜치에서 (`<component>-rc.yml`) |
| 안정 | `X.Y.Z` | 매주 월요일 또는 수동으로, 충분히 검증된 RC를 승격하여 (`<component>-promote.yml`); 패치는 `<component>-backport.yml`를 통해 |

카나리 및 RC 빌드는 GitHub 사전 릴리스로 게시되며("Latest"로 표시되지 않음, GHCR에서 `:latest` 이동 없음, CLI용 Homebrew로 푸시되지 않음) 따라서 패키지 관리자와 이미지 리졸버는 명시적 옵트인 시에만 이를 가져옵니다. 카나리는 항상 다음 미릴리스 마이너 버전을 대상으로 합니다: RC 라인이 생성되면 `main`의 카나리는 다음 마이너 버전으로 진행됩니다.

호스팅된 Tuist는 안정 열차를 기다리지 않습니다: 서버는 커밋 단위 배포되며, 호스팅 카나리와 프로덕션은 최신 Kura 카나리를 실행합니다. 배포 캐스케이드는 배포 전에 해당 카나리 자체를 게시하므로 `kura-release.yml`에는 자체 트리거가 없습니다. Kura 릴리스 도구 변경만(`mise/tasks/kura/**`, `kura-*.yml` 워크플로)으로는 카나리가 생성되지 않습니다.

버전 번호를 직접 선택하지 않습니다. 각 채널의 다음 버전은 아래 워크플로가 호출하는 `mise/tasks/<component>/release/channel-version.sh`에 의해 기존 git 태그에서 파생됩니다.

릴리스 브랜치는 구성 요소별로 네임스페이스가 지정되어(`releases/server-X.Y.x`, `releases/kura-X.Y.x`, CLI의 경우 `releases/X.Y.x`) 세 구성 요소의 라인이 동일한 마이너 버전에서 충돌하지 않습니다.

### 주간 일정

매주 월요일 UTC 06:00에 세 구성 요소의 승격 작업이 동시에 실행됩니다: **CLI를 안정으로 승격**, **서버를 안정으로 승격**, 그리고 **Kura를 안정으로 승격**. 각각 아직 안정화되지 않은 최신 RC 라인을 승격하며, 이는 일반적으로 전 주 월요일에 생성된 라인입니다. 해당 라인이 없으면 해당 작업은 아무것도 게시하지 않습니다.

승격이 완료되면 결과에 상관없이 해당하는 **릴리스 후보** 워크플로(`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`)가 `workflow_run`를 통해 실행되고 `main`에서 다음 라인을 생성합니다.

예약된 실행 중 하나가 실패하거나 취소되면 Slack에 메시지가 게시됩니다. 릴리스 브랜치에 최신 RC 이후의 커밋이 있으면 승격이 실패합니다. 해당 라인을 출시하려면 새 RC를 생성하고 수동으로 승격해야 합니다. 그렇지 않으면 다음 주 월요일에 더 새로운 라인이 대신 승격됩니다.

### 릴리스 후보 생성

주간 일정 외에 새 라인을 생성하려면(아래에서 구성 요소의 워크플로 이름을 대체하세요):

1. 빈 `branch` 입력으로 **<구성 요소> 릴리스 후보** 워크플로(예: `server-rc.yml`)를 실행합니다.
2. `X.Y.0-rc.1`을 게시하고, 성공하면 빌드된 커밋에서 보호된 `releases/<component>-X.Y.x` 브랜치를 생성합니다.

중요한 수정이나 회귀를 소킹 중인 라인에 반영하려면 PR을 통해 릴리스 브랜치로 체리픽합니다(백포트와 동일한 흐름이며 CI는 절대 체리픽하지 않음). 그런 다음 RC를 반복합니다:

1. `releases/<component>-X.Y.x`에서 브랜치를 따고, 수정 사항을 체리픽한 후, 릴리스 브랜치로 다시 PR을 열고 충돌을 해결한 뒤 병합합니다.
2. `branch=releases/<component>-X.Y.x`로 **릴리스 후보** 워크플로를 다시 실행합니다. 이는 브랜치 HEAD에서 `X.Y.0-rc.(N+1)`을 게시합니다.

소킹 중인 라인은 기능이 동결됩니다: 중요한 수정과 회귀만 포함됩니다.

### 안정으로 승격하기

RC가 깨끗하게 소킹된 후 주간 일정 외에 라인을 승격하려면:

1. `branch=releases/<component>-X.Y.x`로 **<구성 요소> 안정으로 승격** 워크플로(예: `server-promote.yml`)를 실행합니다.
2. `make_latest=true`로 세멘틱 버전 태그가 지정된 이미지를 게시하여 GHCR `:latest` 태그와 GitHub "Latest" 포인터를 이동합니다. CLI는 추가로 Homebrew 수식을 업데이트합니다.

브랜치 HEAD가 최신 RC가 가리키는 커밋과 정확히 일치하지 않으면 승격이 실행되지 않습니다. 따라서 마지막 RC 이후 라인에 병합된 수정 사항이 있다면 새 RC를 생성하고 안정적으로 출시될 수 있도록 소킹시켜야 합니다.

### 안정 라인에 수정 사항 백포팅하기

라인이 안정화되면 CLI 전용 **백포트 릴리스** 워크플로(`cli-backport.yml`)를 사용하여 패치를 출시합니다: PR을 통해 `releases/X.Y.x`에 수정 사항을 체리픽한 후, 해당 브랜치로 워크플로를 실행하여 `X.Y.(Z+1)`를 생성합니다. 백포트는 "Latest" 포인터나 Homebrew 수식을 이동하지 않습니다. 두 개의 라인이 동시에 유지됩니다: 현재 라인은 회귀 및 보안 수정 사항을 수용하고, 이전 라인은 중요 및 보안 수정 사항만 수용합니다. 다른 버그 수정 사항은 백포트되지 않으며 다음 마이너 버전에서 출시됩니다.

서버와 Kura의 경우 **서버 백포트 릴리스**(`server-backport.yml`) 또는 **Kura 백포트 릴리스**(`kura-backport.yml`)를 사용합니다. 승격은 RC의 `X.Y.0`만 게시하며 이미 안정화된 라인을 패치할 수 없습니다.

1. 선택한 `X.Y` 라인의 최신 게시된 안정 구성 요소 태그에서 시작하여 기존 `releases/server-X.Y.x` 또는 `releases/kura-X.Y.x` 브랜치로 정밀 수정 PR을 엽니다. 더 새로운 마이너 또는 메이저 릴리스가 유지 중인 라인의 패칭을 방해하지 않습니다. 관련 없는 main 변경 사항은 제외하세요.
2. 소스 PR을 검토하고 병합합니다. 원격 릴리스 브랜치를 가져오고 구성 요소의 지원 플랫폼 및 TLS 양성/음성 제어를 포함한 **최종 병합 팁**을 검증합니다. 병합 전 헤드가 통과되었다고 해서 다른 스쿼시 또는 병합 커밋이 검증된 것은 아닙니다.
3. 별도의 게시 승인을 받아 **main에서** 일치하는 백포트 워크플로를 디스패치하고, `source_sha`를 해당 정확한 검증된 병합 팁으로, `base_tag`를 현재 안정 태그(예: `server@X.Y.Z` 또는 `kura@X.Y.Z`)로 설정합니다. 워크플로는 `X.Y.(Z+1)`을 파생시키며 운영자는 마이너 버전 증가를 선택하거나 카나리 콘텐츠를 승격하지 않습니다.

계획 단계는 정확한 원격 브랜치와 기본 태그를 새로 고치고, 선택된 소스가 브랜치 팁과 일치해야 하며, 변경되지 않은 소스나 구성 요소 외부의 변경 사항, 신뢰 정책 입력 및 검증을 거부하고, 해결된 기본 커밋을 고정합니다. Main 기반 제어는 버전 이미지 및 GitHub 게시 직전에 이러한 검사를 반복합니다. 소스 브랜치, 안정 기본 또는 사용 가능한 버전이 변경되면 새 소스로 대체하지 말고 중단하고 재검증하세요.

백포트는 GitHub의 "Latest" 포인터나 GHCR `:latest`를 이동하지 않고 기존 멀티 플랫폼 게시자를 사용합니다. 게시는 호스팅 배포와 별개입니다: 이러한 워크플로는 호스팅된 서버나 Kura 함대를 승격하거나 카나리 수용을 우회하거나 설치된 런타임을 검증하지 않습니다. 빌드 헬퍼와 Dockerfile은 여전히 선택된 안정 소스에서 제공됩니다. 제어는 게시 게이트이며 자격 증명 없는 빌드 작업이 아닙니다; 빌드는 최종 게이트 전에 태그되지 않은 이미지 다이제스트를 업로드할 수 있습니다. 이미지 및 GitHub 게시는 원자적이지 않습니다: 이미지 태그가 게시된 후 나중 게이트가 실패하면 부분 릴리스를 검사하고 원래 소스와 아티팩트를 유지하세요. 기존 릴리스를 대체하거나 해당 태그 아래에 다른 바이트를 사용하지 마세요.

## 좋은 커밋 메시지 작성하기

커밋 메시지가 릴리스 노트에 직접적인 영향을 미치므로 명확하고 설명적인 메시지를 작성하는 것이 중요합니다:

### 해야 할 일:
- 현재 시제를 사용하세요: "added feature"가 아닌 "add feature"
- 간결하되 설명적으로 작성하세요
- 변경 사항이 구성 요소별인 경우 범위를 포함하세요
- 해당되는 경우 이슈를 참조하세요: `fix(cli): resolve build cache issue (#1234)`

### 하지 말아야 할 일:
- "fix bug" 또는 "update code"와 같은 모호한 메시지를 사용하지 마세요
- 여러 개의 관련 없는 변경 사항을 한 커밋에 혼합하지 마세요
- 주요 변경 사항 정보를 포함하는 것을 잊지 마세요

### 주요 변경 사항

주요 변경 사항의 경우 커밋 본문에 `BREAKING CHANGE:`를 포함하세요:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 릴리스 워크플로

CLI, 서버 및 Kura는 각각 동일한 형태의 채널 워크플로 세트를 가지고 있습니다:

- `<component>-release.yml` - `main`에 구성 요소에 영향을 주는 모든 푸시마다 카나리를 게시합니다(Kura의 경우 `kura/`가 변경될 때 `server-production-deployment.yml`가 호출하는 재사용 가능한 워크플로입니다)
- `<component>-rc.yml` - 매주 월요일(승격 후 `workflow_run`를 통해) 릴리스 후보를 생성하거나 수동으로 생성 또는 반복합니다
- `<component>-promote.yml` - 매주 월요일 UTC 06:00에 대기 중인 RC를 안정으로 승격하거나 소킹된 RC를 수동으로 승격합니다
- `<component>-build-publish.yml` - 위의 세 가지가 호출하는 공유 빌드 및 게시 파이프라인

CLI, 서버 및 Kura는 안정 라인에서 패치를 생성하기 위해 추가로 `<component>-backport.yml`를 가지고 있습니다. 구성 요소의 모든 워크플로는 하나의 `<component>-publish` 동시성 그룹을 통해 직렬화되므로 버전 해결 및 태깅이 경쟁하지 않습니다. Kura는 예외입니다: 카나리는 `kura-canary-publish`를 사용하고 RC, 승격 및 백포트는 `kura-stable-publish`를 사용하므로 긴 안정 빌드가 배포 캐스케이드를 지연시키지 않습니다. 태그 네임스페이스가 분리되어 있으므로 두 그룹이 충돌할 수 없습니다.

Helm 차트와 인프라 이미지(CAPI operator, runners controller, xcresult processor image, linux runner image 등)는 여전히 `.github/workflows/server-production-deployment.yml`를 통해 릴리스됩니다. 이 워크플로는 `main`에 푸시될 때 실행되며, 호스팅 배포를 위해 카나리 → 인수 테스트 → 프로덕션 단계로 진행되고, 변경 사항이 발생할 때마다 해당 인프라 구성 요소를 게시합니다. 앱, 캐시, Gradle 플러그인, 스킬즈, Noora 및 독립형 인프라 컨트롤러는 각각 전용 `*-release.yml` 워크플로를 가지고 있습니다. 모두 변경 감지를 공유합니다: `mise/tasks/release/components.json`는 각 구성 요소의 태그 접두사와 포함 경로를 선언하며, git cliff는 일치하는 커밋을 릴리스 노트로 변환합니다.

CLI 빌드(`cli-build-publish.yml`)는 다운스트림 도구가 명령 인터페이스를 사용할 수 있도록 `tuist.spec.json` 아티팩트(`tuist --experimental-dump-help`에서 생성됨)도 생성하고 게시합니다.

## 릴리스 모니터링

다음 방법을 통해 릴리스를 모니터링할 수 있습니다:
- [GitHub Releases 페이지](https://github.com/tuist/tuist/releases)
- 워크플로 실행을 위한 GitHub Actions 탭
- 각 구성 요소 디렉터리의 변경 로그 파일

## 이점

이 지속적인 릴리스 접근 방식은 다음과 같은 이점을 제공합니다:

- **빠른 전달**: 변경 사항이 병합 직후 사용자에게 즉시 도달합니다
- **병목 현상 감소**: 수동 릴리스를 기다릴 필요가 없습니다
- **명확한 소통**: 커밋 메시지에서 자동 생성된 변경 로그
- **일관된 프로세스**: 모든 구성 요소에 대해 동일한 릴리스 흐름
- **품질 보증**: 테스트된 변경 사항만 릴리스됩니다

## 문제 해결

릴리스가 실패할 경우:

1. 실패한 워크플로의 GitHub Actions 로그를 확인하세요
2. 커밋 메시지가 관례 형식을 따르는지 확인하세요
3. 모든 테스트가 통과하는지 검증하세요
4. 구성 요소가 성공적으로 빌드되는지 확인하세요

즉시 릴리스가 필요한 긴급 수정 사항의 경우:
1. 커밋에 명확한 범위가 있는지 확인하세요
2. 병합 후 릴리스 워크플로를 모니터링하세요
3. 서버 또는 앱의 경우, 수정 사항은 다음 푸시 시 배포됩니다. 필요한 경우 수동 릴리스를 트리거하세요
4. CLI의 경우, 수정 사항은 자동으로 카나리에 적용됩니다. 안정 버전 사용자에게 제공하려면 유지 관리 중인 안정 라인으로 백포트하세요([안정 라인으로 수정 사항 백포트하기](#backporting-fixes-to-a-stable-line) 참조)

## App Store 릴리스

CLI와 서버는 위에서 설명한 지속적인 릴리스 프로세스를 따르지만, **iOS 앱**은 Apple의 App Store 검토 프로세스로 인해 예외입니다:

- **수동 릴리스**: iOS 앱 릴리스는 App Store에 수동으로 제출해야 합니다
- **검토 지연**: 각 릴리스는 Apple의 검토 프로세스를 거쳐야 하며, 이는 1-7일이 소요될 수 있습니다
- **변경 사항 묶음**: 여러 변경 사항은 일반적으로 각 iOS 릴리스에서 함께 번들로 제공됩니다
- **TestFlight**: 베타 버전은 App Store 릴리스 전에 TestFlight를 통해 배포될 수 있습니다
- **릴리스 노트**: App Store 가이드라인에 맞게 특별히 작성해야 합니다

iOS 앱은 여전히 동일한 커밋 규칙을 따르고 git cliff를 사용하여 변경 로그를 생성하지만, 실제 사용자 대상 릴리스는 덜 빈번한 수동 일정에 따라 이루어집니다.
