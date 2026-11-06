---
{
  "title": "XcodeProjベースのパッケージ統合による生成プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "生成プロジェクトでXcodeProjベースのパッケージ統合とともにTuist Registryを使用します。"
}
---
# XcodeProjベースのパッケージ統合による生成プロジェクト {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProjベースの統合</.localized_link>を使用する場合、レジストリで利用可能な依存関係があれば、`--replace-scm-with-registry`フラグを使用してそれらを解決できます。これを`Tuist.swift`ファイルの`installOptions`に追加してください:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

依存関係を解決するたびに必ずレジストリを使用するようにするには、`Tuist/Package.swift`ファイル内の`dependencies`を更新して、URLではなくレジストリ識別子を使用する必要があります。

<!-- @snippet: ./_registry-identifier -->
