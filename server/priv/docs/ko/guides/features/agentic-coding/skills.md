---
{
  "title": "스킬",
  "titleTemplate": ":title · 에이전트 코딩 · 기능 · 가이드 · Tuist",
  "description": "프로젝트 마이그레이션과 같은 일반적인 Tuist 작업을 수행하기 위해 코딩 에이전트가 사용할 수 있는 사전 구축된 스킬입니다."
}
---

# 스킬

스킬은 복잡한 다단계 Tuist 작업을 수행하기 위한 사전 구성된 명령 세트입니다. 마이그레이션이나 설정 과정에서 에이전트를 수동으로 안내하는 대신, 스킬을 설치하고 에이전트가 처리하도록 하면 됩니다.

코딩 에이전트가 플러그인을 지원한다면, [Tuist 플러그인](/guides/features/agentic-coding/plugins)이 이러한 스킬과 호스팅된 Model Context Protocol 서버를 함께 설치합니다.

## 사용 가능한 스킬

| 스킬 | 설명 |
| --- | --- |
| `migrate` | 기존 Xcode 프로젝트를 빌드 및 실행 검증, 외부 의존성 매핑, 마이그레이션 체크리스트가 포함된 Tuist 생성 워크스페이스로 마이그레이션합니다. |
| `generated-projects` | Tuist 생성 워크스페이스에서의 일상 작업을 안내합니다: 생성, 빌드/테스트 명령어, 빌드 가능 폴더 등. |
| `fix-flaky-tests` | Tuist 테스트 인사이트에서 실패 패턴을 분석하고 근본 원인을 식별하여 대상 수정 사항을 적용함으로써 불안정한 테스트를 해결합니다. |
| `debug-generated-project` | 시나리오를 재현하고 필요 시 소스에서 Tuist를 빌드하며, 버그인지 설정 오류인지 팀의 입력이 필요한 사항인지 분류함으로써 Tuist 생성 프로젝트의 문제를 디버깅합니다. |
| `compare-gradle-builds` | 두 개의 Gradle 빌드 실행을 비교하여 소요 시간 회귀, 캐시 변경 사항, 작업 결과 차이를 식별합니다. 빌드 ID, 대시보드 URL 또는 브랜치 이름으로 호출할 수 있습니다. |

## 설치 {#installation}

Tuist 스킬을 설치하는 권장 방법은 [`skills`](https://github.com/vercel-labs/skills) CLI를 사용하는 것입니다. 이 도구는 코딩 에이전트를 자동으로 감지하고 `SKILL.md` 파일을 적절한 위치에 배치합니다.

### 모든 스킬 설치

```bash
npx skills add tuist/agent-skills
```

대화형 프롬프트를 통해 설치할 스킬과 에이전트를 선택할 수 있습니다.

### 특정 스킬 설치

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 특정 에이전트용 설치

```bash
npx skills add tuist/agent-skills -a claude-code
```

### 전역 설치

모든 프로젝트에서 사용할 수 있도록 홈 디렉터리에 스킬을 설치하려면 `-g` 플래그를 추가하세요:

```bash
npx skills add tuist/agent-skills -g
```

### 스킬 업데이트

```bash
npx skills update
```

### 비대화형 (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### 직접 설치 {#manual}

`skills` CLI를 사용하지 않으려면 `SKILL.md` 파일을 직접 다운로드할 수 있습니다. 원하는 스킬에 대한 변수를 설정하고 에이전트에 맞는 `curl` 명령어를 실행하세요:

```bash
SKILL_NAME=tuist-migrate          # or tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md  # or .../generated-projects/SKILL.md
```

::: code-group

```bash [Claude Code]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Codex]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Amp]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [OpenCode]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
