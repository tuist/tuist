---
{
  "title": "マニフェスト",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist のプロジェクト、ワークスペース、生成設定を定義するマニフェストファイル。"
}
---
# マニフェスト {#manifests}

Tuist は、プロジェクトとワークスペースを定義し、生成プロセスを設定するための主要な方法として Swift ファイルをデフォルトで使用します。これらのファイルは、ドキュメント全体で**マニフェストファイル**と呼ばれます。

Swift を使用する決定は、パッケージの定義にも Swift ファイルを使用する[Swift Package Manager](https://www.swift.org/documentation/package-manager/)に触発されました。Swift を使用することで、コンパイラを活用してコンテンツの正確性を検証し、異なるマニフェストファイル間でコードを再利用できます。また、Xcode はシンタックスハイライト、オートコンプリート、および検証により、第一級の編集体験を提供します。

> [!NOTE]
> **キャッシュ**
>
> マニフェストファイルはコンパイルが必要な Swift ファイルであるため、Tuist は解析プロセスを高速化するためにコンパイル結果をキャッシュします。そのため、初めて Tuist を実行すると、プロジェクトの生成に少し時間がかかることがあります。以降の実行は高速になります。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) マニフェストは Xcode プロジェクトを宣言します。プロジェクトは、マニフェストファイルが配置されている同じディレクトリに、`name` プロパティで指定された名前で生成されます。

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

デフォルトでは、Tuist は生成中のプロジェクトとその依存関係のプロジェクトを含む[Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)を生成します。何らかの理由でワークスペースをカスタマイズして追加のプロジェクトを追加したり、ファイルやグループを含めたりしたい場合は、[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace) マニフェストを定義することで実現できます。

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


### マルチプロジェクトまたはモノプロジェクト {#multi-or-monoproject}

よくある質問として、ワークスペース内で単一のプロジェクトを使用するか、複数のプロジェクトを使用するかという点があります。Tuist がない世界では、モノプロジェクトのセットアップは頻繁な Git コンフリクトを引き起こすため、ワークスペースの使用が推奨されます。しかし、Tuist が生成した Xcode プロジェクトを Git リポジトリに含めることを推奨していないため、Git コンフリクトは問題になりません。したがって、ワークスペース内で単一のプロジェクトを使用するか複数のプロジェクトを使用するかはあなた次第です。

Tuist プロジェクトでは、コールド生成時間が高速（コンパイルするマニフェストファイルが少ない）であり、<.localized_link href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</.localized_link>をカプセル化の単位として活用しているため、モノプロジェクトに傾倒しています。ただし、アプリケーションの異なるドメインを表すために Xcode プロジェクトをカプセル化の単位として使用したい場合もあるかもしれません。これは Xcode の推奨プロジェクト構造とより密接に一致します。

## Tuist.swift {#tuistswift}

Tuist は、プロジェクト構成を簡素化するための<.localized_link href="/contributors/principles#default-to-conventions">合理的なデフォルト</.localized_link>を提供します。ただし、プロジェクトのルートに [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) を定義することで構成をカスタマイズできます。これは、Tuist がプロジェクトのルートを決定するために使用されます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(registryEnabled: true))
)
```
