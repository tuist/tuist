---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# SwiftパッケージでTuistを使う<Badge type="warning" text="beta" />.{#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuistは、`Package.swift`
をプロジェクトのDSLとして使用することをサポートしており、パッケージターゲットをネイティブのXcodeプロジェクトとターゲットに変換します。

::: 警告
<!-- -->
この機能の目的は、開発者がSwiftパッケージにTuistを採用することの影響を評価する簡単な方法を提供することです。そのため、Swiftパッケージマネージャの全機能をサポートする予定はありませんし、<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</LocalizedLink>のようなTuist独自の機能をパッケージの世界にすべて持ち込む予定もありません。
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuistコマンドは、ルートが`Tuist` または`.git`
ディレクトリで識別される特定の<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">ディレクトリ構造</LocalizedLink>を期待します。
<!-- -->
:::

## SwiftパッケージでTuistを使う{#using-tuist-with-a-swift-package}

Swiftパッケージを含む[TootSDK
Package](https://github.com/TootSDK/TootSDK)リポジトリでTuistを使用するつもりです。最初にすべきことは、リポジトリをクローンすることです：

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

リポジトリのディレクトリに入ったら、Swift Package Managerの依存関係をインストールする必要があります：

```bash
tuist install
```

フードの下で`tuist install` はパッケージの依存関係を解決して引き出すために Swift Package Manager
を使います。解決完了後、プロジェクトを生成できます：

```bash
tuist generate
```

ほら！ネイティブのXcodeプロジェクトを開いて作業を開始できます。
