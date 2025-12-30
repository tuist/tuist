---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# 모델 컨텍스트 프로토콜(MCP)

[MCP(모델 컨텍스트 프로토콜)(https://www.claudemcp.com)는 [클로드](https://claude.ai)가 LLM이 개발
환경과 상호 작용할 수 있도록 제안한 표준입니다. LLM의 USB-C라고 생각하시면 됩니다. 화물과 운송의 상호 운용성을 높인 선적 컨테이너나
애플리케이션 계층과 전송 계층을 분리한 TCP와 같은 프로토콜처럼 MCP는 [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code)와 같은 LLM 기반 애플리케이션과
[Zed](https://zed.dev), [Cursor](https://www.cursor.com), [VS
Code](https://code.visualstudio.com) 같은 에디터를 다른 도메인과 상호 운용할 수 있게 합니다.

튜이스트는 CLI를 통해 로컬 서버를 제공하여 **앱 개발 환경(**)과 상호 작용할 수 있도록 합니다. 클라이언트 앱을 여기에 연결하면 언어를
사용하여 프로젝트와 상호 작용할 수 있습니다.

이 페이지에서는 설정 방법과 기능에 대해 설명합니다.

::: info Mise란?
<!-- -->
Tuist MCP 서버는 상호작용하려는 프로젝트에 대해 Xcode의 가장 최신 프로젝트를 소스로 사용합니다.
<!-- -->
:::

## 설정하기

Tuist는 인기 있는 MCP 호환 클라이언트를 위한 자동 설정 명령을 제공합니다. 클라이언트에 적합한 명령을 실행하기만 하면 됩니다:

### [Claude](https://claude.ai)

클로드 데스크톱](https://claude.ai/download)의 경우 실행합니다:
```bash
tuist mcp setup claude
```

`~/라이브러리/애플리케이션 지원/Claude/claude_desktop_config.json` 에서 파일을 구성할 수 있습니다.

### [클로드 코드](https://docs.anthropic.com/en/docs/claude-code)

클로드 코드의 경우 실행합니다:
```bash
tuist mcp setup claude-code
```

이렇게 하면 Claude 데스크톱과 동일한 파일이 구성됩니다.

### [커서](https://www.cursor.com)

커서 IDE의 경우 전역 또는 로컬로 구성할 수 있습니다:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Zed 에디터의 경우 전역 또는 로컬로 구성할 수도 있습니다:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS 코드](https://code.visualstudio.com)

MCP 확장 기능이 있는 VS 코드의 경우 글로벌 또는 로컬로 구성합니다:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### 수동 구성

수동 구성을 선호하거나 다른 MCP 클라이언트를 사용 중인 경우, 클라이언트 구성에 Tuist MCP 서버를 추가하세요:

::: code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## 기능

다음 섹션에서는 Tuist MCP 서버의 기능에 대해 알아봅니다.

### 참고자료

#### 최근 프로젝트 및 작업 공간

Tuist는 최근에 작업한 Xcode 프로젝트와 작업 공간을 기록하여 애플리케이션에서 해당 종속성 그래프에 액세스하여 강력한 통찰력을 얻을 수
있도록 합니다. 이 데이터를 쿼리하여 다음과 같은 프로젝트 구조 및 관계에 대한 세부 정보를 확인할 수 있습니다:

- 특정 대상의 직접 종속성과 전이 종속성은 무엇인가요?
- 어떤 대상에 가장 많은 소스 파일이 있으며, 얼마나 많은 파일이 포함되어 있나요?
- 그래프에 있는 모든 정적 제품(예: 정적 라이브러리 또는 프레임워크)은 무엇인가요?
- 모든 대상을 이름 및 제품 유형(예: 앱, 프레임워크, 단위 테스트)과 함께 알파벳순으로 정렬하여 나열할 수 있나요?
- 특정 프레임워크 또는 외부 종속성에 의존하는 대상은 무엇인가요?
- 프로젝트의 모든 대상에 걸쳐 있는 소스 파일의 총 개수는 얼마입니까?
- 대상 간에 순환 종속성이 있으며, 있다면 어디에 있나요?
- 어떤 타깃이 특정 리소스(예: 이미지 또는 목록 파일)를 사용하나요?
- 그래프에서 가장 깊은 종속성 체인은 무엇이며 어떤 타깃이 관련되어 있나요?
- 모든 테스트 대상과 관련 앱 또는 프레임워크 대상을 보여줄 수 있나요?
- 최근 상호작용을 기준으로 빌드 시간이 가장 긴 타겟은 무엇인가요?
- 두 특정 대상 간의 종속성에는 어떤 차이가 있나요?
- 프로젝트에 사용하지 않는 소스 파일이나 리소스가 있나요?
- 공통 종속성을 공유하는 대상은 무엇이며, 그 종속성은 무엇인가요?

Tuist를 사용하면 이전과는 전혀 다른 방식으로 Xcode 프로젝트를 분석하여 가장 복잡한 설정도 더 쉽게 이해하고, 최적화하고, 관리할 수
있습니다!
