---
{
  "title": "ディレクトリ構造",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist プロジェクトの構造と整理方法について学びます。"
}
---
# ディレクトリ構造 {#directory-structure}

Tuistプロジェクトは一般的にXcodeプロジェクトを置き換えるために使用されますが、この用途に限定されるものではありません。Tuistプロジェクトは、SPMパッケージ、テンプレート、プラグイン、タスクなど、他の種類のプロジェクトを生成するためにも使用されます。このドキュメントでは、Tuistプロジェクトの構造とその整理方法について説明します。後のセクションでは、テンプレート、プラグイン、タスクの定義方法についても取り上げます。

## 標準的なTuistプロジェクト {#standard-tuist-projects}

Tuistプロジェクトは**Tuistによって生成される最も一般的なタイプのプロジェクトです。** これらは、アプリ、フレームワーク、ライブラリなどをビルドするために使用されます。Xcodeプロジェクトとは異なり、TuistプロジェクトはSwiftで定義されるため、より柔軟で保守が容易です。また、宣言的であるため、理解しやすく、推論しやすいという特徴もあります。以下の構造は、Xcodeプロジェクトを生成する典型的なTuistプロジェクトを示しています。

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

- **Tuistディレクトリ:** このディレクトリには2つの目的があります。まず、**プロジェクトのルートがどこにあるか**を示します。これにより、プロジェクトのルートに対する相対パスを構築したり、プロジェクト内の任意のディレクトリからTuistコマンドを実行したりできます。次に、以下のファイルのコンテナとなります。
  - **ProjectDescriptionHelpers:** このディレクトリには、すべてのマニフェストファイルで共有されるSwiftコードが含まれています。マニフェストファイルはこのディレクトリで定義されたコードを使用するために`import ProjectDescriptionHelpers`できます。コードを共有することは、重複を避け、プロジェクト間の一貫性を確保するのに役立ちます。
  - **Package.swift:** このファイルには、TuistがXcodeプロジェクトとターゲットを使用して統合するためのSwift Package依存関係（[CocoaPods](https://cococapods)のような構成可能で最適化可能なもの）が含まれています。詳細は<.localized_link href="/guides/features/projects/dependencies">こちら</.localized_link>をご覧ください。

- **ルートディレクトリ**: プロジェクトのルートディレクトリであり、`Tuist`ディレクトリも含まれています。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></.localized_link> このファイルには、すべてのプロジェクト、ワークスペース、環境で共有されるTuistの構成が含まれています。例えば、スキームの自動生成を無効にしたり、プロジェクトのデプロイメントターゲットを定義したりするために使用できます。
  - <.localized_link href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></.localized_link> このマニフェストはXcodeワークスペースを表します。他のプロジェクトをグループ化するために使用され、追加のファイルやスキームを追加することもできます。
  - <.localized_link href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></.localized_link> このマニフェストはXcodeプロジェクトを表します。プロジェクトの一部であるターゲットとその依存関係を定義するために使用されます。

上記のプロジェクトを操作する場合、コマンドは作業ディレクトリまたは`--path`フラグで指定されたディレクトリに`Workspace.swift`または`Project.swift`ファイルがあることを期待します。マニフェストは、プロジェクトのルートを表す`Tuist`ディレクトリを含むディレクトリ、またはそのサブディレクトリにある必要があります。

> [!TIP]
> Xcodeワークスペースでは、マージ競合の可能性を減らすために、プロジェクトを複数のXcodeプロジェクトに分割することができました。もしあなたがワークスペースをその目的で使用していたのであれば、Tuistではそれらは必要ありません。Tuistは、プロジェクトとその依存関係のプロジェクトを含むワークスペースを自動生成します。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

TuistはSPMパッケージプロジェクトもサポートしています。SPMパッケージで作業している場合、何も更新する必要はありません。Tuistは自動的にルートの`Package.swift`を検出し、Tuistのすべての機能はそれが`Project.swift`マニフェストであるかのように動作します。

開始するには、SPMパッケージで`tuist install`および`tuist generate`を実行してください。あなたのプロジェクトには現在、通常のXcode SPM統合で見られるものと同じすべてのスキームとファイルがあるはずです。しかし、今では<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>を実行し、SPM依存関係とモジュールの大部分を事前コンパイルできるため、後続のビルドが非常に高速になります。
