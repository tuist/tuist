---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# モデルコンテキストプロトコル（MCP）

[モデル・コンテキスト・プロトコル（MCP）](https://www.claudemcp.com)は、LLMが開発環境と相互作用するために[クロード](https://claude.ai)によって提案された標準です。LLMのUSB-Cと考えることができる。貨物と輸送の相互運用性を高めた輸送用コンテナや、アプリケーション層とトランスポート層を切り離したTCPのようなプロトコルのように、MCPは[Claude](https://claude.ai/)や[Claude
Code](https://docs.anthropic.com/en/docs/claude-code)のようなLLMを搭載したアプリケーションや、[Zed](https://zed.dev)や[Cursor](https://www.cursor.com)や[VS
Code](https://code.visualstudio.com)のようなエディタを他のドメインと相互運用可能にします。

TuistはCLIを通じてローカルサーバーを提供し、**アプリ開発環境**
と対話することができる。クライアントアプリをこのサーバーに接続することで、言語を使ってプロジェクトとやり取りすることができる。

このページでは、その設定方法と機能について説明する。

::: info
<!-- -->
Tuist MCPサーバーは、あなたが対話したいプロジェクトの真実のソースとしてXcodeの最新のプロジェクトを使用します。
<!-- -->
:::

## セットアップ

Tuistは一般的なMCP互換クライアント用の自動セットアップコマンドを提供する。お使いのクライアントに適したコマンドを実行するだけです：

### [クロード](https://claude.ai)。

クロードデスクトップ](https://claude.ai/download)の場合は、実行する：
```bash
tuist mcp setup claude
```

これは`~/Library/Application Support/Claude/claude_desktop_config.json`
にあるファイルを設定します。

### [クロード・コード](https://docs.anthropic.com/en/docs/claude-code)

クロード・コードは、実行する：
```bash
tuist mcp setup claude-code
```

これはクロードデスクトップと同じファイルを設定します。

### [カーソル](https://www.cursor.com)

Cursor IDEでは、グローバルまたはローカルに設定できます：
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [ゼット](https://zed.dev)

ゼットエディターでは、グローバルまたはローカルに設定することもできます：
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VSコード](https://code.visualstudio.com)

MCP拡張機能を持つVS Codeの場合は、グローバルまたはローカルに設定します：
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### マニュアル設定

手動で設定したい場合、または別のMCPクライアントを使用している場合は、Tuist MCPサーバーをクライアントの設定に追加してください：

コードグループ

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## 能力

以下のセクションでは、Tuist MCPサーバーの機能について説明します。

### リソース

#### 最近のプロジェクトとワークスペース

Tuistは、あなたが最近作業したXcodeプロジェクトとワークスペースの記録を保持し、あなたのアプリケーションに強力な洞察のためのそれらの依存関係グラフへのアクセスを提供します。このデータをクエリして、次のようなプロジェクト構造と関係の詳細を明らかにすることができます：

- 特定のターゲットの直接的、推移的依存関係とは何か？
- ソースファイルの数が最も多いのはどのターゲットで、いくつ含まれているか？
- グラフ内のすべての静的製品（静的ライブラリやフレームワークなど）とは？
- すべてのターゲットをアルファベット順に、名前と製品タイプ（アプリ、フレームワーク、ユニットテストなど）とともにリストアップできますか？
- どのターゲットが特定のフレームワークや外部依存に依存しているか？
- プロジェクト内の全ターゲットにわたるソース・ファイルの総数は？
- ターゲット間に循環的な依存関係はあるか、あるとすればどこにあるか？
- 特定のリソース（イメージやplistファイルなど）を使用するターゲットは？
- グラフの中で最も深い依存関係の連鎖は何か？
- すべてのテストターゲットと、関連するアプリまたはフレームワークのターゲットを見せてもらえますか？
- 最近の交流に基づくと、建設期間が最も長いターゲットは？
- 2つの特定のターゲット間の依存関係の違いは何か？
- プロジェクトに未使用のソースファイルやリソースはありますか？
- どのターゲットが共通の依存関係を持ち、それは何か？

Tuistを使えば、Xcodeプロジェクトをかつてないほど深く掘り下げることができ、最も複雑なセットアップでさえ理解、最適化、管理しやすくなります！
