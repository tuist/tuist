---
{
  "title": "スキル",
  "titleTemplate": ":title · エージェント型コーディング · 機能 · ガイド · Tuist",
  "description": "プロジェクトの移行など、一般的なTuistタスクを実行するためにコーディングエージェントが使用できるビルトインスキル。"
}
---

# スキル

スキルは、複雑で多段階のTuistタスクを実行するための事前構築済み命令セットです。移行やセットアップのプロセスを手動でエージェントに指示する代わりに、スキルをインストールしてエージェントに処理を任せることができます。

コーディングエージェントがプラグインをサポートしている場合、[Tuist プラグイン](/guides/features/agentic-coding/plugins)によって、これらのスキルとホストされたModel Context Protocolサーバーが一緒にインストールされます。

## 利用可能なスキル

| スキル | 説明 |
| --- | --- |
| `migrate` | 既存のXcodeプロジェクトを、ビルドおよび実行の検証、外部依存関係のマッピング、移行チェックリストを備えたTuist生成ワークスペースに移行します。 |
| `generated-projects` | Tuist生成ワークスペースでの日常的な作業をガイドします。生成、ビルド/テストコマンド、ビルド対象フォルダーなどに対応します。 |
| `fix-flaky-tests` | Tuistテストインサイトから失敗パターンを分析し、根本原因を特定して的確な修正を適用することで、不安定なテストを解消します。 |
| `debug-generated-project` | シナリオを再現し、必要に応じてソースからTuistをビルドして、バグ、設定ミス、またはチームの判断が必要かどうかを切り分けることで、Tuist生成プロジェクトの問題をデバッグします。 |
| `compare-gradle-builds` | 2つのGradleビルドの実行を比較して、所要時間の回帰、キャッシュの変化、タスク結果の違いを特定します。ビルドID、ダッシュボードURL、ブランチ名で呼び出すことができます。 |

## インストール {#installation}

Tuistスキルをインストールする推奨方法は、[`skills`](https://github.com/vercel-labs/skills) CLIを使用することです。これにより、コーディングエージェントが自動的に検出され、`SKILL.md`ファイルが適切な場所に配置されます。

### すべてのスキルをインストール

```bash
npx skills add tuist/agent-skills
```

インタラクティブなプロンプトを使用して、インストールするスキルとエージェントを選択できます。

### 特定のスキルをインストール

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 特定のエージェント用にインストール

```bash
npx skills add tuist/agent-skills -a claude-code
```

### グローバルにインストール

すべてのプロジェクトで利用できるように、ホームディレクトリにスキルをインストールするには`-g`フラグを追加します。

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

`skills` CLIを使用したくない場合は、`SKILL.md`ファイルを直接ダウンロードできます。必要なスキルのための変数を設定し、エージェント用の`curl`コマンドを実行してください。

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
