---
title: TuistをSwiftパッケージと使用する
titleTemplate: :title · スタート・ガイド・Tuist
description: TuistをSwiftパッケージで使用する方法を学びます。
---

# TuistをSwiftパッケージと共に使用する <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist は、`Package.swift` をプロジェクトの DSL として使用することをサポートしており、パッケージのターゲットをネイティブの Xcode プロジェクトおよびターゲットに変換します。

> [!WARNING]
> この機能の目的は、開発者がSwiftパッケージにTuistを導入する影響を評価するための簡単な方法を提供することです。 [!WARNING]
> この機能の目的は、開発者がSwiftパッケージにTuistを導入する影響を評価するための簡単な方法を提供することです。 そのため、Swiftパッケージマネージャーの全機能をサポートする予定はなく、<LocalizedLink href="/guides/develop/projects/code-sharing">Project Description Helper</LocalizedLink>のようなTuist特有の機能をパッケージの世界に持ち込むことも計画していません。 [!WARNING]
> この機能の目的は、開発者がSwiftパッケージにTuistを導入する影響を評価するための簡単な方法を提供することです。 そのため、Swiftパッケージマネージャーの全機能をサポートする予定はなく、<LocalizedLink href="/guides/develop/projects/code-sharing">Project Description Helper</LocalizedLink>のようなTuist特有の機能をパッケージの世界に持ち込むことも計画していません。

> [!NOTE] ROOT DIRECTORY
> Tuist commands expect a certain <LocalizedLink href="/guides/develop/projects/directory-structure#standard-tuist-projects">directory structure</LocalizedLink> whose root is identified by a `Tuist` or a `.git` directory.

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

ほら！ ほら！ ほら！ You have a native Xcode project that you can open and start working on.
