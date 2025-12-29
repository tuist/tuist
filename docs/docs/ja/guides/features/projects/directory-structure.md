---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# ディレクトリ構造 {#directory-structure}

Tuist プロジェクトは、Xcode プロジェクトを置き換えるために一般的に使用されますが、この使用例に限定されるものではありません。Tuist
プロジェクトは、SPM
パッケージ、テンプレート、プラグイン、タスクなどの他のタイプのプロジェクトを生成するためにも使用されます。このドキュメントでは、Tuist
プロジェクトの構造とその整理方法について説明します。後の節では、テンプレート、プラグイン、タスクを定義する方法について説明する。

## 標準Tuistプロジェクト{#standard-tuist-projects}。

Tuistプロジェクトは、**、Tuistによって生成される最も一般的なタイプのプロジェクトである。**
アプリ、フレームワーク、ライブラリなどを構築するために使用される。Xcodeプロジェクトとは異なり、TuistプロジェクトはSwiftで定義され、より柔軟でメンテナンスしやすくなっています。また、Tuist
プロジェクトはより宣言的で、理解しやすく、推論しやすくなっています。以下の構造は、Xcodeプロジェクトを生成する典型的なTuistプロジェクトを示している：

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

- **Tuistディレクトリ：** このディレクトリには2つの目的がある。第一に、プロジェクトのルートが**
  であることを**に知らせる。これにより、プロジェクトのルートからの相対パスを構築し、プロジェクト内のどのディレクトリからでもTuistコマンドを実行することができる。第二に、以下のファイルのコンテナである：
  - **ProjectDescriptionHelpers：** このディレクトリには、すべてのマニフェスト ファイルで共有される Swift
    コードが含まれます。マニフェストファイルは`ProjectDescriptionHelpers`
    をインポートして、このディレクトリで定義されたコードを使用することができます。コードを共有することは、重複を避け、プロジェクト間の一貫性を確保するために有用です。
  - **Package.swift：**
    このファイルには、TuistがXcodeプロジェクトと（[CocoaPods](https://cococapods)のような）設定可能で最適化可能なターゲットを使用してそれらを統合するためのSwift
    Packageの依存関係が含まれています。詳しくは<LocalizedLink href="/guides/features/projects/dependencies">こちら</LocalizedLink>。

- **ルート・ディレクトリ** ：`Tuist` ディレクトリも含むプロジェクトのルートディレクトリ。
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>このファイルには、すべてのプロジェクト、ワークスペース、環境で共有されるTuistの設定が含まれています。例えば、スキームの自動生成を無効にしたり、プロジェクトのデプロイメントターゲットを定義したりするのに使用できます。
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>このマニフェストは、Xcode
    ワークスペースを表します。他のプロジェクトをグループ化するために使用され、追加のファイルやスキームを追加することもできます。
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>プロジェクト.swift:</bold></LocalizedLink>。このマニフェストは、Xcode
    プロジェクトを表します。これは、プロジェクトの一部であるターゲットとその依存関係を定義するために使用されます。

上記のプロジェクトと対話するとき、コマンドは`Workspace.swift` または`Project.swift`
ファイルが作業ディレクトリまたは`--path` フラグで指定されたディレクトリにあることを期待します。マニフェストは、プロジェクトのルートを表す`Tuist`
ディレクトリを含むディレクトリのディレクトリまたはサブディレクトリにある必要があります。

::: チップ
<!-- -->
Xcodeのワークスペースは、プロジェクトを複数のXcodeプロジェクトに分割し、マージの衝突の可能性を減らすことができた。そのためにワークスペースを使用していたのであれば、Tuistでは必要ない。Tuistはプロジェクトとその依存関係のプロジェクトを含むワークスペースを自動生成する。
<!-- -->
:::

## Swiftパッケージ <Badge type="warning" text="beta" />{#swift-package-badge-typewarning-textbeta-}.

TuistはSPMパッケージプロジェクトもサポートしている。SPMパッケージで作業している場合、何も更新する必要はないはずです。Tuistは自動的にあなたのルート`Package.swift`
をピックアップし、あたかも`Project.swift` マニフェストであるかのようにTuistのすべての機能が動作します。

始めるには、SPMパッケージで`tuist install` と`tuist generate`
を実行してください。これで、あなたのプロジェクトは、バニラXcode
SPM統合で表示されるのと同じスキームとファイルをすべて持つようになります。しかし、<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>を実行し、SPMの依存関係とモジュールの大部分をプリコンパイルすることもできます。
