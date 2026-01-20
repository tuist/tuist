---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# マニフェスト{#manifests}

Tuistは、プロジェクトとワークスペースを定義し、生成プロセスを設定する主な方法として、Swiftファイルをデフォルトとしています。これらのファイルはドキュメント全体を通して**マニフェストファイル**
と呼ばれています。

Swiftを使用するという決定は、パッケージを定義するためにSwiftファイルも使用する[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)に触発されました。Swiftを使用するおかげで、内容の正しさを検証し、異なるマニフェストファイル間でコードを再利用するためにコンパイラを活用することができ、構文のハイライト、オートコンプリート、および検証のおかげでファーストクラスの編集エクスペリエンスを提供するためにXcodeを活用することができます。

::: info CACHING
<!-- -->
マニフェストファイルはコンパイルが必要な Swift ファイルであるため、Tuist
はコンパイル結果をキャッシュして解析処理を高速化します。そのため、Tuist
を最初に実行したときは、プロジェクトの生成に少し時間がかかるかもしれません。その後の実行は速くなる。
<!-- -->
:::

## プロジェクト.swift{#projectswift}

`Project.swift` マニフェストは Xcode プロジェクトを宣言します。プロジェクトは、`name`
プロパティに示された名前で、マニフェストファイルがあるのと同じディレクトリに生成されます。

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
マニフェストのルートにあるべき唯一の変数は`let project = Project(...)`
です。マニフェストのさまざまな部分でコードを再利用する必要がある場合、Swift 関数を使用することができます。
<!-- -->
:::

## ワークスペース.swift{#workspaceswift}

デフォルトでは、Tuist は生成されるプロジェクトとその依存関係のプロジェクトを含む [Xcode
ワークスペース](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
を生成します。何らかの理由でワークスペースをカスタマイズしてプロジェクトを追加したり、ファイルやグループをインクルードしたい場合は、<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>マニフェストを定義することで可能です。

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
Tuistは依存関係グラフを解決し、依存関係のプロジェクトをワークスペースに含めます。それらを手動でインクルードする必要はない。これはビルドシステムが依存関係を正しく解決するために必要なことである。
<!-- -->
:::

### マルチまたはモノ・プロジェクト{#multi-or-monoproject}

よく出てくる疑問は、ワークスペースで単一のプロジェクトを使うか、複数のプロジェクトを使うかということだ。Tuistのない世界では、単一プロジェクトのセットアップが頻繁なGitコンフリクトにつながるため、ワークスペースの使用が推奨されます。しかし、私たちはTuistが生成したXcodeプロジェクトをGitリポジトリに含めることを推奨していないので、Gitの衝突は問題ではない。したがって、ワークスペースに単一のプロジェクトを使うか、複数のプロジェクトを使うかは、あなた次第です。

Tuistプロジェクトでは、コールド生成時間がより速く（コンパイルするマニフェストファイルがより少ない）、カプセル化の単位として<LocalizedLink href="/guides/features/projects/code-sharing">プロジェクト記述ヘルパー</LocalizedLink>を活用するため、モノプロジェクトに傾いています。しかし、アプリケーションの異なるドメインを表すカプセル化の単位としてXcodeプロジェクトを使用したいかもしれません。

## Tuist.swift{#tuistswift}

Tuistは<LocalizedLink href="/contributors/principles.html#default-to-conventions">分かりやすいデフォルト</LocalizedLink>を提供し、プロジェクト構成を簡素化します。しかし、<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>をプロジェクトのルートに定義することで設定をカスタマイズすることができます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
