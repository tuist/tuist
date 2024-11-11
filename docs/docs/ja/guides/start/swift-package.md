---
title: TuistをSwiftパッケージと使用する
titleTemplate: :title · スタート・ガイド・Tuist
description: TuistをSwiftパッケージで使用する方法を学びます。
---

# TuistをSwiftパッケージと共に使用する <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist は、`Package.swift` をプロジェクトの DSL として使用することをサポートしており、パッケージのターゲットをネイティブの Xcode プロジェクトおよびターゲットに変換します。

> [!WARNING]
> この機能の目的は、開発者がSwiftパッケージにTuistを導入する影響を評価するための簡単な方法を提供することです。 そのため、Swiftパッケージマネージャーの全機能をサポートする予定はなく、<LocalizedLink href="/guides/develop/projects/code-sharing">Project Description Helper</LocalizedLink>のようなTuist特有の機能をパッケージの世界に持ち込むことも計画していません。

> [!NOTE] ROOT DIRECTORY
> Tuist コマンドは、`Tuist` ディレクトリまたは `.git` ディレクトリによってルートが識別される特定の <LocalizedLink href="/guides/develop/projects/directory-structure#standard-tuist-projects">ディレクトリ構造を</LocalizedLink> 期待する。

## Using Tuist with a Swift Package {#using-tuist-with-a-swift-package}

We are going to use Tuist with the [TootSDK Package](https://github.com/TootSDK/TootSDK) repository, which contains a Swift Package. The first thing that we need to do is to clone the repository:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Once in the repository's directory, we need to install the Swift Package Manager dependencies:

```bash
tuist install
```

Under the hood `tuist install` uses the Swift Package Manager to resolve and pull the dependencies of the package.
After the resolution completes, you can then generate the project:

```bash
tuist generate
```

ほら！ ネイティブの Xcode プロジェクトを開いて作業を開始できます。
