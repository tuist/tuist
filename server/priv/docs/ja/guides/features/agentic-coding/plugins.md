---
{
  "title": "プラグイン",
  "titleTemplate": ":title · エージェント型コーディング · 機能 · ガイド · Tuist",
  "description": "Cursor 用の Tuist プラグイン、またはベンダー中立の Agent Plugins パッケージをインストールします。"
}
---

# プラグイン

Tuist はエージェントスキルとホスト型 MCP サーバーをプラグインとしてパッケージ化しているため、両方をまとめてインストールできます。お使いのコーディングエージェントに対応するパッケージを選択してください。

## Claude Code

[Tuist Claude Code マーケットプレイス](https://github.com/tuist/claude-plugin)では、以下のコマンドで Tuist プラグインをインストールできるようにパッケージ化されています：

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

このプラグインは Tuist スキルを提供し、Claude Code をホスト型 MCP サーバーに接続します。

## Cursor

[Cursor Marketplace](https://cursor.com/marketplace)から[Cursor 用 Tuist プラグイン](https://github.com/tuist/cursor-plugin)をインストールします：

1. Cursor のサイドバーで**Customize**を開きます。
2. **Tuist**を検索します。
3. **Install**を選択し、現在のプロジェクト用にインストールするか、ユーザーアカウント用にインストールするかを選びます。

Cursor で`/add-plugin`を入力して、同じインストールフローを開くこともできます。このプラグインは Tuist スキルを提供し、Cursor をホスト型 MCP サーバーに接続します。

組織で Cursor マーケットプレイスを管理している場合は、まず**Settings → Plugins → Team Marketplaces → Import Marketplace**から`https://github.com/tuist/cursor-plugin`をインポートしてください。

## その他のコーディングエージェント

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin)は、オープンでベンダー中立な[Agent Plugins](https://agent-plugins.org/)標準に従っています。互換性のあるクライアントで、そのクライアントのプラグインディレクトリのインストールまたは参照に関する指示に従ってリポジトリを指定してください：

```bash
git clone https://github.com/tuist/agent-plugin.git
```

これにより Tuist スキルがインストールされ、`https://tuist.dev/mcp`がリモート MCP サーバーとして登録されます。Agent Plugins をまだサポートしていないクライアントの場合は、[スキル](/guides/features/agentic-coding/skills)をインストールするか、[MCP サーバー](/guides/features/agentic-coding/mcp)を個別に設定してください。

## 認証

ほとんどのスキルは Tuist コマンドラインインターフェースを使用するため、エージェントにプロジェクトデータへのアクセスを依頼する前に、一度認証を行ってください：

```bash
tuist auth login
```

ホスト型 MCP サーバーは、必要に応じて独自のサインインを要求します。クライアント固有の設定および認証の詳細については、[MCP ガイド](/guides/features/agentic-coding/mcp)をご覧ください。
