---
{
  "title": "ドキュメント",
  "titleTemplate": ":title · コード · 貢献者 · Tuist",
  "description": "Tuistのドキュメントサイトへの貢献。"
}
---
# ドキュメント {#docs}

ソース: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 目的 {#what-it-is-for}

このドキュメントサイトでは、Tuist の製品およびコントリビューター向けのドキュメントを公開しています。これは Phoenix アプリケーションである Tuist サーバーの一部であり、`server/priv/docs/en` 以下の Markdown ページを `/docs` でレンダリングします。

## 貢献方法 {#how-to-contribute}

`server/priv/docs/en` 以下の英語ページを編集してください。翻訳は別途管理されているため、他のロケールディレクトリは編集しないでください。サイドバーは `server/lib/tuist/docs_sidebar.ex` で定義されています。新しいページを追加して、読者が発見できるようにしてください。

複数のページで同じテキスト（ビルドシステム横断のセクションなど）を共有する場合は、それらのページと同じ場所にファイル名が `_` で始まるファイルを作成し、不安定なテストのページで行われているように、`@snippet:` HTML コメントでそのファイルを指してインクルードしてください。`_` で始まるファイルは単独のページとして公開されません。

### ローカル環境の設定 {#set-up-locally}

`server` ディレクトリからサーバーを実行し、[セットアップ手順](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)に従ってください:

```bash
cd server
mise install
mise run dev
```

次に [http://localhost:8080/en/docs](http://localhost:8080/en/docs) を開きます。

### 生成されたコンテンツ {#generated-content}

CLI リファレンスは最新の CLI リリースのコマンド仕様から生成されるため、ローカルでビルドする必要はありません。

ProjectDescription API リファレンスは、[projectdescription.tuist.dev](https://projectdescription.tuist.dev) で DocC サイトとして別途ホストされています。ローカルでビルドするには、リポジトリのルートから `mise run docs:project-description` を実行してください。
