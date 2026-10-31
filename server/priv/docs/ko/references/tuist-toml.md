---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 참조 · Tuist",
  "description": "tuist.toml 구성 파일 형식에 대한 참조입니다."
}
---

# tuist.toml {#tuist-toml}

`tuist.toml`는 빌드 시스템에 구애받지 않는 구성 파일이며 `Tuist.swift`의 진화된 형태입니다. `Tuist.swift`와 달리 Swift가 필요하지 않아 모든 플랫폼과 빌드 시스템에서 사용할 수 있습니다. Linux 기반 CI 러너처럼 Swift를 사용할 수 없는 환경이나, 전체 `Tuist.swift` 매니페스트 없이 서버 관련 설정만 구성해야 할 때 이상적입니다.

Tuist는 현재 작업 디렉터리에서 상위 디렉터리 계층을 따라가며 `tuist.toml`를 검색하고, 첫 번째로 일치하는 위치에서 멈춥니다. 따라서 프로젝트 루트에 배치하면 하위 디렉터리 어디서든 Tuist 명령을 실행할 수 있습니다.

## 지원되는 키 {#supported-keys}

| 키 | 유형 | 필수 | 기본값 | 설명 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 예 | — | 프로젝트의 전체 핸들(예: `"tuist/tuist"`). |
| `url` | `String` | 아니오 | `https://tuist.dev` | Tuist 서버의 URL입니다. |

### 네트워크 {#network}

`[network]` 테이블은 Tuist가 외부 HTTP 연결을 수행하는 방식을 구성합니다.

| 키 | 유형 | 필수 | 기본값 | 설명 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 아니오 | `true` | `true`일 때, Tuist는 `HTTPS_PROXY`/`HTTP_PROXY`로 정의된 프록시를 존재하는 경우 사용합니다. <.localized_link href="/guides/integrations/http-proxy">HTTP 프록시 가이드</.localized_link>를 참조하세요. |
| `ca_certificate` | `String` | 아니오 | — | 시스템 루트 저장소 외에 신뢰할 PEM 또는 DER CA 인증서 번들의 경로입니다. 예를 들어 개인 CA를 사용하는 자체 호스팅 서버에 적합합니다. `TUIST_CA_CERTIFICATE` 환경 변수가 우선 적용됩니다. <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">사용자 지정 CA 인증서 신뢰하기</.localized_link>를 참조하세요. |

## 예제 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 구성 우선순위 {#configuration-precedence}

동일한 설정이 여러 위치에 정의된 경우, Tuist는 다음 우선순위 순서(높음에서 낮음)로 해결합니다.

1. **CLI 플래그**
2. **환경 변수**
3. **Tuist.swift**
4. **tuist.toml**
5. **기본값**
