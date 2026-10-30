---
{
  "title": "技能",
  "titleTemplate": ":title · 智能体编码 · 功能 · 指南 · Tuist",
  "description": "预置技能，供编码智能体执行常见 Tuist 任务，例如项目迁移。"
}
---

# 技能

技能是用于执行复杂、多步骤 Tuist 任务的预构建指令集。无需手动引导代理完成迁移或设置流程，你只需安装一个技能，然后让代理来处理即可。

如果你的编码代理支持插件，[Tuist 插件](/guides/features/agentic-coding/plugins)会一并安装这些技能和托管的 Model Context Protocol 服务器。

## 可用技能

| 技能 | 描述 |
| --- | --- |
| `migrate` | 将现有 Xcode 项目迁移到由 Tuist 生成的工作区，包括构建和运行验证、外部依赖映射以及迁移清单。 |
| `generated-projects` | 指导在 Tuist 生成的工作区中的日常工作：生成、构建/测试命令以及可构建文件夹。 |
| `fix-flaky-tests` | 通过分析 Tuist 测试洞察中的失败模式、识别根本原因并应用针对性修复来解决不稳定测试。 |
| `debug-generated-project` | 通过重现场景、在需要时从源代码构建 Tuist，并判断问题是 bug、配置错误还是需要团队介入，来调试 Tuist 生成项目的问题。 |
| `compare-gradle-builds` | 比较两次 Gradle 构建运行，以识别耗时回归、缓存变化和任务结果差异。可以通过构建 ID、仪表板 URL 或分支名称调用。 |

## 安装 {#installation}

推荐使用 [`skills`](https://github.com/vercel-labs/skills) CLI 来安装 Tuist 技能。它会自动检测你的编码代理，并将 `SKILL.md` 文件放置在正确的位置。

### 安装所有技能

```bash
npx skills add tuist/agent-skills
```

交互式提示允许你选择要安装的技能及其对应的代理。

### 安装特定技能

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 为特定代理安装

```bash
npx skills add tuist/agent-skills -a claude-code
```

### 全局安装

添加 `-g` 标志以将技能安装到你的主目录中，使其在所有项目中可用：

```bash
npx skills add tuist/agent-skills -g
```

### 更新技能

```bash
npx skills update
```

### 非交互式（CI）

```bash
npx skills add tuist/agent-skills --all -y
```

### 手动安装 {#manual}

如果你不想使用 `skills` CLI，可以直接下载 `SKILL.md` 文件。为你想要的技能设置变量，并为你的代理运行 `curl` 命令：

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
