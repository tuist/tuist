---
{
  "title": "以 XcodeProj 為基礎嘅套件整合生成專案",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "喺生成專案入面，將 Tuist Registry 同以 XcodeProj 為基礎嘅套件整合一齊使用。"
}
---
# 使用 XcodeProj 基礎套件整合的生成專案 {#generated-project-with-xcodeproj-based-integration}

當使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 基礎整合</.localized_link> 時，如果註冊表中有可用依賴項，你可以使用 ``--replace-scm-with-registry`` 旗標從註冊表解析依賴項。將其添加到你的 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你想確保每次解析依賴項時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，以使用註冊表識別符而非 URL。註冊表識別符始終採用 `{organization}.{repository}` 的形式。例如，要為 `swift-composable-architecture` 套件使用註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
