---
title: はじめに
titleTemplate: :title · 導入の手順 · Tuist
description: 開発環境にTuistをインストールする方法を学びます。
---

# はじめに {#get-started}

任意のディレクトリ、または Xcode プロジェクトおよびワークスペースのディレクトリで、以下のコマンドを実行するのが Tuist を始める最も簡単な方法です：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```

:::

The command will walk you through the steps to <LocalizedLink href="/guides/features/projects">create a generated project</LocalizedLink> or integrate an existing Xcode project or workspace. It helps you connect your setup to the remote server, giving you access to features like <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink>, <LocalizedLink href="/guides/features/previews">previews</LocalizedLink>, and the <LocalizedLink href="/guides/features/registry">registry</LocalizedLink>.

> [!NOTE] 既存プロジェクトの移行
> 既存のプロジェクトを生成プロジェクトに移行して、開発体験を向上させたり、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>などの機能を活用したい場合は、<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">移行ガイド</LocalizedLink>をご覧ください。
