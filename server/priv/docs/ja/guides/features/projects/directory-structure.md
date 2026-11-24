---
{
  "title": "ディレクトリ構造",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist プロジェクトの構造と、その整理方法について学びます。"
}
---
# ディレクトリ構造 {#directory-structure}

Tuist プロジェクトは Xcode プロジェクトを置き換えるために一般的に使用されますが、このユースケースに限定されるものではありません。Tuist プロジェクトは、SPM パッケージ、テンプレート、プラグイン、タスクなど、他の種類のプロジェクトを生成するためにも使用されます。このドキュメントでは、Tuist プロジェクトの構造とその整理方法について説明します。後のセクションでは、テンプレート、プラグイン、タスクの定義方法についても取り上げます。

## 標準的な Tuist プロジェクト {#standard-tuist-projects}

Tuist プロジェクトは**Tuist によって生成される最も一般的なプロジェクトタイプです。** アプリ、フレームワーク、ライブラリなどのビルドに使用されます。Xcode プロジェクトとは異なり、Tuist プロジェクトは Swift で定義されるため、より柔軟で保守が容易です。また、宣言的であるため、理解しやすく、推論もしやすくなっています。以下の構造は、Xcode プロジェクトを生成する典型的な Tuist プロジェクトを示しています。

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Tuist ディレクトリ:** このディレクトリには 2 つの目的があります。まず、**プロジェクトのルートがどこにあるか**を示します。これにより、プロジェクトのルートに対する相対パスを構築したり、プロジェクト内の任意のディレクトリから Tuist コマンドを実行したりできます。次に、以下のファイルのコンテナとなります。
  - **ProjectDescriptionHelpers:** このディレクトリには、すべてのマニフェストファイル間で共有される Swift コードが含まれています。マニフェストファイルは `import ProjectDescriptionHelpers` をインポートすることで、このディレクトリで定義されたコードを使用できます。コードを共有することは、重複を避け、プロジェクト間の一貫性を確保するために役立ちます。
  - **Package.swift:** このファイルには、Tuist が Xcode プロジェクトとターゲットを使用して統合するための Swift Package 依存関係が含まれており（[CocoaPods](https://cocoapods.org) のように）、構成および最適化が可能です。詳細は<.localized_link href="/guides/features/projects/dependencies">こちら</.localized_link>をご覧ください。

- **ルートディレクトリ**: `Tuist` ディレクトリも含まれる、プロジェクトのルートディレクトリ。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift:</strong></.localized_link> このファイルには、すべてのプロジェクト、ワークスペース、環境で共有される Tuist の設定が含まれています。例えば、スキームの自動生成を無効にしたり、プロジェクトのデプロイメントターゲットを定義したりするために使用できます。
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift:</strong></.localized_link> このマニフェストは Xcode ワークスペースを表します。他のプロジェクトをグループ化するために使用され、追加のファイルやスキームを追加することもできます。
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift:</strong></.localized_link> このマニフェストは Xcode プロジェクトを表します。プロジェクトの一部となるターゲットとその依存関係を定義するために使用されます。

上記のプロジェクトを操作する場合、コマンドは作業ディレクトリまたは `--path` フラグで指定されたディレクトリ内に `Workspace.swift` または `Project.swift` ファイルがあることを想定しています。マニフェストは、プロジェクトのルートを表す `Tuist` ディレクトリを含むディレクトリ、またはそのサブディレクトリにある必要があります。

> [!TIP]
> Xcode ワークスペースでは、マージ競合の可能性を減らすために、プロジェクトを複数の Xcode プロジェクトに分割することができました。もしあなたがワークスペースをその目的で使用していた場合、Tuist ではそれらは不要です。Tuist は、プロジェクトとその依存関係のプロジェクトを含むワークスペースを自動生成します。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist は SPM パッケージプロジェクトもサポートしています。SPM パッケージで作業している場合、何も更新する必要はありません。Tuist は自動的にルートの `Package.swift` を検出し、Tuist のすべての機能は `Project.swift` マニフェストであるかのように動作します。

開始するには、SPM パッケージ内で `tuist install` と `tuist generate` を実行してください。これで、通常の Xcode SPM 統合で見られるのと同じすべてのスキームとファイルがプロジェクトに含まれているはずです。さらに、<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link> を実行して、SPM 依存関係とモジュールの大部分を事前コンパイルできるため、後続のビルドが非常に高速になります。
