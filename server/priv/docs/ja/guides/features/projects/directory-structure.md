---
{
  "title": "ディレクトリ構造",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistプロジェクトの構造と、その整理方法について学びます。"
}
---
# ディレクトリ構造 {#directory-structure}

TuistプロジェクトはXcodeプロジェクトを置き換えるために一般的に使用されますが、このユースケースに限定されるものではありません。Tuistプロジェクトは、SPMパッケージ、テンプレート、プラグイン、タスクなど、他の種類のプロジェクトを生成するためにも使用されます。このドキュメントでは、Tuistプロジェクトの構造とその整理方法について説明します。後のセクションでは、テンプレート、プラグイン、タスクの定義方法について取り上げます。

## 標準的なTuistプロジェクト {#standard-tuist-projects}

Tuistプロジェクトは**Tuistによって生成される最も一般的なプロジェクトタイプです。** これらは、アプリ、フレームワーク、ライブラリなどをビルドするために使用されます。Xcodeプロジェクトとは異なり、TuistプロジェクトはSwiftで定義されるため、より柔軟で保守が容易です。また、Tuistプロジェクトは宣言的であるため、理解しやすく、推論しやすいという特徴もあります。以下の構造は、Xcodeプロジェクトを生成する典型的なTuistプロジェクトを示しています。

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

- **Tuistディレクトリ:** このディレクトリには2つの目的があります。第一に、**プロジェクトのルートがどこにあるか**を示します。これにより、プロジェクトのルートに対する相対パスを構築したり、プロジェクト内の任意のディレクトリからTuistコマンドを実行したりできます。第二に、以下のファイルのコンテナとなります。
  - **ProjectDescriptionHelpers:** このディレクトリには、すべてのマニフェストファイルで共有されるSwiftコードが含まれています。マニフェストファイルは`import ProjectDescriptionHelpers`して、このディレクトリで定義されたコードを使用できます。コードを共有することは、重複を避け、プロジェクト間の一貫性を確保するのに役立ちます。
  - **Package.swift:** このファイルには、TuistがXcodeプロジェクトとターゲットを使用して統合するためのSwift Package依存関係が含まれており（[CocoaPods](https://cocoapods.org)のような）、構成可能で最適化可能です。詳細は<.localized_link href="/guides/features/projects/dependencies">こちら</.localized_link>をご覧ください。

- **ルートディレクトリ**: プロジェクトのルートディレクトリであり、`Tuist`ディレクトリも含んでいます。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift:</strong></.localized_link> このファイルには、すべてのプロジェクト、ワークスペース、環境で共有されるTuistの構成が含まれています。例えば、スキームの自動生成を無効にしたり、プロジェクトのデプロイメントターゲットを定義したりするために使用できます。
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift:</strong></.localized_link> このマニフェストはXcodeワークスペースを表します。他のプロジェクトをグループ化するために使用され、追加のファイルやスキームを追加することもできます。
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift:</strong></.localized_link> このマニフェストはXcodeプロジェクトを表します。プロジェクトの一部であるターゲットとその依存関係を定義するために使用されます。

上記のプロジェクトを操作する場合、コマンドは作業ディレクトリまたは`--path`フラグで指定されたディレクトリ内に`Workspace.swift`または`Project.swift`ファイルがあることを想定しています。マニフェストは、プロジェクトのルートを表す`Tuist`ディレクトリを含むディレクトリ、またはそのサブディレクトリにある必要があります。

> [!TIP]
> Xcodeワークスペースでは、マージ競合の可能性を減らすために、プロジェクトを複数のXcodeプロジェクトに分割することができました。もしあなたがワークスペースをその目的で使用していたなら、Tuistではそれらは不要です。Tuistは、プロジェクトとその依存関係のプロジェクトを含むワークスペースを自動生成します。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

TuistはSPMパッケージプロジェクトもサポートしています。SPMパッケージで作業している場合、何も更新する必要はありません。Tuistは自動的にルートの`Package.swift`を検出し、Tuistのすべての機能はそれが`Project.swift`マニフェストであるかのように動作します。

開始するには、SPMパッケージで`tuist install`と`tuist generate`を実行します。プロジェクトには、通常のXcode SPM統合と同じスキームとファイルがすべて含まれるようになります。さらに、<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>を実行して、SPMの依存関係とモジュールの大部分を事前コンパイルできるようになり、以降のビルドが非常に高速になります。
