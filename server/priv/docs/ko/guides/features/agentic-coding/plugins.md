---
{
  "title": "플러그인",
  "titleTemplate": ":title · 에이전트 코딩 · 기능 · 가이드 · Tuist",
  "description": "Cursor용 Tuist 플러그인이나 벤더 중립적인 에이전트 플러그인 패키지를 설치하세요."
}
---

# 플러그인

Tuist는 에이전트 스킬과 호스팅된 MCP 서버를 플러그인으로 패키징하여 함께 설치할 수 있도록 합니다. 코딩 에이전트에 맞는 패키지를 선택하세요.

## Claude Code

[Tuist Claude Code 마켓플레이스](https://github.com/tuist/claude-plugin)는 Tuist 플러그인을 다음 명령어로 설치할 수 있도록 패키징합니다:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

이 플러그인은 Tuist 스킬을 제공하고 Claude Code를 호스팅된 MCP 서버에 연결합니다.

## Cursor

[Cursor 마켓플레이스](https://cursor.com/marketplace)에서 [Cursor용 Tuist 플러그인](https://github.com/tuist/cursor-plugin)을 설치하세요:

1. Cursor 사이드바에서 **Customize**를 엽니다.
2. **Tuist**를 검색합니다.
3. **Install**을 선택한 후, 현재 프로젝트에 설치할지 사용자 계정에 설치할지 선택합니다.

Cursor에서 `/add-plugin`을 입력하여 동일한 설치 흐름을 열 수도 있습니다. 이 플러그인은 Tuist 스킬을 제공하고 Cursor를 호스팅된 MCP 서버에 연결합니다.

조직에서 Cursor 마켓플레이스를 관리하는 경우, 먼저 **Settings → Plugins → Team Marketplaces → Import Marketplace**에서 `https://github.com/tuist/cursor-plugin`을 가져오세요.

## 기타 코딩 에이전트

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin)은 오픈且벤더 중립적인 [Agent Plugins](https://agent-plugins.org/) 표준을 따릅니다. 해당 클라이언트의 플러그인 디렉터리 설치 또는 참조 지침에 따라 호환되는 클라이언트를 리포지토리로 지정하세요:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

이 플러그인은 Tuist 스킬을 설치하고 `https://tuist.dev/mcp`을 원격 MCP 서버로 등록합니다. 아직 Agent Plugins를 지원하지 않는 클라이언트의 경우, [스킬](/guides/features/agentic-coding/skills)을 설치하거나 [MCP 서버](/guides/features/agentic-coding/mcp)를 별도로 구성하세요.

## 인증

대부분의 스킬은 Tuist 명령줄 인터페이스를 사용하므로, 에이전트가 프로젝트 데이터에 액세스하도록 요청하기 전에 한 번 인증하세요:

```bash
tuist auth login
```

호스팅된 MCP 서버는 필요시 자체 로그인을 요청합니다. 클라이언트별 설정 및 인증 세부 정보는 [MCP 가이드](/guides/features/agentic-coding/mcp)를 참조하세요.
