---
{
  "title": "셀프 호스트 캐시",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "셀프 호스트 캐시 노드를 배포하고 Tuist에 연결합니다."
}
---

# 셀프 호스팅 캐시 {#self-hosted-cache}

셀프 호스팅 캐시 노드를 사용하면 빌드 산출물을 생성하고 소비하는 머신 근처에 빌드 아티팩트와 캐시 메타데이터를 보관할 수 있습니다. CI, 개발자 오피스, 원격 워크스테이션 또는 리전별 컴퓨팅 클러스터 전반에서 캐시 지연 시간이 중요한 경우 사용하세요.

목표는 중앙 캐시가 우연히 가까운 한 환경뿐만 아니라 모든 곳에서 저지연 캐싱을 제공하는 것입니다. 각 캐시 노드는 로컬 디스크에서 읽기 및 쓰기를 처리하며, 메시는 피어 간에 아티팩트와 메타데이터를 복제하여 다른 위치도 시간이 지남에 따라 동일한 캐시의 이점을 누릴 수 있도록 합니다.

> [!NOTE]
> Tuist의 셀프 호스팅 캐시 노드는 Tuist의 분산형 캐시 메시인 [Kura](https://github.com/tuist/tuist/tree/main/kura)로 구동됩니다. Kura는 캐시 노드의 데이터 플레인으로, 캐시 읽기 및 쓰기를 제공하고 로컬 상태를 디스크에 저장하며 아티팩트와 메타데이터를 피어 노드에 복제합니다.

## 셀프 호스팅 캐시가 Tuist와 어떻게 연동되는지 {#how-self-hosted-cache-fits-with-tuist}

Tuist의 관리형 캐시는 `https://<account>.cache.tuist.dev`를 사용합니다. 셀프 호스팅 Tuist 서버에서는 CLI가 서버의 `TUIST_CACHE_ENDPOINTS` 설정에서 캐시 URL을 가져옵니다. 이를 주 캐시 서버 또는 로드 밸런서의 URL로 설정하세요. 여러 URL이 포함된 경우 첫 번째 URL이 사용됩니다.

**호스팅된 Tuist 서버**에 연결된 비공개/맞춤 캐시 노드의 경우, 개발자 셸과 CI에서 명시적 엔드포인트를 설정하세요:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

이 재정의는 두 서버 유형 모두에서 우선 적용되며 셀프 호스팅 Tuist 서버에서는 선택 사항입니다. Xcode 캐시 데몬의 경우, LaunchAgent가 업데이트된 환경을 수신하도록 설정 후 `tuist setup cache`를 다시 실행하세요.

셀프 호스팅 Tuist 서버는 정적 구성에서 엔드포인트를 가져옵니다. Tuist 호스팅 서버에서는 노드가 자격 증명으로 인증하고 자체 등록합니다. 아래 두 섹션 중 하나로 노드를 먼저 배포한 다음 [Tuist에 노드 연결](#connect-nodes-to-tuist)을 참조하세요.

## Kubernetes에 배포 {#deploy-on-kubernetes}

Kura는 GitHub Container Registry를 통해 Helm 차트로 배포됩니다. 영구 볼륨, 피어 검색을 위한 헤드리스 서비스, HTTP 및 gRPC 트래픽을 위한 일반 서비스를 갖춘 `StatefulSet`로 Kura를 배포합니다.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

동일 클러스터 내 셀프 호스팅 Tuist 서버의 경우, 주 캐시 엔드포인트를 구성하세요:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

이렇게 하면 서버 Pod에 `TUIST_CACHE_ENDPOINTS`가 설정됩니다. 개발자 머신과 CI가 접근할 수 있는 주소를 사용하세요. 위 클러스터 내부 서비스 이름은 클러스터 내에서 실행되는 클라이언트에 적합합니다.

> [!IMPORTANT]
> 모든 Kura 노드는 고유한 `KURA_DATA_DIR`를 소유해야 합니다. Kura는 데이터 디렉터리에 애플리케이션 수준 쓰기 잠금을 적용하며 정확히 하나의 프로세스만 이를 소유하기를 기대합니다. Kubernetes에서는 Pod당 하나의 영구 볼륨을 사용하세요. Kubernetes 외부에서는 여러 프로세스가 같은 마운트 디렉터리를指向하지 않도록 하세요.

## Kubernetes 없이 배포 {#deploy-without-kubernetes}

Kura는 VM 또는 베어메탈 호스트에서 일반 컨테이너로도 실행할 수 있습니다. 이 모드에서는 프로세스 감독, 영구 스토리지, 라우팅 및 피어 검색을 직접 책임져야 합니다.

최소한 각 노드에는 영구 데이터 디렉터리, 임시 디렉터리, 공개 캐시 포트(하나의 리스너가 HTTP 캐시 API와 REAPI gRPC를 모두 제공), 내부 피어 URL, 그리고 정적 피어 목록 또는 검색 메커니즘이 필요합니다:

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/var/cache/kura/tmp \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

셀프 호스팅 Tuist 서버에서는 개발자 머신과 CI가 접근할 수 있는 주 캐시 URL을 구성하세요:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## 노드를 로드 밸런서 뒤에 배치 {#load-balancers}

클라이언트는 각 캐시 엔드포인트 URL을 HTTP와 gRPC 모두에 사용합니다. HTTP는 헬스 체크와 HTTP 캐시 API용이며, gRPC는 모듈 캐시와 Bazel의 원격 캐시용입니다. 클라이언트와 Kura 사이의 인그레스, 로드 밸런서 또는 CDN은 동일한 호스트명과 포트에서 둘 다 전달해야 합니다. 이는 클라이언트가 받는 모든 엔드포인트에 적용되는데, CLI가 가장 빠르게 응답하는 것을 선택하기 때문입니다. gRPC가 Kura에 도달하지 못하면 CLI는 원격 모듈 캐싱을 사용할 수 없다고 경고하며 로컬 모듈 캐시만 사용합니다.

다음 경로 접두사를 HTTP/2之上的 gRPC로 Kura에 라우팅하고 나머지는 HTTP로 라우팅하세요:

| 경로 접두사 | 사용처 |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | 모듈 캐시, Bazel |
| `/google.bytestream.` | 모듈 캐시, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Bazel 빌드 이벤트 |

Kura는 `KURA_PORT`에서 평문 HTTP/2(h2c)를 수용하며, `KURA_PUBLIC_TLS_CERT_PATH`와 `KURA_PUBLIC_TLS_KEY_PATH`가 설정되면 `KURA_HTTPS_PORT`에서 TLS之上的 HTTP/2를 제공합니다. 프록시가 ingress-nginx처럼 요청 간에 업스트림 연결을 재사용한다면 `KURA_GATEWAY_GRPC_PORT`를 설정하고 해당 포트로 gRPC 트래픽을 보내세요. 이는 gRPC만 제공하므로 HTTP/1.1과 gRPC 요청은 결코 연결을 공유하지 않습니다.

gRPC 경로를 다음과 같이 구성하세요:

- 요청 본문 크기 제한 없음. 업로드는 단일 요청으로 최대 2 GiB까지 하나의 파일을 전송합니다.
- 요청 및 응답 버퍼링 해제.
- 읽기, 전송 및 유휴 시간 초과를 최소 300초로 설정.

Kura는 gRPC 헬스 체크 서비스를 제공하지 않습니다. HTTP로 `/ready`에서 노드를 헬스 체크하세요. 로드 밸런서가 gRPC 헬스 체크를 요구하면 `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities`를 호출하고 gRPC 상태 코드 `0` 및 `16`를 허용하세요. 인증이 활성화된 노드는 토큰 없는 요청에 `16`(`UNAUTHENTICATED`)로 응답합니다.

### ingress-nginx {#load-balancers-ingress-nginx}

Helm 차트를 사용할 때 HTTP 인그레스는 `/`에 유지하고 동일한 호스트에 gRPC 인그레스를 추가하세요. HTTP 인그레스만 TLS를 선언합니다:

```yaml
service:
  gatewayGrpcPort: 4001

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - kura.example.com
      secretName: kura-tls

grpcIngress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /build\.bazel\.remote\.execution\.v2\.
          pathType: ImplementationSpecific
        - path: /google\.bytestream\.
          pathType: ImplementationSpecific
        - path: /build\.bazel\.remote\.asset\.v1\.
          pathType: ImplementationSpecific
        - path: /google\.devtools\.build\.v1\.
          pathType: ImplementationSpecific
```

### AWS Application Load Balancer {#load-balancers-aws-alb}

gRPC 타겟 그룹에는 HTTPS 리스너가 필요합니다. 해당 리스너에서:

1. 기본 규칙을 `KURA_PORT`에서 프로토콜 버전 `HTTP1`을 사용하는 타겟 그룹으로 전달하고, `/ready`에서 HTTP로 헬스 체크하세요.
2. 프로토콜 버전 `gRPC`인 두 번째 타겟 그룹을 생성하고, `KURA_GATEWAY_GRPC_PORT`(또는 `KURA_PORT`)에서 프로토콜 `HTTP`를 사용하거나 `KURA_HTTPS_PORT`에서 프로토콜 `HTTPS`를 사용하세요. 헬스 체크는 위에서 설명한 대로 구성하세요.
3. 경로 패턴 `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` 및 `/google.devtools.build.v1.*`를 두 번째 타겟 그룹으로 전달하는 규칙을 추가하세요.
4. 로드 밸런서의 유휴 시간 초과를 최소 300초로 늘리세요.

### CDN {#load-balancers-cdns}

노드 앞에 위치한 CDN은 gRPC를 지원해야 하며 방화벽 규칙에서 gRPC 경로를 차단해서는 안 됩니다. 클라이언트는 최대 2 MiB 단위로 큰 아티팩트를 업로드하고 노드가 이를 조립하므로, 요청에 큰 본문이나 긴 업로드 시간이 필요하지 않습니다. 모듈 캐시와 Xcode 컴파일레이션 캐시는 이렇게 동작하며, Bazel은 `--experimental_remote_cache_chunking`로 빌드할 때 이렇게 동작합니다(Bazel 8.7 및 9.1 이상). 해당 플래그가 없으면 Bazel은 각 출력을 단일 요청으로 업로드하므로, CDN은 큰 요청 본문과 가장 느린 링크에서 가장 큰 출력에 필요한 만큼의 시간이 걸리는 업로드도 허용해야 합니다. CDN이 이러한 요구 사항을 충족할 수 없으면 클라이언트에 이를 우회하는 호스트 이름(예: DNS 전용 레코드)을 제공하세요.

#### Cloudflare {#load-balancers-cloudflare}

모듈 캐싱은 모든 요금제에서 프록시된 Cloudflare 호스트 이름을 통해 작동합니다. 영역에서:

1. **Network** 아래에서 **gRPC**를 켜세요.
2. **SSL/TLS** 아래에서 암호화 모드를 **Full** 또는 **Full (strict)** 로 설정하세요. Cloudflare는 포트 443에서 오리진에 연결하므로, 오리진은 해당 포트에서 TLS를 제공하고 ALPN을 통해 HTTP/2를 제공해야 합니다.
3. WAF 사용자 정의 규칙이나 관리형 규칙이 위에 나열된 gRPC 경로를 차단하지 않도록 하세요.

Cloudflare는 오리진이 약 2분 후에 응답을 시작하지 않으면 요청을 종료합니다. `--experimental_remote_cache_chunking` 없는 Bazel 업로드는 마지막 바이트가 도착해야만 응답하므로, Cloudflare에서는 그런 업로드가 그보다 오래 걸리면 실패합니다.

## 노드를 Tuist에 연결하기 {#connect-nodes-to-tuist}

클라이언트 라우팅을 구성하고 노드를 Tuist에 등록하여 대시보드에 주소, 준비 상태 및 사용량이 표시되도록 하세요.

**자체 호스팅 Tuist 서버**에서는 위의 배포 섹션에 나와 있는 대로 `TUIST_CACHE_ENDPOINTS`로 엔드포인트를 정적으로 선언합니다. CLI는 처음 구성된 URL을 사용합니다. `TUIST_CACHE_ENDPOINT`는 개별 클라이언트에 대해 해당 URL을 재정의합니다.

**Tuist 호스팅 서버**에서는 개발자 셸과 CI에서 `TUIST_CACHE_ENDPOINT`를 설정하여 캐시 요청을 노드로 라우팅하세요. 각 노드는 생성한 자격 증명으로 인증한 후 주소를 등록하고 대시보드에 준비 상태를 보고합니다. 이 섹션에서는 노드 등록을 다룹니다.

> [!IMPORTANT]
> **Enterprise 요금제**
>
> 자체 호스팅 캐시 노드는 Enterprise 요금제에서 사용할 수 있습니다. 아래에 설명된 **Self-hosted servers** 섹션은 해당 요금제의 계정에만 표시됩니다.

### 노드 자격 증명 생성하기 {#generate-a-node-credential}

Tuist 대시보드에서 계정을 열고 **Cache**로 이동한 후 **Self-hosted servers**를 찾으세요. **Generate credential**을 선택하여 클라이언트 ID와 시크릿을 발급하세요.

자격 증명은 이를 생성한 계정의 트래픽만 승인합니다.

시크릿은 한 번만 표시되며 대화 상자를 닫으면 복구할 수 없으므로, 노드가 읽는 시크릿 저장소에 바로 복사하세요. 자격 증명을 취소하면 이를 사용하는 모든 노드의 인증이 즉시 중단되므로, 사용 중인 자격 증명을 취소하기 전에 대체 자격 증명을 먼저 생성하세요.

### 부팅 시 노드 등록하기 {#enroll-the-node-on-boot}

등록은 노드를 가동하는 권장 방법입니다. `KURA_ENROLL_ON_BOOT`를 설정하고 노드에 자격 증명과 자체 피어 URL을 제공하세요:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

노드는 로컬에서 키 쌍을 생성하므로 비공개 키가 노드를 벗어나지 않으며, 서명된 피어 인증서, 계정 CA, 테넌트 식별자 및 피어 목록을 수신합니다. 이는 수동으로 구성하던 모든 항목입니다. 등록된 노드는 `KURA_TENANT_ID`, `KURA_PEERS` 및 피어 TLS 설정이 필요하지 않습니다.

`KURA_INTERNAL_TLS_*`를 설정하지 않은 상태로 두세요. 등록 과정에서 인증서 자료가 `KURA_DATA_DIR` 아래의 `tls` 디렉터리에 기록됩니다. 등록 대신 직접 인증서를 제공하는 경우에만 이러한 경로를 직접 설정하세요. 자세한 내용은 [캐시 메시 구축하기](#build-a-cache-mesh)를 참조하세요.

계정의 메시에 처음 참여하는 노드는 링의 서비스 멤버가 되기 전에 계정의 기존 캐시를 가져옵니다. 전체 캐시를 수용할 수 있도록 데이터 볼륨 크기를 조정하고, 광역 링크에서는 첫 참여에 시간이 걸릴 것으로 예상하세요. 노드는 동기화가 완료될 때까지 `joining` 상태를 보고한 다음 `serving` 상태로 전환됩니다.

### 엔드포인트 광고하기 {#advertise-the-endpoint}

등록을 통해 메시에 참여합니다. 등록은 노드의 클라이언트 노출 주소와 준비 상태를 Tuist에 보고합니다. 등록 변수를 설정하세요:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

노드는 180초 임대 기간에 대해 60초마다 하트비트를 보냅니다. Tuist는 임대가 만료되면 해당 등록을 사용할 수 없는 것으로 간주합니다. Tuist는 노드를 호출하지 않으므로 인터넷이 아닌 클라이언트로부터 도달 가능하면 충분합니다.

### 노드가 서비스 중인지 확인하기 {#verify-the-node-is-serving}

대시보드의 **Cache**로 돌아가면 노드가 엔드포인트, 리전, 상태 및 마지막 하트비트 정보와 함께 **Registered nodes** 아래에 표시됩니다. 전혀 표시되지 않는 노드는 등록 엔드포인트에 도달하지 못하거나 인증에 실패한 것입니다. 나타난 후 사라지는 노드는 하트비트를 중단했거나 준비 상태 보고를 중지한 것입니다.

### 테넌트 식별자를 계정 핸들과 일치시키기 {#match-the-tenant-identifier}

`KURA_TENANT_ID`는 Tuist 계정 핸들과 동일해야 합니다. 컨트롤 플레인은 하트비트의 테넌트를 자격 증명에서 확인된 계정과 비교하고 불일치 시 `409 tenant_mismatch`로 거부하므로, 잘못된 값을 가진 노드는 인증에는 성공하더라도 등록되지 않습니다.

> [!IMPORTANT]
> Helm 차트와 이 가이드 앞부분의 컨테이너 예제는 모두 이를 기본값 `default`로 설정합니다. 이 값은 테넌트가 로컬 레이블인 자체 호스팅 Tuist 서버에서는 올바르지만, 계정 이름을 지정해야 하는 Tuist 호스팅 서버의 계정에서는 잘못되었습니다. 컨트롤 플레인이 값을 제공하므로 노드를 등록하면 이 문제를 완전히 피할 수 있습니다.

설정되지 않은 `KURA_TENANT_ID`는 검사를 건너뛰지 않습니다. 등록 자체를 비활성화합니다. 노드는 캐시 트래픽을 계속 제공하지만 대시보드에는 아무것도 표시되지 않으며 오류도 보고되지 않습니다. 노드가 정상인데 **Registered nodes**에 누락되어 있다면 이 변수를 먼저 확인하세요.

### 클라이언트가 도달할 수 있는 광고 URL 선택하기 {#choose-an-advertised-url}

`KURA_ADVERTISED_HTTP_URL`와 Tuist 서버 또는 CLI에 구성된 캐시 URL에는 클라이언트가 도달할 수 있는 주소를 사용하세요.

내부 전용 호스트 이름은 이를 사용하도록 구성된 모든 클라이언트가 해당 이름을 해결하고 도달할 수 있을 때 적합합니다. 다른 네트워크의 클라이언트에게는 공유 가능한 도달 주소를 사용하거나 각 환경마다 도달 가능한 캐시 노드를 구성하세요.

## 캐시 메시 구축하기 {#build-a-cache-mesh}

캐시 메시를 사용하면 캐시 용량을 필요한 컴퓨팅 리소스 근처에 배치할 수 있습니다. 한 회사는 주요 CI 러너 근처에 하나의 노드를, 유럽의 개발자 근처에 또 다른 노드를, 미국 사무실이나 지역 빌드 클러스터 근처에 또 다른 노드를 운영할 수 있습니다. 각 위치는 가장 가까운 노드를 통해 읽고 쓰며, Kura는 백그라운드에서 아티팩트와 메타데이터를 복제하므로 다른 위치에서의 이후 빌드가 동일한 출력을 재사용할 수 있습니다.

메시는 노드가 Kura의 내부 피어 포트에서 서로에게 도달할 수 있을 때만 작동합니다. 이 피어 플레인은 Tuist 클라이언트가 사용하는 공개 캐시 엔드포인트와 분리되어 있습니다. Kura는 이를 사용하여 멤버십을 확인하고, 새로 가입한 노드를 백필하며, 로컬 쓰기가 허용된 후 아티팩트를 복제합니다.

노드가 리전, 클라우드, VPC, 사무실 또는 캐시 배포에 완전히 비공개가 아닌 네트워크 간에 통신할 경우 피어 플레인을 [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication)로 보호하는 것을 강력히 권장합니다. mTLS가 활성화되면 Kura는 구성된 CA로 서명된 인증서를 제시하는 피어에게만 내부 복제 엔드포인트를 제공합니다. 피어 인증서는 노드가 서로 호출할 때 사용하는 DNS 이름을 포함해야 하며, 피어 URL은 내부 포트에서 `https://`를 사용해야 합니다.

> [!NOTE]
> Tuist 호스팅 컨트롤 플레인에 등록하는 노드는 등록 과정에서 피어 인증서와 계정 CA를 받으므로, 아래 수동 단계는 등록하지 않는 메시에 적용됩니다.

예를 들어, 이는 작은 메시의 모든 노드가 마운트할 수 있는 개인 CA와 하나의 피어 인증서를 생성합니다. DNS 이름을 `KURA_NODE_URL` 및 `KURA_PEERS`에서 노드가 사용하는 내부 이름으로 바꾸세요.

```bash
mkdir -p kura-peer-tls
cd kura-peer-tls

openssl ecparam -genkey -name prime256v1 -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=kura-peer-ca" \
  -out ca.pem

openssl ecparam -genkey -name prime256v1 -noout -out tls.key
openssl req -new -key tls.key \
  -subj "/CN=kura-peer" \
  -out peer.csr

cat > peer.ext <<'EOF'
subjectAltName = DNS:kura-0.kura-headless.kura.svc.cluster.local,DNS:kura-1.kura-headless.kura.svc.cluster.local,DNS:kura-2.kura-headless.kura.svc.cluster.local,DNS:kura-1.internal,DNS:kura-2.internal
extendedKeyUsage = serverAuth,clientAuth
keyUsage = digitalSignature,keyEncipherment
EOF

openssl x509 -req -in peer.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 730 \
  -sha256 \
  -extfile peer.ext
```

### 노드 간 동기화 {#catch-up-between-nodes}

메시에 가입하거나 재가입하는 노드는 **백필**을 수행합니다. 각 피어의 항목을 최신 순으로 탐색하여 누락된 부분을 가져오는 동안, 라이브 복제는 피어가 보이는 동안 발생한 쓰기를 처리합니다. 백필 패스는 피어의 최신 항목부터 노드의 세그먼트 링 지평선과 마지막 완료된 패스 중 더 오래된 시점까지 되돌아가므로, 노드는 최근 데이터를 보유함이 보장되지만 반드시 모든 데이터를 보유하는 것은 아닙니다. `KURA_BACKFILL_MARGIN_PERCENT`는 지평선이 얼마나 과거까지 설정되는지를 결정합니다.

메시를 실행하기 전에 알아야 할 두 가지 결과가 있습니다:

- 노드는 세그먼트 링이 `KURA_BACKFILL_READY_RING_PERCENT`만큼 채워지거나 **또는** 첫 번째 백필 사이클이 안정화되면 `/ready`를 보고하며, 이후 프로세스 수명 동안 준비 상태가 유지됩니다. 이후의 피어 불안정성은 서비스 중인 노드를 회전에서 제거하지 않습니다.
- 피어가 충분히 오랫동안 도달 불가능할 때도 주기는 안정화됩니다. 유일한 피어가 다운된 노드는 따라서 거의 또는 전혀 데이터를 보유하지 않은 상태에서 Ready 상태가 됩니다. 오류 대신 미스를 제공합니다. 차이를 기준으로 롤아웃을 제어하려면 `/status/rollout`가 `backfill_initial_cycle` (`pending`, `complete` 또는 `degraded`)를 보고합니다.

**백필 변경 사항을跨越하여 메시 업그레이드하기.** 백필 이전의 Kura 릴리스는 이제 제거된 다른 피어 프로토콜을 통해 동기화했습니다. 백필만 지원하는 릴리스를 사용하기 **전에** 모든 노드를 백필을 실행하는 릴리스로 롤링하세요. 두 프로토콜의 노드는 서로 동기화할 수 없습니다. 웜 노드는 볼륨에서 계속 서비스를 제공하지만 격차를 닫는 것을 중단하며, 해당 기간 동안 빈 볼륨으로 시작하는 노드는 결코 Ready 상태가 되지 않습니다. 차트는 `KURA_BACKFILL_ENABLED=true`를 설정하므로 차트 우선 업그레이드는 이를 커버합니다. 차트와 이미지를 함께 이동하는 단일 `helm upgrade`는 이를 커버하지 않습니다.

mTLS 외에도 네트워크 수준 제한을 사용하세요. Kubernetes에서는 Kura를 `StatefulSet`로 실행하여 각 파드에 하나의 영구 볼륨과 피어 검색을 위한 헤드리스 서비스를 구성한 다음, 예를 들어 `NetworkPolicy`를 사용하여 동일한 캐시 배포에 속하는 파드 간에만 내부 피어 포트를 허용하세요. Kubernetes 외부에서는 각 노드에 안정적인 DNS 이름 또는 IP 주소를 부여하고, 다른 노드의 내부 URL로 메시를 시딩하며, 방화벽 규칙 또는 보안 그룹을 사용하여 캐시 노드만이 피어 포트에 도달할 수 있도록 하세요. 공개 캐시 트래픽은 내부 피어 플레인이 아닌 공개 HTTP 또는 gRPC 엔드포인트를 통해 진입해야 합니다.

## 구성 {#configuration}

Helm 차트는 `values.yaml`에서 일반적인 런타임 설정을 렌더링합니다. Kubernetes 없이 Kura를 실행하는 경우 프로세스에 직접 동일한 변수를 설정하세요. 차트가 직접 매핑하지 않는 변수는 `extraEnv` 또는 `extraEnvFrom`를 통해注入할 수 있습니다.

| 환경 변수 | 설명 | 필수 | 기본값 | Helm 값 |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | 공개 캐시 포트. 하나의 리스너가 HTTP 캐시 API, 헬스 엔드포인트 및 Bazel/Buck2 REAPI gRPC(h2c)를 제공합니다. | 예 | 기본값 없음 | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Kura 피어가 사용하는 내부 HTTP 또는 mTLS 포트. | 예 | 기본값 없음 | `peerTls.internalPort` |
| `KURA_TENANT_ID` | 노드의 기본 테넌트 식별자. | 예 | 기본값 없음 | `config.tenantId` |
| `KURA_REGION` | 메트릭스 및 복제 상태에서 사용되는 리전 레이블. | 예 | 기본값 없음 | `config.region` |
| `KURA_TMP_DIR` | 단계적 요청 본문 및 멀티파트 조립을 위한 임시 디렉터리. | 예 | 기본값 없음 | `/var/cache/kura/tmp`로 고정됨 |
| `KURA_TMP_DIR_MAX_BYTES` | 요청이 백프레셔를 받기 전에 `KURA_TMP_DIR`에 허용되는 최대 단계적 바이트 수. | 아니오 | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | 메타데이터 상태 및 세그먼트 파일을 위한 영구 디렉터리. | 예 | 기본값 없음 | `/var/cache/kura`로 고정됨 |
| `KURA_NODE_URL` | 다른 피어가 이 노드에 도달하기 위해 사용하는 정식 내부 URL. | 예 | 기본값 없음 | 파드 DNS 이름과 `peerTls.internalPort`에서 파생됨 |
| `KURA_PEERS` | 검색이 수렴되기 전에 사용되는 시드 피어 목록. | 아니오 | `KURA_NODE_URL` | StatefulSet 복제본에서 파생됨 |
| `KURA_DISCOVERY_DNS_NAME` | 자동 피어 검색에 사용되는 DNS 이름. | 아니오 | 비활성화됨 | `config.discovery.enabled`에 의해 활성화됨 |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | 피어 mTLS를 검증하는 데 사용되는 CA 인증서. | 아니오 | 비활성화되거나, 노드가 등록될 때 `KURA_DATA_DIR` 아래에서 파생됨 | `peerTls.enabled` 및 `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | 내부 피어 mTLS 리스너에서 사용되는 인증서. | 아니오 | 비활성화되거나, 노드가 등록될 때 `KURA_DATA_DIR` 아래에서 파생됨 | `peerTls.enabled` 및 `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | 내부 피어 mTLS 리스너에서 사용되는 개인 키. | 아니오 | 비활성화되거나, 노드가 등록될 때 `KURA_DATA_DIR` 아래에서 파생됨 | `peerTls.enabled` 및 `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | 공동 호스팅 HTTPS 리스너(`KURA_HTTPS_PORT`)에서 TLS를 종료하는 데 사용되는 인증서. | 아니오 | 비활성화됨 | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | `KURA_PUBLIC_TLS_CERT_PATH`와 쌍을 이루는 개인 키. | 아니오 | 비활성화됨 | `extraEnv` |
| `KURA_HTTPS_PORT` | 동일한 공동 호스팅 HTTP + gRPC 표면(ALPN 협상)을 제공하는 TLS 포트. 공개 TLS 경로가 설정된 경우에만 바인딩됩니다. | 아니오 | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | 업스트림 연결을 재사용하는 프록시를 위한, gRPC API만 제공하는 평문 HTTP/2 포트. [로드 밸런서 뒤에 노드 배치](#load-balancers)를 참조하세요. | 아니오 | 비활성화됨 | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | 요청 및 백그라운드 I/O를 위한 파일 디스크립터 할당량. | 아니오 | 자동 파생 | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | FD 백프레셔로 체크아웃이 실패하기 전에 요청이 대기하는 시간. | 아니오 | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | 고정된 세그먼트 읽기 핸들의 최대 수. | 아니오 | 자동 파생 | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | 종료 중 진행 중인 HTTP 및 gRPC 작업을 위한 유예 기간. | 아니오 | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Kura가 선택적 메모리 사용을 줄이기 시작하는 소프트 메모리 워터마크. | 아니오 | 자동 파생 | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Kura가 복제를 일시 중지하고 핫 캐시를 정리하는 하드 메모리 워터마크. | 아니오 | 자동 파생 | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | 인메모리 매니페스트 캐시의 최대 크기. | 아니오 | 자동 파생 | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | 요청당 최대 키-값 페이로드 크기. | 아니오 | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | 메타데이터 스토어를 위해 예약된 파일 디스크립터 할당량. | 아니오 | 자동 파생 | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | 메타데이터 스토어의 백그라운드 플러시 및 압축 동시성. | 아니오 | 자동 파생 | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | 메타데이터 스토어 읽기 캐시의 용량. | 아니오 | 자동 파생 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | 메타데이터 쓰기 버퍼링을 위해 예약된 총 메모리 할당량. | 아니오 | 자동 파생 | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | 플러시 전 각 메타데이터 쓰기 버퍼의 크기. | 아니오 | 자동 파생 | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | 메모리에 유지되는 메타데이터 쓰기 버퍼의 최대 수. | 아니오 | 자동 파생 | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | 진행 중인 멀티파트 업로드가 만료되기 전에 대기할 수 있는 시간. | 아니오 | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Kura가 오래된 멀티파트 업로드를 스캔하는 빈도. | 아니오 | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | 백필 패스가 도달하는 범위를 제한하는, 최신부터 계산된 연령 순 세그먼트 링의 비율. | 아니오 | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | 첫 번째 백필 주기를 아직 실행 중인 노드가 준비 상태로 보고하는 세그먼트 링의 포화도. | 아니오 | `KURA_BACKFILL_MARGIN_PERCENT`의 절반 | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | 백필 바디 배치 하나가 구성되는 바이트 임계값이며, 이를 초과하는 크기의 항목은 개별적으로 가져옵니다. | 아니오 | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Tokio 작업자 스레드 수. | 아니오 | 자동 파생 | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP 트레이스 엔드포인트. 추적을 비활성화하려면 비워 두세요. | 아니오 | 비활성화됨 | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry 서비스 이름. | 예 | 기본값 없음 | Helm의 Pod 이름 |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry 배포 환경. | 예 | 기본값 없음 | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | 패닉 및 오류 보고를 위한 Sentry DSN. | 아니오 | 비활성화됨 | `extraEnv` 또는 `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | 노드가 실행되는 데이터센터의 ISO 3166-1 alpha-2 국가 코드로, 내보낸 트레이스에 `geo.country.iso_code`로 기록됩니다. | 아니오 | 접두사가 국가 코드일 때 `KURA_REGION`에서 파생됨 | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | 해당 데이터센터의 ISO 3166-2 하위 구역(예: `US-CA`)으로, `geo.region.iso_code`로 기록됩니다. | 아니오 | 설정되지 않음 | `extraEnv` |
| `KURA_AUTH_ENABLED` | 호출자가 유효한 Tuist 토큰을 제시해야 합니다. `KURA_AUTH_TUIST_URL`를 설정하면 자체적으로 인증이 활성화되며, 이를 `false`로 설정해도 다시 비활성화되지 않습니다. 인증 없이 노드를 실행하려면 URL을 해제하세요. | 아니오 | 비활성화됨 | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | 노드가 인증을 수행하는 Tuist 서버입니다. 자체적으로 인증을 활성화합니다. | 인증이 활성화된 경우 필수 | 기본값 없음 | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | 해당 서버 호출에 대한 연결 시간 초과. | 아니오 | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | 해당 서버 호출에 대한 요청 시간 초과. | 아니오 | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | 노드가 직접 읽어서 왕복을 생략할 수 있는 토큰용 공유 비밀 키입니다. 서명과 검증을 모두 수행하므로, 노드와 서버가 동일한 신뢰 경계에 있을 때만 사용하세요. 자체 호스팅 노드는 일반적으로 이 값을 설정하지 않습니다. | 아니오 | 비활성화됨 | `extraEnv` 또는 `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | 서버가 캐시 토큰을 서명하는 키 쌍의 공개 부분으로, 하나 이상의 연결된 PEM 블록 형태입니다. 토큰을 생성하지 않고 읽기만 할 수 있어, 인터넷에서 접근 가능한 노드가 보유해야 합니다. `KURA_AUTH_JWT_SECRET`와 상호 배타적입니다. | 아니오 | 비활성화됨 | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | 해당 키의 알고리즘: 비밀 키 사용 시 `HS256`, `HS384` 또는 `HS512`, 공개 키 사용 시 `ES256`. | 아니오 | 비밀 키 사용 시 `HS256`, 공개 키 사용 시 `ES256` | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | 토큰이 반드시 포함해야 하는 발급자(Issuer). | 아니오 | 확인되지 않음 | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | 토큰이 반드시 포함해야 하는 쉼표로 구분된 대상(Audiences). | 아니오 | 확인되지 않음 | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | 인증 및 권한 부여 캐시 각각에 유지되는 최대 항목 수. | 아니오 | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | 매 부팅 시 노드를 컨트롤 플레인에 등록하고, 피어 인증서를 프로비저닝하며 `KURA_TENANT_ID`와 `KURA_PEERS`를 제공합니다. | 아니오 | 비활성화됨 | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | 노드가 등록을 수행하는 Tuist 서버. | 등록 시 필수 | 기본값 없음 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | 대시보드에서 생성된 노드 자격 증명의 클라이언트 ID. | 등록 또는 가입 시 필수 | 기본값 없음 | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | `KURA_CONTROL_PLANE_CLIENT_ID`와 쌍을 이루는 클라이언트 시크릿. | 등록 또는 가입 시 필수 | 기본값 없음 | `extraEnv` |
| `KURA_REGISTRATION_URL` | 노드가 등록 하트비트를 게시하여 클라이언트 facing 엔드포인트를 광고하는 절대 URL. | 가입 시 필수 | 기본값 없음 | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | 컨트롤 플레인이 클라이언트에 제공하는 클라이언트 facing 캐시 URL. 계정의 모든 클라이언트가 접근할 수 있어야 합니다. | 가입 시 필수 | 기본값 없음 | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | 등록 하트비트 주기. 임대 기간은 여러 개의 누락된 하트비트만큼 넓으므로, 단일 하트비트 손실로 엔드포인트가 제거되지 않습니다. | 아니오 | `60000` | `extraEnv` |

내부 피어 mTLS를 활성화하려면 `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` 및 `KURA_INTERNAL_TLS_KEY_PATH`를 함께 설정하세요. `KURA_NODE_URL`와 `KURA_PEERS`의 모든 값은 내부 피어 포트와 함께 `https://`를 사용해야 합니다.
