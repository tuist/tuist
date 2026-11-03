---
{
  "title": "技能",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "預先構建的技能，供編碼代理執行常見 Tuist 任務（例如項目遷移）。"
}
---

# 技能

技能係預先建立嘅指令集，用嚟執行複雜、多步驟嘅 Tuist 工作。唔使手動引導代理完成遷移或設定流程，你只需要安裝技能，然後讓代理處理就得。

如果你嘅編碼代理支援插件，[Tuist 插件](/guides/features/agentic-coding/plugins)會一併安裝呢啲技能同託管嘅 Model Context Protocol 伺服器。

## 可用技能

| 技能 | 描述 |
| --- | --- |
| `migrate` | 將現有 Xcode 項目遷移至 Tuist 生成嘅工作區，包括構建同運行驗證、外部依賴映射，以及遷移清單。 |
| `generated-projects` | 指導喺 Tuist 生成工作區中嘅日常工作：生成、構建/測試命令，以及可構建資料夾。 |
| `fix-flaky-tests` | 透過分析 Tuist 測試洞察中嘅失敗模式、識別根本原因並應用針對性修正，嚟修復不穩定測試。 |
| `debug-generated-project` | 透過重現場景、必要時從源碼構建 Tuist，並判斷問題係 bug、配置錯誤定係需要團隊輸入，嚟調試 Tuist 生成項目中嘅問題。 |
| `compare-gradle-builds` | 比較兩次 Gradle 構建運行，以識別持續時間回退、快取變更同任務結果差異。可以使用構建 ID、儀表板 URL 或分支名稱嚟調用。 |

## 安裝 {#installation}

安裝 Tuist 技能嘅推薦方式係使用 [`skills`](https://github.com/vercel-labs/skills) CLI。佢會自動偵測你嘅編碼代理，並將 `SKILL.md` 檔案放置喺正確位置。

### 安裝所有技能

```bash
npx skills add tuist/agent-skills
```

互動提示允許你選擇要為邊啲技能同代理進行安裝。

### 安裝特定技能

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 為特定代理安裝

```bash
npx skills add tuist/agent-skills -a claude-code
```

### 全局安裝

添加 `-g` 標誌以將技能安裝到你嘅主目錄，令佢哋喺所有項目中都可用：

```bash
npx skills add tuist/agent-skills -g
```

### 更新技能

```bash
npx skills update
```

### 非互動式（CI）

```bash
npx skills add tuist/agent-skills --all -y
```

### 手動安裝 {#manual}

如果你唔想用 `skills` CLI，可以直接下載 `SKILL.md` 檔案。設定你想要嘅技能對應變數，然後為你嘅代理運行 `curl` 命令：

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
