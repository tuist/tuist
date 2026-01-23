---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Docs{#docs}

Source:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 目的{#what-it-is-for}

ドキュメントサイトはTuistの製品および貢献者向けドキュメントをホストしています。VitePressで構築されています。

## 貢献方法{#how-to-contribute}

### ローカルに設定する{#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### オプションで生成されるデータ{#optional-generated-data}

ドキュメントには生成データが埋め込まれています：

- CLIリファレンスデータ:`mise run generate-cli-docs`
- プロジェクトマニフェスト参照データ:`mise run generate-manifests-docs`

これらはオプションです。ドキュメントはこれらなしでも表示されます。生成されたコンテンツを更新する必要がある場合のみ実行してください。
