---
{
  "title": "XcodeProjベースのパッケージ統合を用いた生成済みプロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "生成済みプロジェクトで、XcodeProjベースのパッケージ統合とともにTuist Registryを使用します。"
}
---
# XcodeProjベースのパッケージ統合を使用した生成プロジェクト {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProjベースの統合</.localized_link>を使用する場合、レジストリで利用可能な依存関係を解決するために`--replace-scm-with-registry`フラグを使用できます。これを`Tuist.swift`ファイル内の`installOptions`に追加してください:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係の解決時に毎回レジストリが使用されるようにするには、`Tuist/Package.swift`ファイル内の`dependencies`を更新して、URLではなくレジストリ識別子を使用する必要があります。

<!-- @snippet: ./_registry-identifier -->
