---
{
  "title": "技能",
  "titleTemplate": ":title · AI 輔助編碼 · 功能 · 指南 · Tuist",
  "description": "預建技能，供 AI 編碼代理執行常見的 Tuist 工作，例如專案遷移。"
}
---

# 技能

技能是預先建置的指令集，用於執行複雜的多步驟 Tuist 任務。與其手動引導代理程式完成遷移或設定流程，不如安裝技能並讓代理程式自動處理。

如果你的編碼代理程式支援外掛程式，[Tuist 外掛程式](/guides/features/agentic-coding/plugins)會一併安裝這些技能與託管的 Model Context Protocol 伺服器。

## 可用技能

| 技能 | 說明 |
| --- | --- |
| `migrate` | 將現有的 Xcode 專案遷移至由 Tuist 產生的工作區，並進行建置與執行驗證、外部相依性對應，以及提供遷移檢查清單。 |
| `generated-projects` | 指導在 Tuist 產生之工作區中的日常工作：包含產生、建置/測試指令，以及可建置資料夾。 |
| `fix-flaky-tests` | 透過分析 Tuist 測試洞察中的失敗模式、找出根本原因，並套用針對性的修正，來修復不穩定測試。 |
| `debug-generated-project` | 除錯 Tuist 產生之專案的問題：重現情境、在需要時從原始碼建置 Tuist，並判斷是錯誤、設定錯誤，或需要團隊輸入的事項。 |
| `compare-gradle-builds` | 比較兩次 Gradle 建置執行，以識別耗時回退、快取變更與任務結果差異。可使用建置 ID、儀表板 URL 或分支名稱叫用。 |

## 安裝 {#installation}

建議使用 [`skills`](https://github.com/vercel-labs/skills) CLI 來安裝 Tuist 技能。它會自動偵測你的編碼代理程式，並將 `SKILL.md` 檔案放置於正確位置。

### 安裝所有技能

```bash
npx skills add tuist/agent-skills
```

互動式提示可讓你選擇要為哪些技能與代理程式進行安裝。

### 安裝特定技能

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 為特定代理程式安裝

```bash
npx skills add tuist/agent-skills -a claude-code
```

### 全域安裝

加入 `-g` 旗標，將技能安裝至你的主目錄，使其在所有專案中皆可使用：

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

如果你不想使用 `skills` CLI，可以直接下載 `SKILL.md` 檔案。設定所需技能的變數，並為你的代理程式執行 `curl` 指令：

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
