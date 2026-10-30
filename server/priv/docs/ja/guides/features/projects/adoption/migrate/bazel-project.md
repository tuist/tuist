---
{
  "title": "Bazel プロジェクトの移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Bazel から Tuist へプロジェクトを移行する方法を学びます。"
}
---
# Bazelプロジェクトの移行 {#migrate-a-bazel-project}

[Bazel](https://bazel.build)は、Googleが2015年にオープンソース化したビルドシステムです。あらゆる規模のソフトウェアを迅速かつ確実にビルドおよびテストできる強力なツールです。[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)、[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)などの大企業でも利用されていますが、導入と維持には初期投資（技術の習得）と継続的な投資（Xcodeのアップデートへの対応）が必要です。これを横断的な課題として扱える組織では機能しますが、プロダクト開発に集中したい組織にとっては最適な選択肢ではない場合があります。例えば、iOSプラットフォームチームがBazelを導入したが、主導していたエンジニアが退職した後に断念せざるを得なくなった組織を目にしました。また、AppleがXcodeとビルドシステムの強い結合を重視していることも、Bazelプロジェクトを長期的に維持することを難しくする要因の一つです。

> [!TIP]
> **Tuistの独自性は、その繊細さにある**
>
> TuistはXcodeやXcodeプロジェクトと戦うのではなく、それらを受け入れます。同じ概念（ターゲット、スキーム、ビルド設定など）、馴染みのある言語（Swift）、そしてシンプルで楽しい体験を提供し、プロジェクトの維持とスケーリングをiOSプラットフォームチームだけでなく、すべてのメンバーの役割にします。


## ルール {#rules}

Bazelはルールを使用してソフトウェアのビルドとテスト方法を定義します。ルールはPythonのような言語である[Starlark](https://github.com/bazelbuild/starlark)で記述されます。Tuistは設定言語としてSwiftを使用しており、開発者はXcodeの自動補完、型チェック、検証機能の利便性を享受できます。例えば、以下のルールはBazelでSwiftライブラリをビルドする方法を示しています。

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
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

次に、BazelとTuistでユニットテストを定義する方法を比較した例を示します。

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


## Swift Package Managerの依存関係 {#swift-package-manager-dependencies}

Bazelでは、[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)プラグインを使用してSwift Packagesを依存関係として利用できます。このプラグインでは、依存関係の信頼できる情報源として`Package.swift`が必要です。Tuistのインターフェースもその点ではBazelと似ています。`tuist install`コマンドを使用してパッケージの依存関係を解決および取得できます。解決が完了したら、`tuist generate`コマンドでプロジェクトを生成できます。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## プロジェクトの生成 {#project-generation}

コミュニティは、Bazelで宣言されたプロジェクトからXcodeプロジェクトを生成するためのルールセット[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)を提供しています。Bazelでは`BUILD`ファイルに何らかの設定を追加する必要がありますが、Tuistでは設定は一切不要です。プロジェクトのルートディレクトリで`tuist generate`を実行すると、TuistがXcodeプロジェクトを生成します。
