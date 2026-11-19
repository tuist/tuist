---
{
  "title": "ドキュメント",
  "titleTemplate": ":title · コード · コントリビューター · Tuist",
  "description": "Tuistのドキュメントサイトへの貢献方法。"
}
---
# ドキュメント {#docs}

ソース: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 目的 {#what-it-is-for}

このドキュメントサイトは、Tuistの製品およびコントリビューター向けドキュメントをホストしています。これはPhoenixアプリケーションであるTuistサーバーの一部であり、`server/priv/docs/en` 以下のMarkdownページを `/docs` でレンダリングします。

## 貢献方法 {#how-to-contribute}

`server/priv/docs/en` 以下の英語ページを編集してください。翻訳は別途管理されているため、他のロケールディレクトリは編集しないでください。サイドバーは `server/lib/tuist/docs_sidebar.ex` で定義されています。読者がページを見つけられるよう、ここに新しいページを追加してください。

複数のページで同じテキスト（ビルドシステム間で共通するセクションなど）を共有する場合は、それらのページの隣に名前が `_` で始まるファイルを作成し、不安定なテストのページで行っているように、`@snippet:` HTMLコメントを使ってそのファイルをインクルードしてください。`_` で始まるファイルは単独のページとして公開されません。

### ローカル環境のセットアップ {#set-up-locally}

`server` ディレクトリからサーバーを実行し、[セットアップ手順](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)に従ってください:

```bash
cd server
mise install
mise run dev
```

その後、[http://localhost:8080/en/docs](http://localhost:8080/en/docs) を開いてください。

### 生成されるコンテンツ {#generated-content}

CLIリファレンスは最新のCLIリリースのコマンド仕様から生成されるため、ローカルでビルドする必要はありません。

ProjectDescription APIリファレンスは、[projectdescription.tuist.dev](https://projectdescription.tuist.dev) のDocCサイトとして別途ホストされています。ローカルでビルドするには、リポジトリのルートから `mise run docs:project-description` を実行してください。
