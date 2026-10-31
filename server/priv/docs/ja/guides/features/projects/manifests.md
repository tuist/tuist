---
{
  "title": "マニフェスト",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist のプロジェクト、ワークスペース、生成設定を定義するマニフェストファイル。"
}
---
# マニフェスト {#manifests}

Tuist は、プロジェクトとワークスペースを定義し、生成プロセスを設定する主要な方法として Swift ファイルをデフォルトで使用します。これらのファイルはドキュメント全体で**マニフェストファイル**と呼ばれます。

Swift を使用する決定は、パッケージの定義にも Swift ファイルを使用する[Swift Package Manager](https://www.swift.org/documentation/package-manager/)にインスパイアされました。Swift を使用することで、コンパイラを活用してコンテンツの正確性を検証し、異なるマニフェストファイル間でコードを再利用できます。また、Xcode のシンタックスハイライト、自動補完、検証機能により、第一級の編集体験を提供できます。

> [!NOTE]
> **キャッシュ**
>
> マニフェストファイルはコンパイルが必要な Swift ファイルであるため、Tuist は解析プロセスを高速化するためにコンパイル結果をキャッシュします。そのため、Tuist を初めて実行した際は、プロジェクトの生成に少し時間がかかることがあります。以降の実行は高速になります。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) マニフェストは Xcode プロジェクトを宣言します。プロジェクトは、マニフェストファイルが存在するディレクトリに、`name` プロパティで指定された名前で生成されます。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **ルート変数**
>
> マニフェストのルートに配置すべき唯一の変数は `let project = Project(...)` です。マニフェストのさまざまな部分でコードを再利用する必要がある場合は、Swift 関数を使用できます。


## Workspace.swift {#workspaceswift}

デフォルトでは、Tuist は生成中のプロジェクトとその依存関係のプロジェクトを含む [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces) を生成します。何らかの理由でワークスペースをカスタマイズして追加のプロジェクトを追加したり、ファイルやグループを含めたりしたい場合は、[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace) マニフェストを定義することで実現できます。

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

> [!NOTE]
> Tuist は依存関係グラフを解決し、依存関係のプロジェクトをワークスペースに含めます。それらを手動で含める必要はありません。これは、ビルドシステムが依存関係を正しく解決するために必要です。


### マルチプロジェクトまたはモノリシックプロジェクト {#multi-or-monoproject}

よく寄せられる質問の一つは、ワークスペース内で単一のプロジェクトを使用するか、複数のプロジェクトを使用するかです。Tuist がない世界では、モノリシックプロジェクトのセットアップは頻繁な Git コンフリクトを引き起こすため、ワークスペースの使用が推奨されます。しかし、Tuist が生成した Xcode プロジェクトを Git リポジトリに含めることを推奨していないため、Git コンフリクトは問題になりません。したがって、ワークスペース内で単一のプロジェクトを使用するか複数のプロジェクトを使用するかはあなた次第です。

Tuist プロジェクトでは、コールド生成時間が高速（コンパイル対象のマニフェストファイルが少ない）であり、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> をカプセル化の単位として活用しているため、モノリシックプロジェクトを採用しています。ただし、アプリケーションの異なるドメインを表すために Xcode プロジェクトをカプセル化の単位として使用したい場合もあり、これは Xcode が推奨するプロジェクト構造とより一致します。

## Tuist.swift {#tuistswift}

Tuist は <.localized_link href="/contributors/principles#default-to-conventions">合理的なデフォルト値</.localized_link> を提供し、プロジェクト設定を簡素化します。ただし、プロジェクトのルートに [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) を定義することで設定をカスタマイズでき、Tuist はこれを使用してプロジェクトのルートを決定します。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
