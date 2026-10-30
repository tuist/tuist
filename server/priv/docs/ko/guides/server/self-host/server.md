---
{
  "title": "서버",
  "titleTemplate": ":title | 자체 호스팅 | 서버 | 가이드 | Tuist",
  "description": "인프라에 Tuist 서버를 배포하는 방법을 알아보세요."
}
---
# 서버 {#server}

인프라에 대한 더 많은 제어가 필요한 조직을 위해 Tuist 서버의 자체 호스팅 버전을 제공합니다. 이 버전을 사용하면 Tuist를 자체 인프라에서 호스팅할 수 있어 데이터가 안전하게 유지되고 비공개로 남습니다.

> [!WARNING]
> **라이선스 필요**
>
> Tuist를 자체 호스팅하려면 법적으로 유효한 유료 라이선스가 필요합니다. Tuist의 온프레미스 버전은 Enterprise 플랜을 사용하는 조직에서만 사용할 수 있습니다. 이 버전에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의해 주세요.

> [!WARNING]
> **레거시 캐시 서비스**
>
> 이전 자체 호스팅 캐시 노드 기술은 새로운 설치에서는 더 이상 사용되지 않습니다. 최신 자체 호스팅 캐시 인프라는 <.localized_link href="/guides/features/cache/self-hosting">자체 호스팅 캐시 가이드</.localized_link>를 참조하세요.
>
> 기존 배포는 GitHub의 마크다운 뷰어에서 레거시 소스 문서를 여전히 참조할 수 있습니다: [캐시 노드](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) 및 [캐시 아키텍처](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md).

## 릴리스 주기 {#release-cadence}

Tuist 서버와 Kura 캐시 서버는 세 가지 GHCR 이미지 채널을 통해 배포됩니다: **canary**(`main`의 모든 커밋), **release candidate**(매주 월요일 생성, 일주일 동안 검증), 그리고 **stable**(다음 주 월요일 승격). 안정 릴리스만 `:latest`를 이동하며 기본적으로 해결됩니다. 카나리와 릴리스 후보는 태그를 고정하여 선택적으로 참여하는 GitHub 사전 릴리스입니다. 서버와 Kura는 [Tuist CLI의 릴리스 일정](/en/cli/release-channels)과 발맞춰 동일한 주간 주기를 따릅니다.

