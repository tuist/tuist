---
{
  "title": "ドキュメント",
  "titleTemplate": ":title · コード · コントリビューター · Tuist",
  "description": "Tuist のドキュメントサイトへの貢献方法。"
}
---
# ドキュメント {#docs}

ソース: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 目的 {#what-it-is-for}

このドキュメントサイトでは、Tuistの製品およびコントリビューター向けドキュメントを公開しています。VitePressで構築されています。

## 貢献方法 {#how-to-contribute}

### ローカル環境のセットアップ {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### オプションの生成データ {#optional-generated-data}

ドキュメントには一部の生成データが埋め込まれています。

- CLIリファレンスデータ: `mise run generate-cli-docs`

これらはオプションです。ドキュメントはこれらのデータなしでも表示されるため、生成コンテンツを更新する必要がある場合のみ実行してください。

ProjectDescription APIリファレンスは、[projectdescription.tuist.dev](https://projectdescription.tuist.dev) でDocCサイトとして別途公開されています。ローカルでビルドするには、リポジトリのルートから `mise run docs:project-description` を実行してください。
