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

| Skill | Description |
| --- | --- |
| `migrate` | Migrates existing Xcode projects to Tuist-generated workspaces with build and run validation, external dependency mapping, and migration checklists. |
| `generated-projects` | Guides day-to-day work in Tuist-generated workspaces: generation, build/test commands, and buildable folders. |
| `fix-flaky-tests` | Fixes flaky tests by analyzing failure patterns from Tuist test insights, identifying root causes, and applying targeted corrections. |

## Installation {#installation}

The recommended way to install Tuist skills is with the [`skills`](https://github.com/vercel-labs/skills) CLI. It detects your coding agents automatically and places the `SKILL.md` files in the right location.

### Install all skills

```bash
npx skills add tuist/tuist
```

The interactive prompt lets you choose which skills and agents to install for.

### Install a specific skill

```bash
npx skills add tuist/tuist --skill migrate
```

### Install for a specific agent

```bash
npx skills add tuist/tuist -a claude-code
```

### Install globally

Add the `-g` flag to install skills in your home directory so they are available across all projects:

```bash
npx skills add tuist/tuist -g
```

### Update skills

```bash
npx skills update
```

### Non-interactive (CI)

```bash
npx skills add tuist/tuist --all -y
```

### Manual installation {#manual}

If you prefer not to use the `skills` CLI, you can download `SKILL.md` files directly. Set the variables for the skill you want and run the `curl` command for your agent:

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
