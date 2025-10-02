---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 始めよう{#get-started}。

任意のディレクトリ、またはXcodeプロジェクトやワークスペースのディレクトリでTuistを始める最も簡単な方法：

コードグループ

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
:::

このコマンドは、<LocalizedLink href="/guides/features/projects">生成されたプロジェクトを作成したり、</LocalizedLink>既存の
Xcode
プロジェクトやワークスペースを統合するための手順を説明します。3}選択的テスト</LocalizedLink>、<LocalizedLink href="/guides/features/previews">プレビュー</LocalizedLink>、<LocalizedLink href="/guides/features/registry">レジストリ</LocalizedLink>のような機能にアクセスできるように、リモートサーバにセットアップを接続するのに役立ちます。

> [注意] 既存のプロジェクトをマイグレーションする
> 開発者のエクスペリエンスを向上させ、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>を利用するために、既存のプロジェクトを生成されたプロジェクトにマイグレーションしたい場合は、<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">マイグレーションガイド</LocalizedLink>をチェックしてください。
