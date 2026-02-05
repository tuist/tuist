---
{
  "title": "Skills",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Pre-built skills that coding agents can use to perform common Tuist tasks like project migration."
}
---

# Skills

Skills are pre-built instruction sets for performing complex, multi-step Tuist tasks. Instead of manually guiding an agent through a migration or setup process, you install a skill and let the agent handle it.

## Available skills

### Migrate to Tuist

Migrates existing Xcode projects to Tuist-generated workspaces with build and run validation, external dependency mapping, and migration checklists.

```bash
SKILL_NAME=tuist-migrate
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md
```

### Use Tuist generated projects

Guides day-to-day work in Tuist-generated workspaces: generation, build/test commands, and buildable folders.

```bash
SKILL_NAME=tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/generated-projects/SKILL.md
```

## Installation

Each coding agent has its own mechanism for loading skills. Below you will find instructions for the most popular ones. The examples use `$SKILL_NAME` and `$SKILL_URL` variables listed alongside each skill above.

### Claude Code

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) loads skills from `SKILL.md` files inside a `skills/` directory.

::: code-group

```bash [Project]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Global]
mkdir -p ~/.claude/skills/$SKILL_NAME
curl -o ~/.claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::

Once installed, invoke it with `/$SKILL_NAME` inside a Claude Code session.

### Codex

[Codex](https://github.com/openai/codex) loads skills from `SKILL.md` files inside a `skills/` directory. It searches the repository root, current working directory, and parent folders.

::: code-group

```bash [Project]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Global]
mkdir -p ~/.codex/skills/$SKILL_NAME
curl -o ~/.codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::

### Amp

[Amp](https://ampcode.com) supports skills through `SKILL.md` files in a `skills/` directory, and also reads `AGENTS.md` for general instructions.

::: code-group

```bash [Project]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Global]
mkdir -p ~/.config/agents/skills/$SKILL_NAME
curl -o ~/.config/agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::

### OpenCode

[OpenCode](https://opencode.ai) loads skills from `SKILL.md` files inside a `skills/` directory.

::: code-group

```bash [Project]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Global]
mkdir -p ~/.config/opencode/skills/$SKILL_NAME
curl -o ~/.config/opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
