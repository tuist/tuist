---
{
  "title": "マニフェスト",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist のプロジェクト、ワークスペース、および生成設定を定義するマニフェストファイル。"
}
---
# マニフェスト {#manifests}

Tuist は、プロジェクトとワークスペースを定義し、生成プロセスを設定するための主要な方法として Swift ファイルをデフォルトで使用します。これらのファイルは、ドキュメント全体で **マニフェストファイル** と呼ばれます。

Swift を使用するという決定は、パッケージの定義にも Swift ファイルを使用する [Swift Package Manager](https://www.swift.org/documentation/package-manager/) に影響を受けました。Swift のおかげで、コンパイラを活用してコンテンツの正確性を検証したり、異なるマニフェストファイル間でコードを再利用したりできます。また、Xcode ではシンタックスハイライト、オートコンプリート、および検証機能により、第一級の編集体験を提供できます。

> [!NOTE]
> **キャッシング**
>
> マニフェストファイルはコンパイルが必要な Swift ファイルであるため、Tuist は解析プロセスを高速化するためにコンパイル結果をキャッシュします。そのため、初めて Tuist を実行した際には、プロジェクトの生成に少し時間がかかることがあります。以降の実行はより高速になります。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) マニフェストは Xcode プロジェクトを宣言します。プロジェクトは、マニフェストファイルが存在する同じディレクトリに、`name` プロパティで指定された名前で生成されます。

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
> Tuist は依存関係グラフを解決し、依存関係のプロジェクトをワークスペースに含めます。これらを手动で含める必要はありません。これは、ビルドシステムが依存関係を正しく解決するために必要です。


### マルチプロジェクトまたはモノプロジェクト {#multi-or-monoproject}

よくある質問として、ワークスペース内で単一のプロジェクトを使用するか、複数のプロジェクトを使用するかがあります。Tuist がない世界では、モノプロジェクト構成会导致頻繁な Git コンフリクトを引き起こすため、ワークスペースの使用が推奨されます。しかし、Tuist で生成された Xcode プロジェクトを Git リポジトリに含めることを推奨していないため、Git コンフリクトは問題になりません。したがって、ワークスペース内で単一のプロジェクトを使用するか、複数のプロジェクトを使用するかはあなた次第です。

Tuist プロジェクトでは、コールド生成時間が高速（コンパイルするマニフェストファイルが少ない）であり、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link> をカプセル化の単位として活用するため、モノプロジェクトに傾倒しています。ただし、アプリケーションの異なるドメインを表すために Xcode プロジェクトをカプセル化の単位として使用したい場合があり、これは Xcode が推奨するプロジェクト構造とより密接に一致します。

## Tuist.swift {#tuistswift}

Tuist は、プロジェクト設定を簡素化するために <.localized_link href="/contributors/principles#default-to-conventions">合理的なデフォルト値</.localized_link> を提供します。ただし、プロジェクトのルートに [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) を定義することで設定をカスタマイズできます。これは、Tuist がプロジェクトのルートを特定するために使用されます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
