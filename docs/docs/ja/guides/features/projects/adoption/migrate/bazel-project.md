---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazel プロジェクトの移行{#migrate-a-bazel-project}

[Bazel](https://bazel.build)は、Googleが2015年にオープンソース化したビルドシステムです。これは、あらゆる規模のソフトウェアを迅速かつ確実にビルドおよびテストできる強力なツールです。
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)、[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)などの大規模な組織では採用されていますが、導入・維持には初期投資（技術習得）と継続的な投資（Xcodeのアップデートへの対応など）が必要です。
これを横断的な課題として扱う組織にとっては有効な選択肢ですが、製品開発に注力したい組織にとっては最適な選択肢ではないかもしれません。例えば、iOSプラットフォームチームがBazelを導入したものの、導入を主導したエンジニアが退職した後にBazelを廃止せざるを得なかった組織の事例も見られます。また、Xcodeとビルドシステムとの強固な結合に対するAppleの姿勢も、Bazelプロジェクトを長期的に維持することを困難にしている要因の一つです。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
TuistはXcodeやXcodeプロジェクトと対立するのではなく、それらを積極的に活用します。ターゲット、スキーム、ビルド設定といった同じ概念、Swiftという馴染みのある言語、そしてシンプルで楽しい開発体験により、プロジェクトの維持管理や拡張は、iOSプラットフォームチームだけでなく、全員の役割となります。
<!-- -->
:::

## ルール{#rules}

Bazelは、ソフトウェアのビルドやテストの方法を定義するためにルールを使用します。ルールは、Pythonに似た言語である[Starlark](https://github.com/bazelbuild/starlark)で記述されます。Tuistは設定言語としてSwiftを使用しており、これにより開発者はXcodeのオートコンプリート、型チェック、および検証機能を利用できるという利便性が得られます。例えば、以下のルールはBazelでSwiftライブラリをビルドする方法を記述しています：

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

BazelとTuistでのユニットテストの定義方法を比較した別の例を以下に示します：

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
プラグインを使用して、Swift
Packagesを依存関係として利用できます。このプラグインは、依存関係の信頼できる情報源として、`Package.swift`
を必要とします。その点において、TuistのインターフェースはBazelのそれと似ています。`tuist install`
コマンドを使用して、パッケージの依存関係を解決し、取得できます。解決が完了したら、`tuist generate` コマンドでプロジェクトを生成できます。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## プロジェクトの生成{#project-generation}

コミュニティでは、Bazelで宣言されたプロジェクトからXcodeプロジェクトを生成するための一連のルール
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)
を提供しています。`のBUILD`
ファイルに設定を追加する必要があるBazelとは異なり、Tuistでは一切の設定が不要です。プロジェクトのルートディレクトリで ``tuist
generate` ` を実行するだけで、TuistがXcodeプロジェクトを生成します。
