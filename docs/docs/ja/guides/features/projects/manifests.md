---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# マニフェスト{#manifests}

Tuistは、プロジェクトとワークスペースの定義、および生成プロセスの設定を主にSwiftファイルで行うことをデフォルトとしています。これらのファイルは、ドキュメント全体で**マニフェストファイル**
と呼ばれています。

Swiftの採用は、パッケージ定義にSwiftファイルを使用する[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)に触発されたものです。Swiftの採用により、コンパイラを活用した内容の正確性検証や異なるマニフェストファイル間でのコード再利用が可能となり、Xcodeの構文ハイライト・自動補完・検証機能による優れた編集環境を実現しています。

::: info CACHING
<!-- -->
マニフェストファイルはコンパイルが必要なSwiftファイルであるため、Tuistは解析処理を高速化するためにコンパイル結果をキャッシュします。そのため、Tuistを初めて実行する際はプロジェクト生成に少し時間がかかる場合があります。以降の実行は高速化されます。
<!-- -->
:::

## Project.swift{#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
マニフェストはXcodeプロジェクトを宣言します。プロジェクトはマニフェストファイルが存在するディレクトリ内に、`name`
プロパティで指定された名前で生成されます。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
マニフェストのルートに置くべき唯一の変数は`let project = Project(...)`
です。マニフェストの複数箇所でコードを再利用する必要がある場合は、Swift関数を使用できます。
<!-- -->
:::

## Workspace.swift{#workspaceswift}

デフォルトでは、Tuistは生成対象プロジェクトとその依存プロジェクトを含む[Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)を生成します。何らかの理由でワークスペースをカスタマイズし、追加プロジェクトやファイル・グループを含めたい場合は、<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
マニフェストを定義することで実現できます。

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

::: info
<!-- -->
Tuistは依存関係グラフを解決し、ワークスペースに依存関係のプロジェクトを含めます。手動で追加する必要はありません。これはビルドシステムが依存関係を正しく解決するために必要です。
<!-- -->
:::

### マルチプロジェクトまたは単一プロジェクト{#multi-or-monoproject}

よくある質問として、ワークスペース内で単一プロジェクトを使用するか複数プロジェクトを使用するかが挙げられます。Tuistが存在しない環境では、単一プロジェクト構成は頻繁なGitコンフリクトを引き起こすため、ワークスペースの使用が推奨されます。しかし、Tuistが生成したXcodeプロジェクトをGitリポジトリに含めることは推奨していないため、Gitコンフリクトは問題になりません。したがって、ワークスペース内で単一プロジェクトを使用するか複数プロジェクトを使用するかは、ご自身の判断に委ねられます。

Tuistプロジェクトでは、初期生成時間が短縮される（コンパイル対象のマニフェストファイルが少なくなる）ため単一プロジェクトを採用し、カプセル化の単位として<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</LocalizedLink>を活用しています。ただし、アプリケーションの異なるドメインを表現するカプセル化の単位としてXcodeプロジェクトを使用することも可能です。これはXcodeが推奨するプロジェクト構造により適合します。

## Tuist.swift{#tuistswift}

Tuistはプロジェクト設定を簡素化するため、<LocalizedLink href="/contributors/principles.html#default-to-conventions">合理的なデフォルト設定</LocalizedLink>を提供します。ただし、プロジェクトルートに<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>を定義することで設定をカスタマイズ可能です。Tuistはこの設定ファイルを用いてプロジェクトのルートを判定します。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
