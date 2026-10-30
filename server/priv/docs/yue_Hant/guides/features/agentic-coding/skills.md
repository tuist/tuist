---
{
  "title": "技能",
  "titleTemplate": ":title · AI 編碼代理 · 功能 · 指南 · Tuist",
  "description": "預建技能，讓編碼代理能夠執行常見的 Tuist 工作，例如項目遷移。"
}
---

# 技能

技能係預先建立好嘅指令集，用嚟執行複雜、多步驟嘅 Tuist 工作。與其手動引導代理程式進行遷移或設定流程，不如安裝一個技能，讓代理程式自動處理。

如果你嘅編碼代理程式支援外掛程式，[Tuist plugins](/guides/features/agentic-coding/plugins) 會一併安裝呢啲技能同埋託管嘅 Model Context Protocol 伺服器。

## 可用技能

| 技能 | 描述 |
| --- | --- |
| `migrate` | 將現有 Xcode 專案遷移至 Tuist 生成嘅工作區，並提供建構同執行驗證、外部依賴映射，以及遷移檢查清單。 |
| `generated-projects` | 指導喺 Tuist 生成工作區入面嘅日常工作：包括生成、建構/測試指令，以及可建構資料夾。 |
| `fix-flaky-tests` | 透過分析 Tuist 測試洞察中的失敗模式、找出根本原因並應用針對性修正，來修復不穩定測試。 |
| `debug-generated-project` | 除錯 Tuist 生成專案嘅問題：重現場景、必要時從原始碼建構 Tuist，並判斷係 bug、設定錯誤，定係需要團隊介入。 |
| `compare-gradle-builds` | 比較兩次 Gradle 建構運行，以識別耗時倒退、快取變更同任務結果差異。可以透過建構 ID、儀表板 URL 或分支名稱來調用。 |

## 安裝 {#installation}

建議使用 [`skills`](https://github.com/vercel-labs/skills) CLI 來安裝 Tuist 技能。佢會自動偵測你嘅編碼代理程式，並將 `SKILL.md` 檔案放置於正確位置。

### 安裝所有技能

```bash
npx skills add tuist/agent-skills
```

互動式提示讓你選擇要為邊啲技能同代理程式進行安裝。

### 安裝特定技能

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 為特定代理程式安裝

```bash
npx skills add tuist/agent-skills -a claude-code
```

### 全域安裝

加入 `-g` 標誌，將技能安裝到你嘅主目錄，令佢哋喺所有專案中都可用：

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

如果你唔想用 `skills` CLI，可以直接下載 `SKILL.md` 檔案。設定你想要嘅技能變數，然後為你嘅代理程式執行 `curl` 指令：

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
