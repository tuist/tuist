---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# はじめましょう{#get-started}

Tuistを任意のディレクトリ、またはXcodeプロジェクトやワークスペースのディレクトリで開始する最も簡単な方法：

コードグループ

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

このコマンドは、<LocalizedLink href="/guides/features/projects">生成されたプロジェクトの作成</LocalizedLink>または既存のXcodeプロジェクト/ワークスペースの統合手順を案内します。これによりリモートサーバーへの接続が確立され、<LocalizedLink href="/guides/features/selective-testing">選択的テスト</LocalizedLink>、<LocalizedLink href="/guides/features/previews">プレビュー</LocalizedLink>、<LocalizedLink href="/guides/features/registry">レジストリ</LocalizedLink>などの機能を利用できるようになります。

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
既存プロジェクトを生成プロジェクトに移行し、開発者エクスペリエンスを向上させ、当社の<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>を活用したい場合は、<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">移行ガイド</LocalizedLink>をご確認ください。
<!-- -->
:::
