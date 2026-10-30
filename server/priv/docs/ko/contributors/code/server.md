---
{
  "title": "서버",
  "titleTemplate": ":title · 코드 · 기여자 · Tuist",
  "description": "Tuist 서버에 기여하세요."
}
---
# 서버 {#server}

소스: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 용도 {#what-it-is-for}

서버는 인증, 계정 및 프로젝트, 캐시 스토리지, 인사이트, 미리보기, 레지스트리, 통합(GitHub, Slack, SSO)과 같은 Tuist의 서버 측 기능을 지원합니다. Postgres와 ClickHouse를 사용하는 Phoenix/Elixir 애플리케이션입니다.

## 기여 방법 {#how-to-contribute}

서버에 기여하려면 CLA(`server/CLA.md`)에 서명해야 합니다.

### 로컬 설정 {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

브라우저에서 `http://localhost:8080`을 엽니다. 개발 환경에서는 로그인 페이지에 사전 구성된 계정(`tuistrocks@tuist.dev` / `tuistrocks`)으로 로그인할 수 있는 **테스트 사용자로 로그인** 버튼이 포함되어 있습니다.

> [!NOTE]
> 내부 개발자는 fnox를 통해 1Password에서 개발 시크릿을 로드합니다. `mise run dev`은 서버를 `fnox exec`로 감쌉니다(`server/fnox.toml` 참조). 외부 기여자는 1Password 접근 권한이 필요하지 않으며, 서버는 이를 사용하지 않고도 로컬에서 실행됩니다. OAuth, Stripe 및 기타 서드파티 통합은 비활성화되지만 핵심 기능은 정상적으로 작동합니다.

### 로컬 Helm 테스트 {#local-helm-testing}

[kind](https://kind.sigs.k8s.io/)와 포함된 mise 작업을 사용하여 머신에서 전체 스택을 실행할 수 있습니다. 이 과정은 Docker 이미지를 로컬에서 빌드하고, kind 클러스터를 생성하며, 차트를 설치하고, 모든 서비스를 자동으로 포트 포워딩합니다.

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**필수 조건:** `docker`, `kind`, `helm`, `kubectl`.

### 테스트 및 포맷팅 {#tests-and-formatting}

- 테스트: `mix test`
- 포맷: `mise run format`
