---
{
  "title": "スキル",
  "titleTemplate": ":title · エージェント型コーディング · 機能 · ガイド · Tuist",
  "description": "プロジェクトの移行など、一般的なTuistタスクを実行するためにコーディングエージェントが使用できる事前構築済みスキル。"
}
---

# スキル

スキルは、複雑で多段階のTuistタスクを実行するための事前構築された指示セットです。移行やセットアッププロセスを手動でエージェントに案内させる代わりに、スキルをインストールしてエージェントに処理を任せることができます。

コーディングエージェントがプラグインをサポートしている場合、[Tuist プラグイン](/guides/features/agentic-coding/plugins)によって、これらのスキルとホストされているModel Context Protocolサーバーが一緒にインストールされます。

## 利用可能なスキル

| スキル | 説明 |
| --- | --- |
| `migrate` | 既存のXcodeプロジェクトを、ビルドおよび実行の検証、外部依存関係のマッピング、移行チェックリストを備えたTuist生成ワークスペースに移行します。 |
| `generated-projects` | Tuist生成ワークスペースでの日常業務をガイドします：生成、ビルド/テストコマンド、およびビルド可能なフォルダ。 |
| `fix-flaky-tests` | Tuistテストインサイトから失敗パターンを分析し、根本原因を特定して targeted な修正を適用することで、不安定なテストを修正します。 |
| `debug-generated-project` | シナリオを再現し、必要に応じてソースからTuistをビルドし、バグ、設定ミス、またはチームの入力が必要なものかどうかをトリアージすることで、Tuist生成プロジェクトの問題をデバッグします。 |
| `compare-gradle-builds` | 2つのGradleビルド実行を比較して、所要時間の回帰、キャッシュの変更、タスク結果の違いを特定します。ビルドID、ダッシュボードURL、またはブランチ名で呼び出すことができます。 |

## インストール {#installation}

Tuistスキルをインストールする推奨方法は、[`skills`](https://github.com/vercel-labs/skills) CLIを使用することです。これはコーディングエージェントを自動的に検出し、`SKILL.md`ファイルを適切な場所に配置します。

### すべてのスキルをインストール

```bash
npx skills add tuist/agent-skills
```

インタラクティブなプロンプトにより、どのスキルとエージェントをインストールするかを選択できます。

### 特定のスキルをインストール

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 特定のエージェント用にインストール

```bash
npx skills add tuist/agent-skills -a claude-code
```

### グローバルにインストール

`-g`フラグを追加して、ホームディレクトリにスキルをインストールし、すべてのプロジェクトで利用できるようにします：

```bash
npx skills add tuist/agent-skills -g
```

### スキルを更新

```bash
npx skills update
```

### 非インタラクティブ（CI）

```bash
npx skills add tuist/agent-skills --all -y
```

### 手動インストール {#manual}

`skills` CLIを使用しない場合は、`SKILL.md`ファイルを直接ダウンロードできます。必要なスキルのための変数を設定し、エージェント用の`curl`コマンドを実行します：

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
