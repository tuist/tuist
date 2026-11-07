---
{
  "title": "Swift Package で Tuist を使う",
  "titleTemplate": ":title · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Swift Package で Tuist を使う方法を学びます。"
}
---
# Swift Package で Tuist を使用する <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist は、プロジェクトの DSL として `Package.swift` を使用することをサポートしており、パッケージターゲットをネイティブな Xcode プロジェクトおよびターゲットに変換します。

> [!WARNING]
> この機能の目的は、開発者が Swift Packages への Tuist 導入の影響を簡単に評価できるようにすることです。そのため、Swift Package Manager の全機能をサポートしたり、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> など Tuist の独自の機能をすべてパッケージの世界に持ち込んだりすることは計画していません。


> [!NOTE]
> **ルートディレクトリ**
>
> Tuist コマンドは特定の <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">ディレクトリ構造</.localized_link> を想定しており、そのルートは `Tuist` または `.git` ディレクトリによって識別されます。


## Swift Package で Tuist を使用する {#using-tuist-with-a-swift-package}

Swift Package を含む [TootSDK パッケージ](https://github.com/TootSDK/TootSDK) リポジトリで Tuist を使用します。最初に行うべきことは、リポジトリをクローンすることです。

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

リポジトリのディレクトリに移動したら、Swift Package Manager の依存関係をインストールする必要があります。

```bash
tuist install
```

内部では `tuist install` が Swift Package Manager を使用してパッケージの依存関係を解決し、取得します。解決が完了したら、プロジェクトを生成できます。

```bash
tuist generate
```

これで完了です。ネイティブな Xcode プロジェクトが作成され、開いて作業を開始できます。