예측 가능한 버전 관리와 호환성을 보장하기 위해 [시맨틱 버전 관리](https://semver.org/)를 따릅니다. 주요 구성 요소는 Tuist 서버의 파괴적 변경 사항을 표시하는 데 사용되며, 이는 자체 호스팅 사용자와의 조정이 필요합니다. 이를 사용할 것으로 기대하지 않아도 되며, 만약 필요하다면 원활한 전환을 위해 여러분과 협력할 것입니다.

각 채널이 어떻게 생성되는지, 배포에서 하나를 고정하는 방법, 그리고 스테이징 환경에서 다가오는 릴리스를 검증하는 동안 프로덕션을 느리게 움직이는 안정 라인에 유지하는 권장 전략에 대해서는 <.localized_link href="/guides/server/self-host/release-channels">릴리스 채널</.localized_link> 페이지를 참조하세요.

## OAuth 업그레이드 및 롤백 경계 {#oauth-upgrade-and-rollback-boundary}

OAuth 엔티티 캐시 제거는 기존 설치를 위한 단계적 업그레이드가 필요합니다. OAuth 캐시 무효화를 중지하는 버전을 배포하기 전에, 먼저 [#14040](https://github.com/tuist/tuist/pull/14040)의 권한 있는 읽기 호환성 릴리스를 **모든 OAuth 리더와 라이터**에 배포하세요. 이 호환성 단계는 **1.355** 릴리스 라인에서 처음 나타납니다: `ghcr.io/tuist/tuist:1.355.0-rc.1`에 포함되어 있으며, 프로덕션 배포는 승격된 후 안정적인 `1.355.x` 릴리스를 사용해야 합니다. 1.354 이하 버전의 설치는 제거 기능이 포함된 이후 릴리스로 업그레이드하기 전에 이 단계를 완료해야 합니다. 1.355 라인은 호환성 전용으로 유지하세요: 무효화 제거 기능을 이 라인에 백포트하지 마십시오.

원본 호환성 커밋은 `ghcr.io/tuist/tuist:sha-c8e54471a425`으로도 제공됩니다. 다른 이미지는 이전 소비자가 남아 있는 동안 권한 있는 읽기를 보존하고 **레거시 무효화를 유지**하는 경우에만 호환성 단계로 적합합니다. 트래픽을 제공하기 전에 해당 단계의 일반적인 데이터베이스 마이그레이션(리프레시 토큰 조회 인덱스 포함)을 실행하세요.

각 환경의 모든 웹 복제본, 백그라운드 워커, 스케줄된 작업 및 별도로 고정된 프로세서 이미지를 확인하세요. 호환성 롤아웃이 완료될 때까지 기다리고 무효화를 제거하기 전에 캐시를 읽는 바이너리가 남아 있지 않은지 확인하세요. 자동 업그레이드 중에浮动 이미지 태그가 이 단계를 건너뛰지 않도록 하세요. 이전 소비자가 없는 신규 설치에는 중간 배포가 필요하지 않습니다.

> [!WARNING]
> **권한 있는 읽기 롤백 대상 유지**
>
> 무효화가 제거된 후, 일반적인 롤링 롤백은 #14040 또는 다른 권한 있는 읽기 버전을 대상으로 해야 합니다. 모든 무효화 프로세스가 중단된 후에도 retained OAuth 캐시 항목은 stale 상태일 수 있으며, 재시작된 캐시 읽기 복제본은 피어로부터 이를 가져올 수 있습니다.
>
> 더 깊이 롤백하려면 **모든** 무효화되지 않는 OAuth 소비자를 중지하고 드레이닝한 다음, 캐시 읽기 소비자를 시작하기 전에 **모든** retained Boruta 캐시 참가자를 지우거나 교체해야 합니다. retained 참가자가 다시 가입하지 않도록 방지하세요. 인그레스만 드레이닝하거나 웹 복제본만 재시작하는 것은 불충분합니다. 캐시를 지우거나 데이터베이스 마이그레이션을 자동으로 롤백하기보다는 Tuist 지원 담당자와 이 복구 작업을 조정하세요.

## 다중 복제본 클러스터링 {#multi-replica-clustering}

지원되는 다중 복제본 웹 배포는 인증 권한이 아닌 크로스 복제본 Phoenix PubSub 및 Oban PG 알림을 위해 Erlang 클러스터링이 필요합니다. `server.cluster.enabled`가 false일 때 차트는 하나의 복제본을 초과하여 확장될 수 있는 오토스케일러를 포함하여 여러 복제본을 거부합니다. 이전에 허용된 비클러스터 배포는 가드를 우회하지 않고 이 업그레이드를 계획해야 합니다. 멤버십을 변경하기 전에 <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth 업그레이드 시퀀스</.localized_link>(무효화 제거 포함)를 완료하세요.

비밀 관리자를 사용하여 릴리스 네임스페이스에 개인 쿠키 Secret을 생성한 다음 이름과 키를 구성하세요:

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

쿠키는 높은 엔트로피를 가져야 하며 참여하는 모든 웹 복제본에서 공유되어야 합니다. 공개된 이미지에 내장된 쿠키를 절대 사용하지 마십시오: 배포 쿠키를 소유하면 해당 노드에서 원격 실행이 가능해집니다. 분산 릴리스 시작은 이제 누락된 개인 `RELEASE_COOKIE` 또는 잘못된 포트를 거부하며, DNS 검색 없이 명시적으로 구성된 `RELEASE_DISTRIBUTION=name` 또는 `sname`도 포함됩니다. 비차트 배포도 `TUIST_CLUSTER_DNS_SERVICE`, `TUIST_CLUSTER_APP_NAME` 및 팟 IP/노드 이름을 일관되게 구성해야 합니다. 검색은 현재 IPv4 A 기록을 사용합니다.

일반적인 서버 연결 `helm upgrade`에서 `cookieExistingSecret`를 비워 두면 쿠키 Secret이 생성되고 이후 업그레이드에서 현재 값을 재사용합니다. 오프라인 `helm template`, Argo CD 및 기타 라이브 Secret 조회가 없는 GitOps 렌더러는 생성된 값을 보존할 수 없습니다. 이들은 별도로 관리되는 안정적인 Secret으로 뒷받침되는 `cookieExistingSecret`를 사용해야 합니다. 라이브 클러스터를 암시적으로 회전시키기 위해 쿠키 키를 변경하지 마십시오. 쿠키 회전에는 모든 참가자의 조정된 마이그레이션/재시작이 필요하며, Secret만 업데이트한다고 해서 기존 프로세스가 업데이트되지는 않습니다.

이미지에 내장된 쿠키에서 첫 롤아웃을 수행하면 모든 웹 복제본이 개인 Secret을 사용할 때까지 구버전/신버전 멤버십 섬이 별도로 형성됩니다. 실시간 업데이트를 위한 마이그레이션 창구를 계획하세요. 이후의 롤링 배포는 혼합 버전 클러스터를 형성하므로, 실제 구버전/신버전 간에 PubSub, Oban 알림 및 피어 교체를 검증하세요. 이러한 알림은 지속적 전달 보장을 제공하지 않습니다. 호환되는 버전을 롤백할 때는 권위 있는 읽기 권한을 가진 롤백 이미지를 유지하고 동일한 개인 쿠키를 보존하세요.

EPMD(TCP 4369)와 구성된 배포 포트는 신뢰할 수 있는 서버 피어 간에만 허용하고, 테넌트 워크로드나 공용 네트워크에서는 절대 허용하지 마십시오. 환경에서의 실제 인그레스/이그레스 격리를 확인하세요. NetworkPolicy를 렌더링한다고 해서 강제 적용이나 백엔드 도달 가능성이 입증되지는 않습니다. 연속 부하 하의 두 복제본 카나리아는 승격 전에 가입, 롤링 교체 및 장애/복구를 통과해야 합니다. DNS는 피어를 검색하는 데 사용되며, 일시적인 실패 또는 부분적인 응답으로 인해 정상 노드를 연결 해제하는 데 사용되지 않습니다. 실제 노드 손실과 OTP 파티션 방지는 여전히 적용됩니다. libcluster는 연결을 닫지 않고도 유지 관리 콜백을 위해 성공적인 "연결 해제" 작업을 로깅할 수 있습니다. 해당 로그 줄뿐만 아니라 노드 업/다운 이벤트 또는 `Node.list()`에서 실제 멤버십을 확립하세요.

## 지속적 배포 {#continuous-deployment}

프로덕션을 안정적인 마이너 라인(예: `ghcr.io/tuist/tuist:1.351`)에 고정하여 일상적인 업그레이드가 백포트된 수정 사항만 포함하도록 하는 것을 권장합니다. 안정적인 라인은 릴리스 후보 채널에서 일주일간 소크 테스트를 거친 후 매주 월요일 UTC 06:00에 승격됩니다. 카나리 또는 현재 릴리스 후보 태그의 스테이징 환경은 사용자에게 도달하기 전에 회귀를 포착합니다. 권장되는 고정 전략은 <.localized_link href="/guides/server/self-host/release-channels">릴리스 채널</.localized_link>을 참조하세요.

매니페스트를 변경하지 않고 새로운 기능이 안정화됨에 따라 흡수하기를 원한다면 `:latest`를 고정하세요. 태그는 매주 월요일 아침에 이동하므로 이에 맞춰 배포 창구를 계획하세요. 다음은 해당 주기에 따라 최신 안정 이미지를 확인하고 배포하는 GitHub Actions 워크플로의 예시입니다:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 8 * * 1' # Mondays 08:00 UTC, after the weekly stable promote
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

<span id="network-trusted-report-publishing"></span>
<span id="network-trusted-cache-access"></span>

## 네트워크 신뢰 액세스 {#network-trusted-access}

셀프 호스팅 설치에서는 신뢰할 수 있는 네트워크의 개발자가 로그인 없이 인사이트를 제출하거나 캐시를 사용하거나 둘 다 수행할 수 있습니다. 대시보드 및 관리는 여전히 인증이 필요합니다.

필요한 기능만 활성화하세요:

| 서버 환경 변수 | 로그인 없이 허용 |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | 빌드 및 테스트 인사이트 제출 |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | 캐시된 빌드 출력 읽기 및 쓰기 |

두 설정 모두 **기본적으로 꺼져 있으며**, 독립적이고 개인 프로젝트를 포함한 모든 계정 및 프로젝트에 인스턴스 전체로 적용됩니다. 이들은 호스팅된 Tuist에서는 사용할 수 없으며 셀프 호스팅 라이선스를 대체하지 않습니다.

이전의 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` 이름은 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS`가 설정되지 않았을 때 호환성 폴백으로 남아 있습니다.

> [!WARNING]
> 강제된 사내 네트워크 또는 VPN 경계 뒤에서만 이러한 설정을 활성화하세요. 활성화된 엔드포인트에 도달할 수 있는 사람은 누구나 보고서를 제출하거나, 캐시 액세스가 활성화된 경우 캐시된 출력을 읽고 덮어쓸 수 있습니다. 이는 위조된 텔레메트리, 캐시 오염 및 용량 고갈을 허용합니다. 보고 응답은 또한 비공개 프로젝트 핸들 및 빌드 시스템을 노출할 수 있습니다. Tuist는 VPN 멤버십을 확인하거나 전달된 IP 헤더를 멤버십 증거로 신뢰하지 않습니다.

### 인스턴스 구성 {#network-trusted-instance-configuration}

1. 방화벽 또는 전용 인그레스를 사용하여 Tuist 서버, 모든 Kura HTTP/gRPC 리스너 및 모든 Bazel BES 인그레스를 신뢰할 수 있는 네트워크로 제한하세요.
2. 클라이언트를 업그레이드하기 전에 모든 서버 및 Kura 복제본을 업그레이드하세요. `KURA_AUTH_TUIST_URL` 및 제어 플레인 자격 증명으로 Kura 인증을 활성화된 상태로 유지하세요. 이를 비활성화하면 이러한 제한이 우회됩니다. <.localized_link href="/guides/features/cache/self-hosting">셀프 호스팅 캐시 가이드</.localized_link>를 사용하여 캐시 엔드포인트를 구성하세요.
3. 위의 원하는 변수를 관련 Tuist 서버 복제본 각각에 설정한 다음 재시작하거나 재배포하세요. 정확한 값 `true`만 설정을 활성화합니다. 대시보드 토글이나 별도의 Kura 플래그는 없습니다.

### 클라이언트 구성 {#network-trusted-client-configuration}

호환되는 각 클라이언트에 최종 셀프 호스팅 서버 URL과 프로젝트를 구성하세요. 클라이언트는 자격 증명이 없을 때 어떤 기능이 활성화되었는지 자동으로 검색합니다. 클라이언트 옵트인이 필요하지 않습니다. 검색은 리디렉션을 따르지 않습니다. 기존 자격 증명은 계속 사용되며, 유효하지 않거나 새로 고침에 실패한 자격 증명은 익명 폴백 대신 오류를 발생시킵니다. 복구하려면 다시 로그인하거나 명시적으로 로그아웃하세요.

인사이트 액세스를 활성화하기 전에, 손상되거나 거부된 자격 증명을 보존하고, 읽을 수 없는 자격 증명 디렉터리를 거부하며, 서명되지 않은 보고서에서 Git 출처를 생략하는 버전으로 자격 증명을 공유하는 모든 도구를 업그레이드하세요. 이전 도구는 자격 증명을 삭제하고 의도치 않게 익명 폴백을 허용할 수 있습니다. 서버만 업그레이드해서는 이를 해결할 수 없습니다. 서버에 검색 지원이 부족하거나 이전 버전으로 롤백된 경우 클라이언트는 인증해야 합니다. 이전의 `TUIST_NETWORK_TRUSTED_PUBLISHING` 클라이언트 설정은 더 이상 적용되지 않습니다.

- **인사이트:** 완료된 Xcode, Gradle, Elixir/Mix 및 Bazel 보고서만 제출하세요. 아카이브, 첨부 파일, 커버리지, 샤드 계획 또는 기존 보고서 액세스는 포함되지 않습니다. 액터 클레임은 검증되지 않으며, 서명되지 않은 텔레메트리는 신뢰할 수 있는 테스트 증거나 자동화를 구동하지 않습니다. 클라이언트 설정 및 개인정보 보호 세부 정보는 <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>, <.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> 및 <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> 가이드를 참조하세요.
- **캐시:** CLI 컴파일/모듈 캐싱, Bazel 캐싱 및 Gradle 작업 캐싱을 지원합니다. 캐시 퍼지 및 원격 자산 다운로드에는 여전히 자격 증명이 필요합니다. 지원을 받지 않는 클라이언트는 계속 인증해야 합니다.
- **Bazel:** 보고에는 명시적인 `TUIST_BAZEL_BES_BACKEND` 및 호환되는 Kura가 필요합니다. 캐시 및 보고 옵션은 독립적으로 활성화됩니다. 자격 증명이나 두 설정 중 하나를 변경한 후 `tuist bazel setup`를 다시 실행하세요. 컴파일 캐시 구성 변경 시 `tuist cache config`를 다시 실행하세요.

보고서 요청은 프로젝트당 8MB, 분당 60개 요청, 하루 10,000개 요청으로 제한됩니다. 여러 복제본을 사용한 배포 전체 할당량을 위해 공유 Valkey를 구성하세요. 그렇지 않으면 제한은 프로세스별입니다. 구성된 공유 할당량 백엔드를 사용할 수 없는 경우 서명되지 않은 보고서는 거부됩니다. 인그레스 연결, 본문 및 속도 제한도 추가하세요.

### 네트워크 신뢰 액세스 비활성화 {#disable-network-trusted-publishing}

해당 변수를 `false`로 설정한 후, **관련된 모든 서버 복제본**을 다시 시작하세요. 이전 복제본은 교체될 때까지 자격 증명 없는 요청을 계속 수락할 수 있습니다. 마지막 복제본이 전환된 후 60초 이내에 새 요청에 대한 캐시 액세스가 중단되며, 진행 중인 전송은 취소되지 않습니다. 즉시 권한을 회수해야 하는 경우 인그레스에서 트래픽을 먼저 차단하세요. 기존 보고서는 일반적인 가시성과 보존 정책을 유지하며, 인증된 클라이언트는 계속 작동합니다.

## 런타임 요구 사항 {#runtime-requirements}

이 섹션에서는 인프라에 Tuist 서버를 호스팅하기 위한 요구 사항을 설명합니다.

### 호환성 매트릭스 {#compatibility-matrix}

Tuist 서버는 테스트되었으며 다음 최소 버전과 호환됩니다:

| 구성 요소 | 최소 버전 | 참고 |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | 분석에 필요 |

### Docker 가상화 이미지 실행 {#running-dockervirtualized-images}

서버는 [Docker](https://www.docker.com/) 이미지로 [GitHub의 컨테이너 레지스트리](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를 통해 배포됩니다.

실행하려면 인프라가 Docker 이미지 실행을 지원해야 합니다. 대부분의 인프라 제공업체는 이를 지원합니다. 이는 프로덕션 환경에서 소프트웨어를 배포하고 실행하기 위한 표준 컨테이너가 되었기 때문입니다.

### Postgres 데이터베이스 {#postgres-database}

Docker 이미지를 실행하는 것 외에도 관계형 데이터를 저장하기 위해 [Postgres 데이터베이스](https://www.postgresql.org/)가 필요합니다. 대부분의 인프라 제공업체는 Postgres 데이터베이스를 포함합니다(예: [AWS](https://aws.amazon.com/rds/postgresql/) 및 [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

> [!NOTE]
> **마이그레이션**
>
> Docker 이미지의 진입점(entrypoint)은 서비스를 시작하기 전에 대기 중인 스키마 마이그레이션을 자동으로 실행합니다.


### ClickHouse 데이터베이스 {#clickhouse-database}

Tuist는 대량의 분석 데이터를 저장하고 쿼리하기 위해 [ClickHouse](https://clickhouse.com/)를 사용합니다. ClickHouse는 빌드 인사이트와 같은 기능에 **필수**입니다. ClickHouse를 자체 호스팅하거나 호스팅된 서비스를 사용할지 선택할 수 있습니다.

> [!NOTE]
> **마이그레이션**
>
> Docker 이미지의 진입점(entrypoint)은 서비스를 시작하기 전에 대기 중인 ClickHouse 스키마 마이그레이션을 자동으로 실행합니다.

번들된 Docker Compose 및 Helm 내장 ClickHouse 구성은 이미지 기본값인 `trace`에서 `information`로 ClickHouse 텍스트 로그 수준을 낮춥니다. 이는 `system.text_log` 볼륨의 대부분이 발생하는 지점입니다. 두 구성 모두 기본적으로 무제한인 ClickHouse 자체의 `system.*` 운영 로그 테이블에도 상한선을 적용할 수 있지만, 기본적으로는 비활성화되어 있습니다. 아래를 참조하세요. 외부 ClickHouse 배포는 이러한 운영 로그를 ClickHouse 서비스에서 직접 구성해야 합니다.

#### ClickHouse 복제 토폴로지 {#clickhouse-replication-topology}

Tuist 뒤의 다중 복제본 ClickHouse는 ClickHouse Cloud에서만 지원됩니다. 자체 관리 ClickHouse는 단일 복제본입니다.

인제스트 마이그레이션은 일반 `MergeTree` 엔진을 생성합니다. Cloud에서는 투명하게 `SharedMergeTree`가 되므로 쓰기는 공유 객체 스토리지에 저장되며 모든 복제본 수가 작동합니다. 자체 관리 ClickHouse에서는 `MergeTree`가 하나의 복제본에만 로컬 디스크에 기록됩니다. 다중 복제본 설정은 연결 사용자의 `database_replicated_allow_only_replicated_engine` 설정 방식에 따라 인제스트를 복제본 간에 조용히 분할하거나 `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.`로 CREATE를 거부합니다.

자체 관리 ClickHouse에서 하나의 샤드와 하나의 복제본을 실행하고 ClickHouse 데이터 디렉터리의 정기 백업을 수행하세요. 노드가 손실될 경우 대체할 두 번째 복제본이 없습니다.

#### 운영 로그 보존 기간 상한 설정 {#capping-operational-log-retention}

보존 기간은 `system.text_log`, `system.query_log`, `system.query_thread_log`, `system.query_views_log`, `system.trace_log`, `system.metric_log`, `system.asynchronous_metric_log` 및 `system.part_log`에 적용할 수 있습니다.

이미 데이터가 있는 인스턴스에서 이를 활성화하는 것은 일회성 단방향 단계이므로 번들 패키지 중 어느 것도 이를 자동으로 수행하지 않습니다. 어떤 보존 기간이라도 설정하면 해당 테이블 정의가 구성과 일치하지 않게 되므로, ClickHouse는 각 테이블의 이름을 변경하고 [대체된 로그 테이블](#superseded-log-tables)에서 설명된 대로 새 테이블을 시작합니다. 남겨진 세대는 지금까지 누적된 모든 데이터를 보유하며 자체 보존 기간이 없으므로, 동일한 단계에서 이를 회수하지 않으면 디스크에 영구적으로 남게 되고 새 창은 그 이후에 작성된 행만 제한합니다. 둘을 함께 활성화하세요:

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

단일 `helm upgrade`는 자체 완결적입니다. `ttlDays`를 공백에서 설정 값으로 변경하면 드롭인 마운트가 추가되고 ClickHouse 포드가 롤링되기 때문입니다. 포드가 재시작되고 테이블이 대체되며, 업그레이드 후 Job이 이를 삭제합니다. Job이 실행되기 전에 포드가 롤링되도록 `helm upgrade --wait`로 배포하세요. 그렇지 않으면 세대가 확인된 후에 나타나며, 다음 `helm upgrade`에서 이를 회수합니다.

Docker Compose를 사용하는 경우, `docker-compose.yml`의 `clickhouse` 서비스에 있는 `clickhouse-log-ttl.xml` 볼륨 주석을 해제하고 `.env`에서 두 변수를 설정하세요:

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

공간을 회수한 후에는 `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES`를 다시 `ignore`로 설정하여 향후 ClickHouse 업그레이드가 자체적으로 기록을 삭제하지 않도록 할 수 있습니다.

#### 대체된 로그 테이블 {#superseded-log-tables}

ClickHouse는 시작 시 각 시스템 로그 테이블이 여전히 구성과 일치하는지 확인합니다. 일치하지 않는 경우 기존 테이블의 이름을 `system.<name>_0`, `_1`, `_2` 등으로 변경하고 새 테이블을 시작합니다. 이는 보존 기간 창을 변경할 때 또는 시스템 로그 스키마를 변경하는 ClickHouse 업그레이드 시 발생합니다.

테이블 이름 변경은 데이터를 복사하지 않으므로 추가 디스크 공간을 소비하지 않습니다. 대체된 테이블에 이후 발생하는 일은 원래 테이블에 따라 달라집니다. 대체된 순간 활성 테이블이 가지고 있던 보존 정책을 유지하기 때문입니다. 처음으로 보존을 활성화할 때 대체되는 테이블에는 보존 정책이 없으므로 지금까지 누적된 모든 기록을 무기한 보관합니다. 나중에 창을 변경하면 이미 TTL을 가진 테이블이 대체되므로, 이들은 만료되어 빈 테이블만 남깁니다. ClickHouse는 테이블 자체를 삭제하지 않으므로 장기 운영 인스턴스에서는 어느 쪽이든 누적됩니다.

대체된 테이블은 기본적으로 유지되므로 업그레이드가 자체적으로 운영 기록을 삭제하지 않습니다. 대신 삭제하려면 정책을 `delete`로 설정하세요. 이는 `docker compose up` 및 각 `helm upgrade` 시 발생합니다:

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Helm 차트에서는 동일한 정책을 값으로 구성하세요:

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

대체된 테이블을 삭제하면 디스크 공간이 회수됩니다. 활성 테이블이나 대체된 이후 작성된 행에는 영향을 주지 않습니다.

정책을 변경하지 않고 한 번만 공간을 회수하려면 테이블을 수동으로 삭제하세요:

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` 데이터베이스는 `Atomic` 엔진을 사용하며, 일반 `DROP TABLE`를 `database_atomic_delay_before_drop_table_sec`(기본값 8분) 동안 지연시킵니다. `SYNC`는 데이터를 즉시 제거하므로 디스크가 가득 차서 테이블을 삭제할 때 유용합니다.


### 스토리지 {#storage}

파일(예: 프레임워크 및 라이브러리 바이너리)을 저장할 솔루션도 필요합니다. Tuist 서버는 S3 호환 스토리지와 Azure Blob Storage를 서버 소유 아티팩트에 대해 지원합니다.

> [!TIP]
> **최적화된 캐싱**
>
> 주요 목표가 캐시 지연 시간을 줄이는 것이라면 전체 서버를 자체 호스팅할 필요가 없을 수 있습니다. CI 또는 개발자 네트워크 근처에 자체 호스팅 Kura 노드를 배포하고 이를 호스팅된 Tuist 서버나 자체 호스팅 서버에 연결할 수 있습니다.
>
> <.localized_link href="/guides/cache/self-host">자체 호스팅 캐시 가이드</.localized_link>를 참조하세요.


### 자체 호스팅 Kura 노드 {#self-hosted-cache-nodes}

자체 호스팅 Tuist 서버와 함께 자체 호스팅 Kura 노드를 사용하려면 다음 단계를 따르세요:

1. Tuist 서버에서 `KURA_CONTROL_PLANE_CLIENT_ID` 및 `KURA_CONTROL_PLANE_CLIENT_SECRET`를 구성하세요. 클라이언트 ID는 **UUID여야 합니다**. <.localized_link href="/guides/cache/self-host#control-plane-client">자체 호스팅 캐시 가이드</.localized_link>의 명령어를 사용하여 UUID와 무작위 시크릿을 생성하고 배포 시크릿에 저장하세요.
2. 동일한 컨트롤 플레인 자격 증명을 사용하여 <.localized_link href="/guides/cache/self-host">자체 호스팅 캐시 가이드</.localized_link>에 따라 Kura 노드를 배포하세요.
3. 각 Kura 노드에 `KURA_REGISTRATION_URL` 및 `KURA_ADVERTISED_HTTP_URL`를 구성하세요. 등록 하트비트는 서버가 CLI에 광고할 수 있는 준비된 클라이언트 Facing Kura 엔드포인트를 알려줍니다.

## 구성 {#configuration}

서비스 구성은 런타임에 환경 변수를 통해 수행됩니다. 이러한 변수의 민감한 성격을 고려하여 암호화하고 안전한 비밀번호 관리 솔루션에 저장하는 것을 권장합니다. Tuist는 이러한 변수를 최대한 주의 깊게 처리하여 로그에 표시되지 않도록 합니다.

> [!NOTE]
> **시작 검사**
>
> 필수 변수는 시작 시 검증됩니다. 누락된 변수가 있으면 시작이 실패하며 오류 메시지에 누락된 변수가 상세히 표시됩니다.


### 라이선스 구성 {#license-configuration}

온프레미스 사용자는 라이선스를 받게 되며 이를 환경 변수로 노출해야 합니다. 라이선스는 배포를 검증하고 서비스가 계약 조건 내에서 실행되고 있는지 확인하는 데 사용됩니다.

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | 서비스 수준 계약서 서명 후 제공되는 라이선스입니다. 표준 라이선스 키 또는 서버가 외부 서비스에 접근할 수 없는 격리된 환경에서 사용되는 base64 인코딩 인증서를 모두 허용합니다. | 예 | | `******` |

> [!WARNING]
> **만료 날짜**
>
> 라이선스에는 만료 날짜가 있습니다. 라이선스가 30일 이내에 만료되면 서버와 상호작용하는 Tuist 명령어 사용 중 경고가 표시됩니다. 라이선스 갱신에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의하세요.


### 기본 환경 구성 {#base-environment-configuration}

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | 인터넷에서 인스턴스에 접근하기 위한 기본 URL | 예 | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | 정보(예: 쿠키의 세션)를 암호화하는 데 사용할 키 | 예 | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | 해시된 비밀번호를 생성하기 위한 페퍼 | 아니오 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | 무작위 토큰을 생성하기 위한 시크릿 키 | 아니오 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 민감한 데이터의 AES-GCM 암호화를 위한 32바이트 키 | 아니오 | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | `1`일 때 앱이 IPv6 주소를 사용하도록 구성합니다 | 아니오 | `0` | `1`|
| `TUIST_LOG_LEVEL` | 앱에 사용할 로그 레벨 | 아니오 | `info` | [로그 레벨](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | GitHub 앱의 슬러그로, `https://github.com/apps/<slug>`에서 가져옵니다. 앱 설치에 필요합니다. <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> 참조 | 아니오 | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 자동 PR 댓글 게시와 같은 추가 기능을 잠금 해제하기 위해 GitHub 앱에 사용되는 base64 인코딩된 프라이빗 키 | 아니오 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 자동 PR 댓글 게시와 같은 추가 기능을 잠금 해제하기 위해 GitHub 앱에 사용되는 프라이빗 키입니다. **특수 문자 문제를 피하기 위해 base64 인코딩 버전을 사용하는 것을 권장합니다** | 아니오 | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | 이메일 주소가 `@<this-domain>`로 끝나는 확인된 사용자는 운영 URL(`/ops/*`)에 접근할 수 있습니다 | 아니오 | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | 서버 인스턴스를 식별하기 위해 대시보드 내비게이션 바에 배지로 표시되는 라벨(예: 버전 번호 또는 브랜치 이름) | 아니오 | 개발 환경의 Git 브랜치 | `v1.2.3` |
| `TUIST_WEB` | 웹 서버 엔드포인트 활성화 | 아니오 | `1` | `1` 또는 `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | 로그인 없이 빌드 및 테스트 인사이트 제출을 허용합니다. 설정 및 보안 요구사항은 [네트워크 신뢰 액세스](#network-trusted-access)를 참조하세요. | 아니오 | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | 로그인 없이 캐시 읽기 및 쓰기를 허용합니다. 설정 및 보안 요구사항은 [네트워크 신뢰 액세스](#network-trusted-access)를 참조하세요. | 아니오 | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | 추적 정보를 보내기 위한 OpenTelemetry Collector의 gRPC 엔드포인트 | 아니오 | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | 로그를 푸시하기 위한 Loki 호환 엔드포인트의 기본 URL(예: Grafana Alloy 또는 Loki) | 아니오 | | `http://localhost:3100` |

> [!WARNING]
> **HTTPS를 통해 앱 제공**
>
> 세션 쿠키는 `Secure`로 플래그되어 있으므로 일반 `http://`에서는 브라우저가 이를 제거하여 사용자가 로그인할 수 없습니다. 서버 앞에서 TLS를 종료하고(내부 CA의 인증서를 사용한 리버스 프록시로 충분함) 내부 또는 VPN 전용 배포에서도 `TUIST_APP_URL`를 `https://` URL로 설정하세요.

### 데이터베이스 구성 {#database-configuration}

다음 환경 변수는 데이터베이스 연결을 구성하는 데 사용됩니다.

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | Postgres 데이터베이스에 접근하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다. | 예 | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist의 애플리케이션 테이블에서 사용하는 PostgreSQL 스키마입니다. 데이터베이스 정책이 `public` 스키마 사용을 허용하지 않을 때 이 값을 설정하세요. 스키마 이름은 따옴표가 없는 PostgreSQL 식별자여야 합니다. | 아니오 | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | `Tuist.Release.migrate`에서만 사용하는 선택적 Postgres URL입니다. `DATABASE_URL`가 더 제한된 런타임 역할을 가리킬 때 소유자 역할 URL로 설정하세요. | 아니오 | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | 마이그레이션 완료 후 애플리케이션 테이블 권한을 부여해야 하는 런타임 Postgres 역할입니다. 웹 서버가 스키마 소유자로 연결되지 않아야 할 때 `TUIST_MIGRATION_DATABASE_URL`와 함께 사용하세요. | 아니오 | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | ClickHouse 데이터베이스에 접근하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다. | 아니오 | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | true일 경우 데이터베이스 연결에 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)을 사용합니다. | 아니오 | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | 연결 풀에서 열어둘 연결 수 | 아니오 | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | 풀에서 체크아웃된 모든 연결이 큐 간격보다 오래 걸렸는지 확인하는 간격(밀리초 단위) [(자세히 보기)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 아니오 | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 새 연결 드롭을 시작할지 결정하기 위해 풀이 사용하는 큐 내 임계 시간(밀리초 단위) [(자세히 보기)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 아니오 | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 버퍼 플러시 사이의 시간 간격(밀리초) | 아니오 | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | 강제 플러시 전 최대 ClickHouse 버퍼 크기(바이트) | 아니오 | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | 실행할 ClickHouse 버퍼 프로세스 수 | 아니오 | `5` | `5` |

`TUIST_DATABASE_SCHEMA`가 `public`가 아닐 때, Ecto 마이그레이션 체인을 실행하기 전에 스키마가 아직 존재하지 않으면 릴리스 마이그레이션이 스키마를 생성합니다. 마이그레이션 역할이 스키마를 생성할 수 없다면 미리 스키마를 생성하고 마이그레이션 역할을 해당 스키마의 소유자로 설정하세요.

Tuist는 세션 `search_path`을 설정하여 연결을 custom 스키마로 지정합니다. 일부 풀링되거나 프록시된 Postgres 설정(예: PgBouncer 또는 시작 매개변수를 제한하는 관리형 데이터베이스)은 이를 적용하지 않으며 세션은 `public`로 폴백되는데, 이는 마이그레이션 중에 `permission denied for schema public` 오류로 나타납니다. 이러한 설정을 통해 연결할 때는 프록시에 관계없이 모든 세션이 해당 스키마에서 시작되도록 역할 자체에 스키마를 고정하세요:

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### 인증 환경 구성 {#authentication-environment-configuration}

[신원 공급자(IdP)](https://en.wikipedia.org/wiki/Identity_provider)를 통한 인증을 지원합니다. 이를 활용하려면 선택한 공급자에 필요한 모든 환경 변수가 서버 환경에 있는지 확인하세요. **누락된 변수**가 있으면 Tuist는 해당 공급자를 건너뜁니다.

#### 이메일 및 비밀번호 {#email-and-password}

이메일 및 비밀번호 로그인과 셀프 서비스 등록은 기본 제공되며 기본적으로 활성화되어 있습니다. 신원 공급자를 필수로 요구하려는 인스턴스(예: SSO 강제 시)에서는 이를 완전히 비활성화할 수 있습니다. 이렇게 하면 로그인 경험에서 이메일/비밀번호 폼, 가입 링크, 비밀번호 재설정 흐름이 제거되고 CLI가 사용하는 이메일/비밀번호 엔드포인트(`tuist auth`)를 포함해 일치하는 모든 서버 측 엔드포인트가 닫힙니다.

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | 이메일과 비밀번호로 로그인 및 등록할 수 있는지 여부입니다. 로그인 페이지에서 이메일/비밀번호 폼, 가입 링크, 비밀번호 재설정 흐름을 제거하고 일치하는 서버 측 엔드포인트를 닫으려면 `0`로 설정하세요. | 아니오 | `1` | `0` |

#### 구성된 신원 공급자 비활성화 {#disabling-a-configured-identity-provider}

기본적으로 공급자가 구성되면 로그인 옵션으로 표시됩니다. 로그인 및 가입 페이지에서 제거하면서도 공급자는 구성된 상태(자격 증명이 설정된 상태)로 유지하려면 해당 레버를 `0`로 설정하세요. GitHub, Google, Apple의 경우 이는 로그인 콜백도 닫으므로 해당 방법은 전체적으로 사용할 수 없게 됩니다.

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub로 로그인할 수 있는지 여부입니다(앱이 로그인과 자격 증명을 공유하는 이유는 [GitHub](#github) 섹션을 참조하세요). | 아니오 | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Google로 로그인할 수 있는지 여부 | 아니오 | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | 구성된 Okta 공급자가 로그인 옵션으로 표시되는지 여부 | 아니오 | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Apple로 로그인할 수 있는지 여부 | 아니오 | `1` | `0` |

#### GitHub {#github}

[GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을 사용한 인증을 권장하지만 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)도 사용할 수 있습니다. GitHub에서 지정한 모든 필수 환경 변수가 서버 환경에 포함되어 있는지 확인하세요. 변수가 없으면 Tuist는 GitHub 인증을 무시합니다. GitHub 앱을 올바르게 설정하려면:
- GitHub 앱의 일반 설정에서:
    - `Client ID`를 복사하여 `TUIST_GITHUB_APP_CLIENT_ID`로 설정하세요
    - 새 `client secret`를 생성하고 복사하여 `TUIST_GITHUB_APP_CLIENT_SECRET`로 설정하세요
    - `Callback URL`를 `http://YOUR_APP_URL/users/auth/github/callback`로 설정하세요. `YOUR_APP_URL`는 서버의 IP 주소일 수도 있습니다.
- 다음 권한이 필요합니다:
  - 저장소:
    - 풀 리퀘스트: 읽기 및 쓰기
  - 계정:
    - 이메일 주소: 읽기 전용

`Permissions and events`의 `Account permissions` 섹션에서 `Email addresses` 권한을 `Read-only`로 설정하세요.

그런 다음 Tuist 서버가 실행되는 환경에서 다음 환경 변수를 노출해야 합니다:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 애플리케이션의 클라이언트 ID | 예 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 애플리케이션의 클라이언트 시크릿 | 예 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub로 로그인할 수 있는지 여부입니다. 플랫폼 통합(PR 댓글 등)용으로 구성한 GitHub App은 로그인과 클라이언트 자격 증명을 공유하므로 그렇지 않으면 로그인 옵션으로 표시됩니다. 앱을 유지하면서 로그인 페이지에서 GitHub를 제거하려면 `0`로 설정하세요. | 아니오 | `1` | `0` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2)를 사용하여 Google로 인증을 설정할 수 있습니다. 이를 위해 OAuth 클라이언트 ID 유형의 새 자격 증명을 생성해야 합니다. 자격 증명을 생성할 때 애플리케이션 유형으로 "웹 애플리케이션"을 선택하고 이름을 `Tuist`로 지정한 후 리디렉션 URI를 `{base_url}/users/auth/google/callback`로 설정하세요. 여기서 `base_url`는 호스팅 서비스가 실행 중인 URL입니다. 앱을 생성한 후 클라이언트 ID와 시크릿을 복사하여 각각 `GOOGLE_CLIENT_ID` 및 `GOOGLE_CLIENT_SECRET` 환경 변수로 설정하세요.

> [!NOTE]
> **동의 화면 범위**
>
> 동의 화면을 생성해야 할 수 있습니다. 생성할 때 `userinfo.email` 및 `openid` 범위를 추가하고 앱을 내부용으로 표시하세요.


#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) 프로토콜을 통해 Okta 인증을 활성화할 수 있습니다. Okta에서 [앱을 생성](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)하고 <.localized_link href="/guides/integrations/authentication/sso#okta">이 지침</.localized_link>에 따라 설정해야 합니다.

Okta 애플리케이션 설정 중에 클라이언트 ID와 시크릿을 얻으면 다음 환경 변수를 설정해야 합니다:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | Okta 인증에 사용할 클라이언트 ID입니다. 숫자는 조직 ID여야 합니다. | 예 | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta 인증에 사용할 클라이언트 시크릿 | 예 | | |

숫자 `1`는 조직 ID로 대체해야 합니다. 일반적으로 1이지만 데이터베이스에서 확인하세요.

### 스토리지 환경 구성 {#storage-environment-configuration}

 Tuist는 API를 통해 업로드된 아티팩트를 저장할 스토리지가 필요합니다. Tuist가 효과적으로 작동하려면 **지원되는 스토리지 솔루션 중 하나를 구성하는 것이 필수**입니다.

서버 아티팩트 백엔드를 선택하려면 `TUIST_OBJECT_STORAGE_PROVIDER`를 설정하세요:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | 서버 아티팩트 스토리지 백엔드입니다. S3 호환 스토리지에는 `s3`를, Azure Blob Storage에는 `azure_blob`를 사용하세요. | 아니오 | `s3` | `azure_blob` |

#### S3 호환 스토리지 {#s3compliant-storages}

아티팩트를 저장하기 위해 모든 S3 호환 스토리지 제공자를 사용할 수 있습니다. 스토리지 제공자와의 통합을 인증하고 구성하려면 다음 환경 변수가 필요합니다:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` 또는 `AWS_ACCESS_KEY_ID` | 스토리지 제공자 인증에 사용할 액세스 키 ID | 예 | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` 또는 `AWS_SECRET_ACCESS_KEY` | 스토리지 제공자 인증에 사용할 시크릿 액세스 키 | 예 | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 또는 `AWS_REGION` | 버킷이 위치한 리전 | 아니오 | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` 또는 `AWS_ENDPOINT` | 스토리지 제공자의 엔드포인트 | 예 | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | 아티팩트가 저장될 버킷 이름 | 예 | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | S3 HTTPS 연결을 검증하기 위한 PEM 인코딩 CA 인증서입니다. 자체 서명 인증서나 내부 인증 기관(CA)을 사용하는 격리된 환경에서 유용합니다. | 아니오 | 시스템 CA 번들 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | 스토리지 제공자에 대한 연결을 설정하는 타임아웃(밀리초) | 아니오 | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | 스토리지 제공자로부터 데이터를 수신하는 타임아웃(밀리초) | 아니오 | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | 스토리지 제공자에 대한 연결 풀의 타임아웃(밀리초). 타임아웃 없이 사용하려면 `infinity`를 사용하세요. | 아니오 | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | 풀 내 연결의 최대 유휴 시간(밀리초). 연결을 무기한 유지하려면 `infinity`를 사용하세요. | 아니오 | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | 풀당 최대 연결 수 | 아니오 | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | 사용할 연결 풀의 수 | 아니오 | 시스템 스케줄러 수 | `4` |
| `TUIST_S3_PROTOCOL` | 스토리지 제공자에 연결할 때 사용할 프로토콜(`http1` 또는 `http2`) | 아니오 | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL을 버킷 이름을 서브도메인(가상 호스트)으로 구성할지 여부 | 아니오 | `false` | `1` |

> [!NOTE]
> **환경 변수의 웹 신원 토큰을 사용한 AWS 인증**
>
> 스토리지 제공자가 AWS이고 웹 신원 토큰을 사용하여 인증하려는 경우, 환경 변수 `TUIST_S3_AUTHENTICATION_METHOD`를 `aws_web_identity_token_from_env_vars`로 설정하면 Tuist는 일반적인 AWS 환경 변수를 사용하여 해당 방법을 사용합니다.


#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage의 경우, [이 문서](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)를 따라 `AWS_ACCESS_KEY_ID` 및 `AWS_SECRET_ACCESS_KEY` 쌍을 가져오세요. `AWS_ENDPOINT`는 `https://storage.googleapis.com`로 설정해야 합니다. 다른 환경 변수는 다른 S3 호환 스토리지와 동일합니다.

#### Azure Blob Storage {#azure-blob-storage}

Azure Blob Storage의 경우, `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob`를 설정하고 Azure 스토리지 계정 자격 증명을 구성하세요:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure 스토리지 계정 이름 | 예 | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Azure Blob REST 요청 및 SAS URL 서명에 사용되는 스토리지 계정 액세스 키 | 예 | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | 서버 아티팩트가 저장되는 컨테이너 | 예 | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob 서비스 엔드포인트입니다. `https://<account>.blob.core.windows.net`를 사용하려면 이 값을 생략하세요. | 아니오 | 계정 이름에서 파생됨 | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | 서명된 요청 및 SAS URL에 사용되는 Azure Blob REST API 버전 | 아니오 | `2020-12-06` | `2020-12-06` |

Helm 차트를 사용할 때는 `server.storage.provider=azure_blob`를 설정하고 `server.azureBlob.*`를 채우세요. 차트의 최상위 `objectStorage` 설정은 S3 호환 상태로 유지됩니다. 선택적 캐시 및 레지스트리 미러 워크로드가 여전히 S3 호환 스토리지를 예상하기 때문입니다. 해당 워크로드가 비활성화되고 서버가 Azure Blob을 사용하는 경우, `objectStorage.mode=external`를 설정하고 외부 오브젝트 스토리지 엔드포인트와 자격 증명을 비워 두어 내장 MinIO 서비스가 배포되지 않도록 하세요.

#### 아티팩트 보존 기간 {#artifact-retention}

셀프 호스팅 인스턴스에서는 아티팩트 정리가 기본적으로 비활성화되어 있습니다. 지원되는 각 아티팩트 유형에는 고유한 환경 변수가 있습니다. 해당 아티팩트 유형의 정리를 활성화하려면 변수를 양의 정수 일수로 설정하세요. 변수를 설정하지 않거나 비워 두면 해당 아티팩트 유형에 대해서만 정리가 비활성화됩니다.

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

Helm 차트를 사용할 경우, 동일한 기간을 맵으로 구성하세요:

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

여섯 개의 키는 모두 선택 사항입니다. 이 예제는 독립적인 보존 기간을 가진 모든 지원 아티팩트 유형을 활성화합니다. 특정 아티팩트 유형의 정리를 비활성화 상태로 유지하려면 키를 생략하거나 값을 비워 두세요. 셀프 호스팅 보존 기간에는 30일 최대 제한이 없습니다. 양의 정수가 아닌 값으로 구성하면 서버 시작 시 실패합니다.

보존 기간 변수를 변경한 후 서버를 재시작하세요. 대기 중인 모든 셀프 호스팅 정리 배치는 파일을 삭제하기 전에 현재 구성을 확인하므로, 변수를 설정 해제하거나 비워 두거나 기간을 늘리면 재시작 후에도 대기 중인 작업으로부터 파일이 보호됩니다.

| 환경 변수 | 오브젝트 스토리지에서 제거되는 아티팩트 파일 |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode 캐시, 레거시 콘텐츠 주소 지정 스토리지 캐시, 모듈 캐시 및 Gradle 캐시 파일 |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | 앱 미리보기 빌드 및 아이콘 |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | 현재 및 레거시 빌드 아카이브 |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | 결과 번들, 호출 기록 및 세션 아카이브를 포함하여 만료된 실행의 아티팩트 접두사 아래에 저장된 모든 오브젝트 |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | 테스트 실행 첨부 파일 |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | 테스트 샤드 번들 |

예약된 정리는 아티팩트 블롭만 제거합니다. 해당하는 PostgreSQL 및 ClickHouse 행은 보존되므로, 다운로드 기간이 만료된 후에도 대시보드에서 빌드, 테스트, 실행, 미리보기 및 샤드 메타데이터를 계속 볼 수 있습니다. 이 구성은 ClickHouse 테이블 보존 규칙을 변경하지 않습니다.

### 이메일 구성 {#email-configuration}

Tuist는 사용자 인증 및 트랜잭션 알림(예: 비밀번호 재설정, 계정 알림)을 위해 이메일 기능이 필요합니다. 현재 이메일 제공자로 **Mailgun만 지원**됩니다.

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | Mailgun 인증을 위한 API 키 | 예* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | 이메일이 발송될 도메인 | 예* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | "보내는 사람" 필드에 표시될 이메일 주소 | 예* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 사용자 답장을 위한 선택적 회신 주소 | 아니오 | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | 새 사용자 등록 시 이메일 확인을 건너뜁니다. 활성화되면 사용자가 자동으로 확인되며 등록 직후 즉시 로그인할 수 있습니다. | 아니오 | 이메일이 구성되지 않은 경우 `true`, 이메일이 구성된 경우 `false` | `true`, `false`, `1`, `0` |

\* 이메일 구성 변수는 이메일을 보내려는 경우에만 필요합니다. 구성되지 않으면 이메일 확인이 자동으로 건너뜹니다.

> [!NOTE]
> **SMTP 지원**
>
> 범용 SMTP 지원은 현재 사용할 수 없습니다. 온프레미스 배포에 SMTP 지원이 필요한 경우 요구 사항을 논의하기 위해 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의하세요.


> [!NOTE]
> **인터넷 격리 환경 배포**
>
> 인터넷 액세스나 이메일 제공자 구성 없이 온프레미스로 설치하는 경우, 기본적으로 이메일 확인이 자동으로 건너뜁니다. 사용자는 등록 직후 즉시 로그인할 수 있습니다. 이메일이 구성되어 있더라도 확인을 건너뛰려면 `TUIST_SKIP_EMAIL_CONFIRMATION=true`로 설정하세요. 이메일이 구성되었을 때 이메일 확인을 필수로 하려면 `TUIST_SKIP_EMAIL_CONFIRMATION=false`로 설정하세요.


### Git 플랫폼 구성 {#git-platform-configuration}

Tuist는 풀 리퀘스트에 댓글을 자동으로 게시하는 것과 같은 추가 기능을 제공하기 위해 <.localized_link href="/guides/server/authentication">Git 플랫폼과 통합</.localized_link>할 수 있습니다.

#### GitHub {#platform-github}

셀프 호스팅 Tuist 서버는 `https://tuist.dev`에서 실행되는 GitHub 앱을 설치할 수 없습니다. GitHub 앱은 이를 등록한 서버에 바인딩되므로, 여러분의 배포에는 github.com에 자체 앱이 필요합니다.

##### 앱 등록 {#platform-github-registering-the-app}

GitHub 조직 소유의 [GitHub 앱 만들기](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps). OAuth 앱을 만든 경우가 아니라면 인증용으로 만든 앱을 재사용할 수 있습니다. `YOUR_APP_URL`를 `TUIST_APP_URL` 값으로 대체하여 다음과 같이 구성하세요:

| 설정 | 값 |
| --- | --- |
| 콜백 URL | `YOUR_APP_URL/users/auth/github/callback` 및 `YOUR_APP_URL/integrations/github/authorize` |
| 설정 URL | `YOUR_APP_URL/integrations/github/setup` |
| 업데이트 시 리디렉션 | 활성화됨 |
| 웹훅 URL | `YOUR_APP_URL/webhooks/github` |
| 웹훅 시크릿 | 임의의 문자열. 이를 `TUIST_GITHUB_APP_WEBHOOK_SECRET`로 설정합니다. |

다음 리포지토리 권한을 부여하세요:

| 권한 | 액세스 |
| --- | --- |
| 콘텐츠 | 읽기 전용 |
| 메타데이터 | 읽기 전용 |
| 이슈 | 읽기 및 쓰기 |
| 풀 리퀘스트 | 읽기 및 쓰기 |
| 체크 | 읽기 및 쓰기 |

**멤버: 읽기 전용** 조직 권한도 부여하세요. github.com 설정 중 Tuist는 조직 설치를 연결하는 사람이 해당 리포지토리에 액세스할 수 있는 사람이 아닌 활성 GitHub 조직 소유자인지 확인합니다.

앱을 `Check run`, `Pull request` 및 `Issue comment` 이벤트에 구독하세요.

GitHub가 설치자를 설정 URL로 보내도록 **설치 중 사용자 승인 요청(OAuth)** 을 비활성화된 상태로 유지하세요. Tuist는 추가 `/integrations/github/authorize` 콜백을 사용하여 별도의 승인 단계를 시작하고 설치 소유권을 확인합니다. GitHub에서 설치가 시작되면 설치자가 Tuist 조직을 선택합니다. Tuist에서 시작된 설치는 해당 조직을 유지합니다.

##### 서버 구성 {#platform-github-configuring-the-server}

다음 환경 변수를 설정한 후 서버를 재시작하세요:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | 앱의 슬러그로, 공개 페이지 URL `https://github.com/apps/<slug>`의 마지막 경로 구성 요소입니다. | 예 | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | 설치 소유권을 확인하는 데 사용되는 숫자 앱 ID | 예 | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub 애플리케이션의 클라이언트 ID | 예 | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 애플리케이션의 클라이언트 시크릿 | 예 | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 애플리케이션의 Base64로 인코딩된 개인 키. 플랫폼이 줄 바꿈을 처리하는 방식에 민감한 `TUIST_GITHUB_APP_PRIVATE_KEY`보다 선호됩니다. | 예 | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | GitHub 애플리케이션에 구성된 웹훅 시크릿 | 아니오 | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **필수 앱 자격 증명 모두 구성**
>
> 조직의 통합 페이지에서 **GitHub 앱 설치** 버튼은 `TUIST_GITHUB_APP_NAME`, `TUIST_GITHUB_APP_CLIENT_ID`, `TUIST_GITHUB_APP_CLIENT_SECRET` 및 개인 키가 모두 설정될 때까지 비활성화 상태로 유지됩니다. 설치 소유권을 확인하려면 숫자 `TUIST_GITHUB_APP_ID`도 필요합니다. 설치 URL에는 앱 슬러그가 포함되므로, 특히 `TUIST_GITHUB_APP_NAME`가 누락되면 GitHub가 404로 응답하는 링크가 생성됩니다.

서버가 재시작되면 조직 관리자는 <.localized_link href="/guides/integrations/gitforge/github">GitHub 통합 가이드</.localized_link>에 따라 앱을 설치하고 리포지토리를 프로젝트에 연결합니다.

##### OIDC 인증은 이에 의존합니다 {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 인증</.localized_link>은 CI 토큰의 리포지토리 클레임을 프로젝트에 연결된 리포지토리와 비교하여 해결하며, 연결은 설치된 GitHub 앱을 통해서만 생성할 수 있습니다. CI 워크플로우가 토큰 없이 `tuist auth login`를 실행하기 전에 위의 설정을 완료하세요.

Tuist 서버는 서명 키를 가져오기 위해 CI 제공업체의 OIDC 발급자에 대한 아웃바운드 액세스도 필요합니다:

| CI 제공업체 | 호스트 |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

위의 환경 변수는 Tuist의 github.com 앱만 구성합니다. 대신 Tuist를 GitHub Enterprise Server(GHES) 인스턴스와 통합하려면 조직 관리자가 통합 페이지의 **Enterprise server** 탭으로 전환하고 GHES 기본 URL을 입력합니다. 그러면 Tuist는 GHES 인스턴스에 새로운 Tuist 앱을 등록하기 위해 GitHub의 [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)를 안내합니다. 새 앱의 자격 증명은 설치별로 암호화되어 저장되며 추가 `TUIST_GITHUB_APP_*` 환경 변수는 필요하지 않습니다.

#### Origin {#platform-origin}

셀프 호스팅 Tuist 서버에는 자체 Origin 앱이 필요하며, 배포의 URL과 서명 키로 구성해야 합니다. 설치와 자격 증명이 독립적으로 유지되도록 각 Tuist 환경마다 별도의 앱을 등록하세요.

##### 앱 등록 {#platform-origin-registering-the-app}

1. Ed25519 지원이 포함된 OpenSSL을 사용하여 Ed25519 서명 키 쌍을 생성하세요:

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. [Origin 앱 설정](https://cursor.com/codebase/settings/apps)에서 앱을 만드세요. `origin-app-public.pem`의 내용을 공개 서명 키로 등록하세요. `origin-app-private.pem`는 비밀로 유지하세요. 이를 Cursor에 업로드하지 않고 Tuist 서버에 제공합니다.
3. 다음 설정을 구성하고 `YOUR_APP_URL`를 Tuist 배포의 HTTPS 기본 URL로 대체하세요:

   | 설정 | 값 |
   | --- | --- |
   | 홈페이지 URL | `YOUR_APP_URL` |
   | 리디렉션 URI | `YOUR_APP_URL/integrations/origin/setup` |
   | 웹훅 URL | `YOUR_APP_URL/webhooks/origin` |

4. `app_`로 시작하는 등록된 앱 ID를 복사하세요.

Tuist는 설치 중에 다음 권한을 요청합니다:

| 범위 | 사용 목적 |
| --- | --- |
| `repository:pull_requests:read` | 풀 리퀘스트와 현재 헤드 커밋을 찾습니다. |
| `repository:pull_requests:reviews:write` | 보고서 댓글을 읽고, 게시하고, 업데이트합니다. Origin에는 해당하는 리뷰 읽기 권한이 포함되어 있습니다. |
| `repository:metadata:read` | 리포지토리를 발견하고 기본 브랜치를 읽습니다. Origin에 의해 자동으로 부여됩니다. |

선택적 리포지토리 웹훅 이벤트는 선택하지 않은 상태로 두세요. 설치 라이프사이클 알림으로 충분하며 소스 코드 접근, 병합 권한 및 체크 실행 권한은 필요하지 않습니다.

##### 서버 구성 {#platform-origin-configuring-the-server}

다음 환경 변수를 설정한 후 서버를 재시작하세요:

| 환경 변수 | 설명 | 필수 | 기본값 | 예시 |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | Origin 앱 설정에서 복사한 앱 ID입니다. | 예 | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `BEGIN PRIVATE KEY` 및 `END PRIVATE KEY` 줄과 모든 줄 바꿈을 포함하여 `origin-app-private.pem`의 전체 내용입니다. | 예 | | `-----BEGIN PRIVATE KEY-----...` |

비밀 키를 배포의 시크릿 매니저에 저장하세요. 멀티라인 PEM 형식을 유지해야 하며 이 설정은 base64로 인코딩된 대체 값을 허용하지 않습니다. 키를 소스 제어에 커밋하거나 로그에 노출해서는 안 됩니다. 두 변수 모두 동일한 등록된 앱에 속해야 합니다.

Tuist 서버는 `api.cursor.com`에 대한 아웃바운드 HTTPS 액세스가 필요합니다. Cursor는 웹훅 URL로 요청을 전달할 수 있어야 하며 관리자는 브라우저에서 리디렉션 URI로 돌아갈 수 있어야 합니다. 등록된 두 URL 모두 배포의 HTTPS 기본 URL과 일치해야 합니다.

##### 앱 설치 {#platform-origin-installing-the-app}

서버가 재시작되면 관리자가 **설정 → 통합**을 열고 Origin 아래의 **연결**을 선택한 다음 적절한 Origin 계정과 리포지토리에 대한 앱 액세스를 승인합니다. 이 과정에서 Tuist 조직은 유지됩니다. 대신 Origin에서 직접 시작한 설치는 관리자에게 로그인하고 연결할 Tuist 조직을 선택하도록 요청합니다. 그런 다음 **새 프로젝트 연결 추가**를 선택하여 Tuist 프로젝트를 네이티브 리포지토리에 연결합니다.

프로젝트 연결 및 결과 업로드 요구 사항에 대해서는 <.localized_link href="/guides/integrations/gitforge/origin">Origin 통합 가이드</.localized_link>를 따르세요. 앱을 설치해도 빌드 또는 테스트 워크플로우가 시작되지 않으며 해당 워크플로우는 계속 Tuist 서버에 결과를 보고합니다.

## 로컬에서 테스트하기 {#testing-locally}

인프라에 배포하기 전에 로컬 머신에서 Tuist 서버를 테스트하는 데 필요한 모든 종속성을 포함한 포괄적인 Docker Compose 구성을 제공합니다:

- PostgreSQL 15
- 분석용 ClickHouse 26.5
- 조정을 위한 ClickHouse Keeper
- S3 호환 스토리지를 위한 MinIO
- 로컬 셀프 호스팅 캐시 테스트를 위한 Kura
- 데이터베이스 관리를 위한 pgweb

> [!CAUTION]
> **라이선스 필요**
>
> 로컬 개발 인스턴스를 포함하여 Tuist 서버를 실행하려면 유효한 `TUIST_LICENSE` 환경 변수가 법적으로 필요합니다. 라이선스가 필요하면 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의하세요.


**빠른 시작:**

1. 구성 파일 다운로드:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 환경 변수 구성:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   번들된 ClickHouse 서비스는 다음과 같은 선택적 운영 로그 제어를 허용합니다:

   | 환경 변수 | 설명 | 기본값 | 예시 |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | ClickHouse `system.*` 로그 테이블(`text_log`, `query_log`, `trace_log`, `metric_log`, `part_log` 등)의 보관 기간(일) | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse 서버 로거 및 `system.text_log` 수준 | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | 시스템 로그 테이블을 대체할 때 ClickHouse가 남기는 `<name>_N` 테이블을 어떻게 처리할지 지정합니다. `ignore`는 테이블을 유지하고, `delete`는 테이블을 삭제합니다. | `ignore` | `delete` |

3. 모든 서비스 시작:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   Apple Silicon에서는 Docker Desktop이 Tuist 및 종속성 이미지의 `linux/arm64` 변형을 자동으로 가져옵니다. 디버깅을 위해 amd64 에뮬레이션을 강제하려면 `DOCKER_DEFAULT_PLATFORM=linux/amd64`로 Compose를 실행하세요.

   번들된 compose 파일은 영구 데이터를 위해 이름이 지정된 Docker 볼륨을 사용합니다. 이를 호스트 바인드 마운트로 대체하는 경우 먼저 호스트 디렉터리를 생성하고 컨테이너 사용자가 쓸 수 있도록 권한을 설정하세요. 특히 ClickHouse 및 ClickHouse Keeper 데이터 디렉터리에 주의하세요.

4. 서버에 접속: http://localhost:8080

**서비스 엔드포인트:**
- Tuist 서버: http://localhost:8080
- Kura 캐시 (HTTP + REAPI gRPC 단일 포트): http://localhost:4000
- MinIO 콘솔: http://localhost:9003 (인증 정보: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus 메트릭: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**일반 명령어:**

서비스 상태 확인:
```bash
docker compose ps
# or: podman compose ps
```

로그 보기:
```bash
docker compose logs -f tuist
```

서비스 중지:
```bash
docker compose down
```

모두 초기화(모든 데이터 삭제):
```bash
docker compose down -v
```

**구성 파일:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 전체 Docker Compose 구성
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse 구성
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper 구성
- [.env.example](/server/self-host/.env.example) - 환경 변수 예제 파일

## Helm을 사용한 Kubernetes {#kubernetes-with-helm}

Tuist는 Kubernetes 배포를 위한 공식 Helm 차트를 제공합니다. 이 차트는 Tuist 서버와 캐시 서비스를 패키징하며 필요에 따라 외부 제공자로 교체할 수 있는 내장 인프라 종속성을 포함합니다.

### 차트 설치 {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

특정 차트 버전을 고정하려면:

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### 라이선스 {#helm-license}

`server.license.key` 값은 표준 라이선스 키와 격리된 설치를 위한 Base64 인코딩 라이선스 인증서를 모두 허용하며 서버가 자동으로 유형을 감지합니다.

`--set`로 라이선스를 전달하면 빠르게 설치할 수 있습니다. 값을 버전 관리 시스템에서 관리하는 경우 Vault, Sealed Secrets 또는 SOPS 등을 사용해 Helm 외부에서 관리하는 Kubernetes Secret에 라이선스를 저장하고 차트가 이를 참조하도록 설정하세요:

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` 아래의 항목은 라이선스 값(라이선스 키 또는 격리된 설치를 위한 Base64 인코딩 라이선스 인증서)을 보유하는 Secret의 필드 이름을 지정합니다. `existingSecretKeys` 아래의 각 항목은 차트의 기본 키 이름으로 설정되므로 위 `certificateBase64`와 같이 Secret에 없는 항목은 빈 문자열로 설정하세요. 그렇지 않으면 포드가 존재하지 않는 키를 참조하여 시작에 실패합니다. 차트를 설치하거나 업그레이드하기 전에 릴리스 네임스페이스에 Secret을 생성하세요.

라이선스는 `server.license.key` 또는 `server.license.existingSecret` 중 하나의 소스로만 구성하세요. 아무것도 설정되지 않거나 소스가 결합되면 차트 렌더링이 실패합니다. `server.extraEnv`를 통해 전달된 라이선스는 소스로 간주되지 않으므로 대신 `existingSecret`를 사용하세요.

### 인프라 종속성 {#helm-infrastructure-dependencies}

차트는 `postgresql`, `clickhouse`, `objectStorage` 세 가지 인프라 종속성을 관리합니다. 각각 기본적으로 **내장** 모드로 설정되어 차트가 클러스터 내부에 배포합니다. 대신 외부 인스턴스를 사용하려면 종속성의 `mode`를 `external`로 설정하고 `values.yaml`에 연결 세부 정보를 입력하세요. 예를 들어 외부 PostgreSQL 데이터베이스를 사용하려면:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

PostgreSQL 자격 증명을 Helm 외부에서 관리하는 경우 기존 Kubernetes Secret을 참조하도록 차트를 설정하세요:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

차트는 Secret에서 호스트, 사용자 이름, 비밀번호를 읽고 Kubernetes 환경 변수 치환을 통해 `DATABASE_URL`를 구성하므로 비밀번호가 Helm 매니페스트에 노출되지 않습니다. Secret의 비밀번호 값은 데이터베이스 URL에 삽입되므로 URL에 안전한 형식이어야 합니다.

동일한 패턴이 `clickhouse` 및 `objectStorage`에도 적용됩니다. 구성 가능한 전체 필드는 차트의 `values.yaml`에서 각 섹션 아래의 `external` 블록을 참조하세요.

### 공유 스케줄링 및 라벨 {#helm-shared-scheduling-and-labels}

차트는 `global` 아래에 공유 포드 설정을 소수로 노출하여 운영자가 모든 워크로드에 대해 동일한 값을 반복하지 않고도 배포를 클러스터에 맞게 조정할 수 있도록 합니다:

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

다음과 같은 경우 이 설정을 사용하세요:

- 모든 포드에 클러스터별 라벨 추가
- 개인 레지스트리에서 미러링된 이미지 가져오기
- 전용 노드 풀 대상 지정
- Tuist 워크로드용으로 예약된 테인트(taint)가 있는 노드에 포드 허용

### 워크로드 아이덴티티 및 서비스 계정 {#helm-workload-identity}

차트는 애플리케이션 워크로드별로 서비스 계정의 범위를 지정하여 필요한 곳에만 아이덴티티를 부여할 수 있도록 합니다:

- `server.serviceAccount`는 Tuist 서버 배포 및 마이그레이션 작업에 적용됩니다
- `cache.serviceAccount`는 캐시 배포에 적용됩니다

예를 들어, 캐시가 EKS에서 외부 S3 버킷을 사용하는 경우 내장 데이터베이스에 동일한 IAM 역할을 연결하지 않고도 캐시 워크로드에 대해 IRSA를 활성화할 수 있습니다:

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### 호환성 재정의 {#helm-compatibility-overrides}

차트는 스토리지 및 메시 관련 조정을 옵트인으로 유지하여 기본값이 휴대성을 갖도록 합니다:

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      supersededTables: delete
      level: warning
```

클러스터에서 필요할 때만 이러한 재정의를 사용하세요:

- `cache.podSecurityContext`는 기본적으로 비어 있습니다. 스토리지 클래스 또는 CSI 드라이버가 마운트된 볼륨에서 공유 그룹 소유권을 필요로 하는 경우 `fsGroup`를 설정하세요.
- `clickhouse.embedded.service.nativePort`는 ClickHouse의 표준 `9000` 네이티브 서비스 포트로 기본 설정되며, 서비스 메시나 플랫폼 예약이 해당 포트와 충돌할 때 변경할 수 있습니다.
- `clickhouse.embedded.systemLogs.ttlDays`는 기본적으로 비어 있어 `system.text_log`, `system.query_log`, `system.trace_log`, `system.metric_log`, `system.part_log`와 같은 내장 내부 로그 테이블에 대한 ClickHouse의 무제한 보존 정책을 그대로 둡니다. 이를 설정하면 해당 테이블이 한 번 재정의되므로 `supersededTables: delete`와 함께 채택하세요 — 자세한 내용은 <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">운영 로그 보존 제한</.localized_link>을 참조하세요.
- `clickhouse.embedded.systemLogs.level`는 내장 ClickHouse 서버 로거 및 `system.text_log`에 대해 기본적으로 `information`로 설정됩니다. `ttlDays`와 달리 이는 테이블 정의의 일부가 아니므로 변경해도 테이블이 재정의되지 않습니다.
- `clickhouse.embedded.systemLogs.supersededTables`는 기본적으로 `ignore`로 설정되며 시스템 로그 테이블을 재정의할 때 ClickHouse가 남기는 `<name>_N` 테이블의 처리 방식을 결정합니다. 각 `helm upgrade` 시점에 이 테이블들을 삭제하려면 `delete`로 설정하세요.
- `ttlDays` 및 `level`에 대한 편집은 다음 ClickHouse 포드 재시작 시 반영됩니다. 둘 다 `subPath` 마운트이며 ConfigMap이 변경될 때 차트가 StatefulSet을 롤링하지 않기 때문입니다.

### 관찰 가능성 {#helm-observability}

차트에는 선택적 관찰 가능성 스택(OpenTelemetry Collector, Prometheus, Grafana, Loki, Tempo)이 포함되어 있습니다. 기본적으로 **비활성화**되어 있습니다. `values.yaml`에서 이를 활성화하려면:

```yaml
# values.yaml
observability:
  enabled: true
```

활성화되면 Logs, Traces, Metrics 드릴다운이 사전 구성된 Grafana를 사용할 수 있습니다. 외부 관찰 가능성을 위해서는 이를 비활성화 상태로 두고 `server.extraEnv`를 통해 엔드포인트를 구성하세요:

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### 값 참조 {#helm-values-reference}

구성 가능한 값의 전체 목록은 차트의 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)를 참조하세요.

## 배포 {#deployment}

공식 Tuist Docker 이미지는 다음 위치에서 사용할 수 있습니다:
```
ghcr.io/tuist/tuist
```

공개된 이미지에는 `.xcactivitylog` 아카이브를 위한 내장 Linux 빌드 처리 기능이 포함되어 있으므로 자체 호스팅 배포는 추가 서비스를 실행하지 않고도 빌드를 처리할 수 있습니다. `ProcessBuildWorker` Oban 작업은 각 서버 포드 내에서 인프로세스로 실행됩니다. 빌드 처리를 전용 복제본 집합으로 오프로드하려는 경우(예: 웹 계층과 독립적으로 파싱 처리량을 확장하기 위해) Helm 차트에서 `processor.enabled: true`를 설정하세요. 차트는 동일한 이미지를 큐 전용 소비자(`TUIST_PROCESSOR_MODE=true`)로 배포합니다. 전체 구성 옵션은 [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml)를 참조하세요.

> [!NOTE]
> `.xcresult` 파싱은 Xcode의 `xcresulttool`에 의존하므로 macOS에서만 실행할 수 있습니다. CLI는 자체 호스팅 배포를 위해 이를 투명하게 처리합니다. `tuist test`는 `tuist.dev`가 아닌 서버에 대해 기본적으로 **로컬** 처리 모드로 동작하며, 개발자 머신(빌드 자체를 위해 이미 Xcode가 설치됨)에서 xcresult를 파싱하고 구조화된 결과를 업로드합니다. 테스트 결과는 추가 인프라 없이 수집됩니다.

### Docker 이미지 가져오기 {#pulling-the-docker-image}

다음 명령어를 실행하여 이미지를 가져올 수 있습니다:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

이미지는 `linux/amd64` 및 `linux/arm64` 모두를 위해 공개되므로 Docker는 호스트의 네이티브 Linux 아키텍처를 자동으로 선택합니다.

또는 특정 버전을 가져오세요:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker 이미지 배포 {#deploying-the-docker-image}

Docker 이미지의 배포 프로세스는 선택한 클라우드 제공업체와 조직의 지속적 배포 접근 방식에 따라 달라집니다. [Kubernetes](https://kubernetes.io/)와 같은 대부분의 클라우드 솔루션 및 도구는 Docker 이미지를 기본 단위로 사용하므로 이 섹션의 예제는 기존 설정과 잘 맞을 것입니다.

> [!WARNING]
> 배포 파이프라인에서 서버가 실행 중인지 검증해야 하는 경우 `/ready`에 `GET` HTTP 요청을 보내고 응답에서 `200` 상태 코드를 어설션할 수 있습니다.


#### Fly {#fly}

[Fly](https://fly.io/)에 앱을 배포하려면 `fly.toml` 구성 파일이 필요합니다. 지속적 배포(CD) 파이프라인 내에서 동적으로 생성하는 것을 고려하세요. 아래는 참고용 예제입니다:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

그런 다음 `fly launch --local-only --no-deploy`를 실행하여 앱을 시작할 수 있습니다. 이후 배포에서는 `fly launch --local-only` 대신 `fly deploy --local-only`를 실행해야 합니다. Fly.io는 비공개 Docker 이미지 가져오기를 허용하지 않으므로 `--local-only` 플래그를 사용해야 합니다.


## Prometheus 메트릭 {#prometheus-metrics}

Tuist는 자체 호스팅 인스턴스를 모니터링할 수 있도록 `/metrics`에서 Prometheus 메트릭을 노출합니다. 이러한 메트릭에는 다음이 포함됩니다:

### Finch HTTP 클라이언트 메트릭 {#finch-metrics}

Tuist는 HTTP 클라이언트로 [Finch](https://github.com/sneako/finch)를 사용하며 HTTP 요청에 대한 상세 메트릭을 노출합니다:

#### 요청 메트릭
- `tuist_prom_ex_finch_request_count_total` - Finch 요청 총 횟수(카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 요청 지속 시간(히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 요청 예외 총 횟수(카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 풀 큐 메트릭
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 연결 풀 큐에서 대기한 시간(히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 사용되기 전 연결이 유휴 상태였던 시간(히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 큐 예외 총 횟수(카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 메트릭
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 연결 설정에 소요된 시간(히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `error`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 연결 시도 총 횟수(카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`

#### 전송 메트릭
- `tuist_prom_ex_finch_send_duration_milliseconds` - 요청 전송에 소요된 시간(히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 전송 전 연결이 유휴 상태였던 시간(히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

모든 히스토그램 메트릭은 상세 분석을 위해 `_bucket`, `_sum` 및 `_count` 변형을 제공합니다.

### 기타 메트릭

Finch 메트릭 외에도 Tuist는 다음에 대한 메트릭을 노출합니다:
- BEAM 가상 머신 성능
- 사용자 정의 비즈니스 로직 메트릭(스토리지, 계정, 프로젝트 등)
- 데이터베이스 성능(Tuist 호스팅 인프라 사용 시)

## 운영 {#operations}

Tuist는 `/ops/` 아래에서 인스턴스를 관리하는 데 사용할 수 있는 유틸리티 세트를 제공합니다.

> [!WARNING]
> **인증**
>
> 이메일 도메인이 `TUIST_OPERATOR_EMAIL_DOMAIN`(기본값 `tuist.dev`)와 일치하는 확인된 사용자만 `/ops/` 엔드포인트에 접근할 수 있습니다.


- **오류(`/ops/errors`):** 애플리케이션에서 발생한 예상치 못한 오류를 확인할 수 있습니다. 이는 디버깅과 문제 원인 파악에 유용하며, 문제가 발생하면 이 정보를 공유해 달라고 요청할 수 있습니다.
- **대시보드(`/ops/dashboard`):** 애플리케이션의 성능과 상태(예: 메모리 사용량, 실행 중인 프로세스, 요청 수)에 대한 통찰을 제공하는 대시보드를 확인할 수 있습니다. 이 대시보드는 현재 사용 중인 하드웨어가 부하를 처리하기에 충분한지 이해하는 데 매우 유용합니다.
