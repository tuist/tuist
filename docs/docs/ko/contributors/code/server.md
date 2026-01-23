---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# 서버 {#server}

Source:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## 용도 {#what-it-is-for}

서버는 Tuist의 인증, 계정 및 프로젝트, 캐시 저장소, 인사이트, 미리보기, 레지스트리, 통합(GitHub, Slack, SSO)과 같은
서버 측 기능을 지원합니다. 이는 Postgres와 ClickHouse를 사용하는 Phoenix/Elixir 애플리케이션입니다.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB는 더 이상 사용되지 않으며 제거될 예정입니다. 현재 로컬 설정이나 마이그레이션에 필요한 경우 [TimescaleDB 설치
문서](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)을
참조하십시오.
<!-- -->
:::

## 기여 방법 {#how-to-contribute}

서버에 기여하려면 CLA(`server/CLA.md`)에 서명해야 합니다.

### 로컬 환경 설정 {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!NOTE] 자체 개발자는 `priv/secrets/dev.key` 에서 암호화된 비밀 키를 로드합니다. 외부 기여자는 해당 키를 보유하지
> 않으며, 이는 정상입니다. 서버는 여전히 `TUIST_SECRET_KEY_BASE` 로 로컬에서 실행되지만, OAuth, Stripe 및
> 기타 통합 기능은 비활성화된 상태로 유지됩니다.

### 테스트 및 서식 {#tests-and-formatting}

- 테스트: `mix test`
- 포맷: `mise run format`
