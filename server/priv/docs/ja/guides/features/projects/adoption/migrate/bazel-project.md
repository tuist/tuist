---
{
  "title": "Bazel プロジェクトの移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Bazel から Tuist へプロジェクトを移行する方法を学びます。"
}
---
# Bazel プロジェクトの移行 {#migrate-a-bazel-project}

[Bazel](https://bazel.build) は、Google が 2015 年にオープンソース化したビルドシステムです。あらゆる規模のソフトウェアを迅速かつ確実にビルド・テストできる強力なツールです。[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/) や [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)、[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) といった大企業でも採用されていますが、導入と維持には初期投資（技術の習得）と継続的な投資（Xcode のアップデートへの対応）が必要です。これを横断的な課題として扱う組織ではうまく機能することもありますが、製品開発に集中したい組織には必ずしも適しているとは限りません。実際、iOS プラットフォームチームが Bazel を導入したが、主導していたエンジニアの退職後に廃止せざるを得なくなった事例もあります。また、Apple が Xcode とビルドシステムの強い結合を重視していることも、Bazel プロジェクトを長期的に維持することを難しくする要因の一つです。

> [!TIP]
> **Tuist の独自性は、その繊細さにあります**
>
> Tuist は Xcode や Xcode プロジェクトと対立するのではなく、それらを受け入れます。同じ概念（ターゲット、スキーム、ビルド設定など）、馴染みのある言語（Swift）、そしてシンプルで快適な体験を提供し、プロジェクトの維持とスケーリングを iOS プラットフォームチームだけでなく、すべてのメンバーの役割にします。


## ルール {#rules}

Bazel では、ソフトウェアのビルド方法やテスト方法を定義するためにルールを使用します。ルールは Python に似た言語である [Starlark](https://github.com/bazelbuild/starlark) で記述されます。一方、Tuist は設定言語として Swift を使用しており、開発者は Xcode の自動補完、型チェック、検証機能を便利に利用できます。例えば、以下のルールは Bazel で Swift ライブラリをビルドする方法を示しています。

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["**/*.swift"]
        )
    ]
)
```
<!-- -->
:::

次に、Bazel と Tuist でユニットテストを定義する方法を比較した例を示します。

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Swift Package Manager の依存関係 {#swift-package-manager-dependencies}

Bazel では、[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) の [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) プラグインを使用して Swift Packages を依存関係として利用できます。このプラグインでは、依存関係の信頼できる情報源として `Package.swift` が必要です。この点において、Tuist のインターフェースは Bazel と類似しています。`tuist install` コマンドを使用してパッケージの依存関係を解決および取得できます。解決が完了したら、`tuist generate` コマンドでプロジェクトを生成できます。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## プロジェクトの生成 {#project-generation}

コミュニティは、Bazel で宣言されたプロジェクトから Xcode プロジェクトを生成するためのルールセット [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) を提供しています。Bazel では `BUILD` ファイルに何らかの設定を追加する必要がありますが、Tuist では設定が一切不要です。プロジェクトのルートディレクトリで `tuist generate` を実行するだけで、Tuist が Xcode プロジェクトを生成します。
