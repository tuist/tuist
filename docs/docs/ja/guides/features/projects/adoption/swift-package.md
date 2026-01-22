---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# SwiftパッケージでTuistを使う<Badge type="warning" text="beta" />.{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuistは、プロジェクトのDSLとして`Package.swift`
の使用をサポートし、パッケージターゲットをネイティブのXcodeプロジェクトおよびターゲットに変換します。

::: 警告
<!-- -->
この機能の目的は、開発者がSwiftパッケージにTuistを採用した場合の影響を簡単に評価できるようにすることです。したがって、Swift Package
Managerの全機能をサポートしたり、<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト説明ヘルパー</LocalizedLink>のようなTuist固有の機能をすべてパッケージの世界に導入したりする予定はありません。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuistコマンドは特定の<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">ディレクトリ構造</LocalizedLink>を前提としており、そのルートは`Tuist`
または`.git` ディレクトリで識別されます。
<!-- -->
:::

## SwiftパッケージでTuistを使う{#using-tuist-with-a-swift-package}

Tuistを[TootSDK
Package](https://github.com/TootSDK/TootSDK)リポジトリと共に使用します。このリポジトリにはSwiftパッケージが含まれています。最初に行うべきことは、リポジトリをクローンすることです：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

リポジトリのディレクトリに移動したら、Swift Package Managerの依存関係をインストールする必要があります：

```bash
tuist install
```

内部処理では、`tuist install` はSwift Package
Managerを使用してパッケージの依存関係を解決・取得します。解決が完了したら、プロジェクトを生成できます:

```bash
tuist generate
```

さあ、これでネイティブのXcodeプロジェクトが完成しました。開いて作業を開始できます。
