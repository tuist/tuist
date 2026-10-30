---
{
  "title": "HTTP 프록시",
  "titleTemplate": ":title | 통합 | 가이드 | Tuist",
  "description": "HTTPS_PROXY 또는 HTTP_PROXY가 설정되었을 때 Tuist가 회사 프록시를 통해 HTTP 트래픽을 라우팅하는 방법을 알아보세요."
}
---
# HTTP 프록시 {#http-proxy}

환경에 `HTTPS_PROXY` 또는 `HTTP_PROXY`가 설정되면 Tuist는 관리하는 HTTP 연결을 해당 프록시를 통해 자동으로 라우팅합니다. 이는 Tuist CLI와 Tuist Gradle 플러그인 모두에 적용되며, 추가 구성이 필요하지 않습니다.

이 동작은 `curl`, `git` 및 대부분의 개발자 도구에서 사용하는 규칙과 일치하므로, 다른 도구를 위해 이러한 변수를 이미 설정한 환경에서는 Tuist가 별도 설정 없이 바로 작동합니다.

## 프록시 대상 {#what-is-proxied}

Tuist가 소유한 HTTP 클라이언트만 프록시를 통해 라우팅됩니다:

- 캐시, 미리보기, 분석 및 레지스트리 엔드포인트,
- 그리고 Gradle 플러그인이 Tuist 서비스(원격 빌드 캐시, 빌드 인사이트, 테스트 인사이트, 테스트 격리, 테스트 샤딩)로 수행하는 호출입니다.

## 변수 조회 순서 {#variable-lookup-order}

Tuist는 다음 순서로 첫 번째 비어 있지 않은 값을 읽습니다:

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

값은 `http://proxy.corp:8080`와 같은 URL이어야 합니다. 인라인 자격 증명(`http://user:password@proxy.corp:8080`)도 지원됩니다.
