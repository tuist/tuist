---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazelプロジェクトを移行する{#migrate-a-bazel-project}

[Bazel](https://bazel.build) は、Google が 2015
年にオープンソース化したビルドシステムです。あらゆる規模のソフトウェアを迅速かつ確実にビルド・テストできる強力なツールです。
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)、[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)などの大規模組織が採用していますが、導入・維持には初期投資（技術習得）と継続的投資（Xcode更新への対応）が必要です。
これを横断的な課題として扱う組織には有効ですが、製品開発に集中したい組織には最適とは言えません。例えば、iOSプラットフォームチームがBazelを導入したものの、主導したエンジニアが退職した後に廃止せざるを得なかった事例があります。Xcodeとビルドシステムの強固な結合に対するAppleの姿勢も、Bazelプロジェクトを長期的に維持する上での障壁となっています。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
XcodeやXcodeプロジェクトと戦う代わりに、Tuistはそれらを受け入れます。同じ概念（例：ターゲット、スキーム、ビルド設定）、馴染み深い言語（Swift）、そしてシンプルで楽しい体験により、プロジェクトの維持管理と拡張はiOSプラットフォームチームだけでなく、全員の仕事となります。
<!-- -->
:::

## ルール{#rules}

Bazelはルールを用いてソフトウェアのビルドとテスト方法を定義します。ルールはPythonに似た言語である[Starlark](https://github.com/bazelbuild/starlark)で記述されます。Tuistは設定言語としてSwiftを使用しており、これにより開発者はXcodeの自動補完、型チェック、検証機能を利用できます。例えば、以下のルールはBazelでSwiftライブラリをビルドする方法を記述しています：

コードグループ
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
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

BazelとTuistにおけるユニットテストの定義方法を比較する別の例：

コードグループ
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


## Swift Package Manager の依存関係{#swift-package-manager-dependencies}

Bazelでは、[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
プラグインを使用してSwiftパッケージを依存関係として利用できます。このプラグインは、依存関係の信頼できる情報源として`Package.swift`
を必要とします。この点においてTuistのインターフェースはBazelと類似しています。 パッケージの依存関係を解決・取得するには、`tuist
install` コマンドを使用できます。解決完了後、`tuist generate` コマンドでプロジェクトを生成できます。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## プロジェクト生成{#project-generation}

`
コミュニティは、Bazelで宣言されたプロジェクトからXcodeプロジェクトを生成するための一連のルール、[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)を提供しています。Bazelでは`のBUILDファイルに設定を追加する必要がありますが、Tuistでは一切の設定が不要です。プロジェクトのルートディレクトリで`tuist
generate` を実行すると、TuistがXcodeプロジェクトを生成します。
