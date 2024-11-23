---
title: TuistをSwiftパッケージと使用する
titleTemplate: :title · スタート・ガイド・Tuist
description: TuistをSwiftパッケージと使用する方法を学びます。
---

# TuistをSwiftパッケージと使用する <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist は、`Package.swift` をプロジェクトの DSL として使用することをサポートしており、パッケージのターゲットをネイティブの Xcode プロジェクトおよびターゲットに変換します。

> [!WARNING]
> この機能の目的は、開発者がSwiftパッケージにTuistを導入する影響を評価するための簡単な方法を提供することです。 そのため、Swiftパッケージマネージャーの全機能をサポートする予定はなく、<LocalizedLink href="/guides/develop/projects/code-sharing">Project Description Helper</LocalizedLink>のようなTuist特有の機能をパッケージの世界に持ち込むことも計画していません。

> [!NOTE] ROOT DIRECTORY
> Tuist コマンドは、`Tuist` ディレクトリまたは `.git` ディレクトリによってルートが識別される特定の <LocalizedLink href="/guides/develop/projects/directory-structure#standard-tuist-projects">ディレクトリ構造を</LocalizedLink> 期待する。

## TuistをSwiftパッケージと使用する {#using-tuist-with-a-swift-package}

Swiftパッケージを含む[TootSDK Package](https://github.com/TootSDK/TootSDK)リポジトリでTuistを使用します。 まず、リポジトリをクローンする必要があります。 まず、リポジトリをクローンする必要があります。

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

リポジトリのディレクトリに一度入ったら、Swift Package Manager の依存関係をインストールする必要があります。

```bash
tuist install
```

`tuist install` は、Swift Package Managerを使用してパッケージの依存関係を解決して pull します。
依存関係の解決が完了したら、プロジェクトを生成することができます。
依存関係の解決が完了したら、プロジェクトを生成することができます。

```bash
tuist generate
```

ほら！ ネイティブの Xcode プロジェクトを開いて作業を開始できます。
