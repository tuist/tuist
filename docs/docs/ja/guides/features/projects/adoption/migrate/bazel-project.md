---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazelプロジェクトを移行する{#migrate-a-bazel-project}

[Bazel](https://bazel.build)は、Googleが2015年にオープンソース化したビルドシステムである。あらゆる規模のソフトウェアを迅速かつ確実にビルドし、テストできる強力なツールだ。Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)、または[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)のようないくつかの大規模な組織がこれを使用しているが、導入と維持には先行投資（つまり、技術を学ぶこと）と継続的な投資（つまり、Xcodeのアップデートに追いつくこと）が必要である。これは、それを横断的な問題として扱う一部の組織には有効ですが、製品開発に集中したい他の組織には最適ではないかもしれません。例えば、iOSプラットフォームチームがBazelを導入し、その取り組みを主導したエンジニアが退社した後、Bazelを中止せざるを得なかった組織を見たことがある。Xcodeとビルドシステムの間の強い結合に対するAppleのスタンスは、Bazelプロジェクトを長期にわたって維持することを難しくするもう1つの要因だ。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
XcodeやXcodeプロジェクトと戦う代わりに、Tuistはそれを受け入れる。同じコンセプト（ターゲット、スキーム、ビルド設定など）、慣れ親しんだ言語（つまりSwift）、そしてシンプルで楽しいエクスペリエンスによって、iOSプラットフォーム・チームだけでなく、プロジェクトの維持とスケーリングをみんなの仕事にするのだ。
<!-- -->
:::

## ルール{#rules}

Bazelは、ソフトウェアのビルドとテストの方法を定義するためにルールを使用する。ルールは、Pythonに似た言語である[Starlark](https://github.com/bazelbuild/starlark)で書かれている。Tuistは設定言語としてSwiftを使用し、Xcodeのオートコンプリート、タイプチェック、検証機能を使用する利便性を開発者に提供します。例えば、以下のルールはBazelでSwiftライブラリを構築する方法を説明している：

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

別の例だが、BazelとTuistのユニットテストの定義方法を比較してみよう：

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


## Swift パッケージマネージャの依存関係{#swift-package-manager-dependencies}

Bazel
では、[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
を使うことができます。[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
プラグインを使うことができます。プラグインは依存関係のための真実のソースとして`Package.swift`
を必要とします。Tuistのインターフェイスはその意味でBazelと似ている。`tuist install`
コマンドを使って、パッケージの依存関係を解決し、引き出すことができます。解決完了後、`tuist generate` コマンドでプロジェクトを生成できます。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## プロジェクト・ジェネレーション{#project-generation}

コミュニティは、Bazelで宣言されたプロジェクトからXcodeプロジェクトを生成するためのルールセット、[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)を提供しています。`BUILD`
ファイルに設定を追加する必要がある Bazel とは異なり、Tuist は設定を全く必要としません。プロジェクトのルートディレクトリで`tuist
generate` を実行すれば、TuistがXcodeプロジェクトを生成してくれます。
