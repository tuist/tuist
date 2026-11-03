---
{
  "title": "プラグイン",
  "titleTemplate": ":title · エージェントによるコーディング · 機能 · ガイド · Tuist",
  "description": "Cursor 用の Tuist プラグイン、またはベンダー非依存のエージェントプラグインパッケージをインストールします。"
}
---

# プラグイン

Tuist はエージェントスキルとホスト型 MCP サーバーをプラグインとしてパッケージ化しているため、両方をまとめてインストールできます。コーディングエージェントに合ったパッケージを選択してください。

## Claude Code

[Tuist Claude Code マーケットプレイス](https://github.com/tuist/claude-plugin)では、次のコマンドで Tuist プラグインをインストールできます：

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

このプラグインは Tuist スキルを提供し、Claude Code をホスト型 MCP サーバーに接続します。

## Cursor

[Cursor Marketplace](https://cursor.com/marketplace)から[Cursor 用 Tuist プラグイン](https://github.com/tuist/cursor-plugin)をインストールします：

1. Cursor のサイドバーで**Customize**を開きます。
2. **Tuist**を検索します。
3. **Install**を選択し、現在のプロジェクト用かユーザーアカウント用にインストールするかを選びます。

Cursor で `/add-plugin` と入力しても、同じインストールフローを開くことができます。このプラグインは Tuist スキルを提供し、Cursor をホスト型 MCP サーバーに接続します。

組織が Cursor マーケットプレイスを管理している場合は、まず **Settings → Plugins → Team Marketplaces → Import Marketplace** から `https://github.com/tuist/cursor-plugin` をインポートしてください。

## その他のコーディングエージェント

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) は、オープンでベンダー中立の [Agent Plugins](https://agent-plugins.org/) 標準に従っています。互換性のあるクライアントのリポジトリを指すよう設定し、そのクライアントのプラグインディレクトリのインストールまたは参照に関する指示に従ってください：

```bash
git clone https://github.com/tuist/agent-plugin.git
```

これにより Tuist スキルがインストールされ、`https://tuist.dev/mcp` がリモート MCP サーバーとして登録されます。Agent Plugins をまだサポートしていないクライアントの場合は、[スキル](/guides/features/agentic-coding/skills)をインストールするか、[MCP サーバー](/guides/features/agentic-coding/mcp)を個別に設定してください。

## 認証

ほとんどのスキルは Tuist コマンドラインインターフェースを使用するため、エージェントにプロジェクトデータへのアクセスを依頼する前に、一度認証を行ってください：

```bash
tuist auth login
```

ホスト型 MCP サーバーは必要に応じて独自のサインインを要求します。クライアント固有の設定および認証の詳細については、[MCP ガイド](/guides/features/agentic-coding/mcp)をご覧ください。
