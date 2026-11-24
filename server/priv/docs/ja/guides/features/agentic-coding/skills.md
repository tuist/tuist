---
{
  "title": "スキル",
  "titleTemplate": ":title · エージェントによるコーディング · 機能 · ガイド · Tuist",
  "description": "プロジェクトの移行など、一般的なTuistタスクを実行するためにコーディングエージェントが使用できる事前構築済みのスキル。"
}
---

# スキル

スキルは、複雑な多段階のTuistタスクを実行するための事前構築済み指示セットです。移行やセットアップのプロセスを手動でエージェントに案内させる代わりに、スキルをインストールしてエージェントに処理を任せます。

コーディングエージェントがプラグインをサポートしている場合、<.localized_link href="/guides/features/agentic-coding/plugins">Tuist プラグイン</.localized_link>によって、これらのスキルとホストされたModel Context Protocolサーバーが一緒にインストールされます。

## 利用可能なスキル

| スキル | 説明 |
| --- | --- |
| `migrate` | 既存のXcodeプロジェクトを、ビルドおよび実行の検証、外部依存関係のマッピング、移行チェックリスト付きのTuist生成ワークスペースに移行します。 |
| `generated-projects` | Tuist生成ワークスペースでの日常作業をガイドします。生成、ビルド/テストコマンド、ビルド対象フォルダーなど。 |
| `fix-flaky-tests` | Tuistテストインサイトから失敗パターンを分析し、根本原因を特定して targeted な修正を適用することで、不安定なテストを修正します。 |
| `debug-generated-project` | シナリオを再現し、必要に応じてソースからTuistをビルドして、バグなのか設定ミスなのか、それともチームの入力が必要なものなのかをトリアージすることで、Tuist生成プロジェクトの問題をデバッグします。 |
| `compare-gradle-builds` | 2つのGradleビルド実行を比較して、所要時間の回帰、キャッシュの変化、タスク結果の違いを特定します。ビルドID、ダッシュボードURL、またはブランチ名で呼び出せます。 |

## インストール {#installation}

Tuistスキルをインストールする推奨方法は、[`skills`](https://github.com/vercel-labs/skills) CLIを使用することです。これにより、コーディングエージェントが自動検出され、`SKILL.md`ファイルが適切な場所に配置されます。

### すべてのスキルをインストール

```bash
npx skills add tuist/agent-skills
```

インタラクティブなプロンプトで、どのスキルとどのエージェント用にインストールするかを選択できます。

### 特定のスキルをインストール

```bash
npx skills add tuist/agent-skills --skill migrate
```

### 特定のエージェント用にインストール

```bash
npx skills add tuist/agent-skills -a claude-code
```

### グローバルにインストール

`-g`フラグを追加すると、スキルがホームディレクトリにインストールされ、すべてのプロジェクトで利用可能になります。

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

`skills` CLIを使用しない場合は、`SKILL.md`ファイルを直接ダウンロードできます。目的のスキルのための変数を設定し、エージェント用の`curl`コマンドを実行してください。

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
