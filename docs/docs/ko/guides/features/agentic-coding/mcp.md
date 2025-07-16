---
title: Model Context Protocol (MCP)
titleTemplate: :title · AI · Guides · Tuist
description: Tuist의 MCP 서버를 사용하여 앱 개발 환경에서 언어 기반 인터페이스를 활용하는 방법을 배워봅니다.
---

# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com)은 LLM이 개발 환경과 상호작용할 수 있도록 [Claude](https://claude.ai)에서 제안한 표준입니다.
이것을 LLM의 USB-C로 생각할 수 있습니다.
컨테이너 운송이 화물과 운송을 더 상호 운용 가능하게 만들었듯이,
TCP 프로토콜이 애플리케이션 계층을 전송 계층과 분리했듯이,
MCP는 [Claude](https://claude.ai/)와 같은 LLM 기반 애플리케이션과 [Zed](https://zed.dev)나 [Cursor](https://www.cursor.com)와 같은 편집기가 다른 도메인과 상호 운용될 수 있도록 합니다.

Tuist는 CLI를 통해 로컬 서버를 제공하여 _앱 개발 환경_과 상호작용할 수 있습니다.
클라이언트 앱을 이 서버에 연결하면 언어를 사용해 프로젝트와 상호작용할 수 있습니다.

이 페이지에서는 MCP 서버의 설정 방법과 기능에 대해 알아볼 수 있습니다.

> [!NOTE]\
> Tuist MCP 서버는 Xcode의 최신 프로젝트를 기준으로 상호작용할 프로젝트를 결정합니다.

## 설정

Tuist provides automated setup commands for popular MCP-compatible clients. Simply run the appropriate command for your client:

### [Claude](https://claude.ai)

For [Claude desktop](https://claude.ai/download), run:

```bash
tuist mcp setup claude
```

또한 `~/Library/Application\ Support/Claude/claude_desktop_config.json`의 파일을 직접 수정하여 Tuist MCP 서버를 추가할 수 있습니다:

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

For Claude Code, run:

```bash
tuist mcp setup claude-code
```

This will configure the same file as Claude desktop.

### [Cursor](https://www.cursor.com)

For Cursor IDE, you can configure it globally or locally:

```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

For Zed editor, you can also configure it globally or locally:

```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

For VS Code with MCP extension, configure it globally or locally:

```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Manual Configuration

If you prefer to configure manually or are using a different MCP client, add the Tuist MCP server to your client's configuration:

:::code-group

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

:::

## Capabilities

다음 섹션에서 Tuist MCP 서버의 기능에 대해 배워봅니다.

### 리소스

#### 최근 프로젝트와 워크스페이스

Tuist는 최근에 작업한 Xcode 프로젝트와 워크스페이스를 기록하여, 애플리케이션의 의존성 그래프에 접근이 가능하기 때문에 더 나은 분석이 가능합니다. 이런 데이터를 조회하여 다음과 같이 프로젝트의 구조와 관계에 대해 자세히 알 수 있습니다:

- 특정 타겟의 직접 의존성 및 전이적 의존성은 무엇입니까?
- 가장 많은 소스 파일을 포함한 타겟과 얼마나 많은 파일을 포함하고 있습니까?
- 그래프 내에 모든 정적 제품(예: 정적 라이브러리, 정적 프레임워크)는 무엇입니까?
- 모든 타겟을 알파벳 순으로 정렬하고, 이름 및 제품 타입(예: 앱, 프레임워크, 유닛 테스트)과 함께 나열할 수 있습니까?
- 특정 프레임워크나 외부에 의존하는 타겟은 무엇입니까?
- 프로젝트의 모든 타겟에 포함된 총 소스 파일의 갯수는 몇 개입니까?
- 타겟 간의 순환 의존성이 존재하며, 어디에 있습니까?
- 특정 리소스(예: 이미지, plist 파일)를 사용하는 타겟은 무엇입니까?
- 그래프에서 가장 깊은 의존성 체인은 무엇이며 어떤 타겟이 포함됩니까?
- 모든 테스트 타겟과 그 타겟과 연관된 앱이나 프레임워크 타겟을 보여줄 수 있습니까?
- 최근 빌드 시간을 기준으로 빌드 시간이 가장 오래 걸린 타겟은 무엇입니까?
- 특정 두 타겟의 의존성 차이는 무엇입니까?
- 프로젝트에서 사용하지 않는 소스 파일이나 리소스가 있습니까?
- 어떤 타겟이 공통된 의존성을 공유하며, 그 의존성은 무엇입니까?

Tuist를 사용하면, Xcode 프로젝트를 더 깊이 알 수 있으며, 이를 통해 복잡한 설정도 쉽게 이해하고 최적화하며 효과적으로 관리할 수 있습니다!
