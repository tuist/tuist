---
{
  "title": "基于 XcodeProj 的包集成生成的项目",
  "titleTemplate": ":title · Swift · 包注册表 · 功能 · 指南 · Tuist",
  "description": "在生成的项目中使用 Tuist Registry 与基于 XcodeProj 的包集成。"
}
---
# 使用基于 XcodeProj 的包集成生成的项目 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">基于 XcodeProj 的集成</.localized_link> 时，如果注册表中存在依赖项，你可以使用 ``--replace-scm-with-registry`` 标志从注册表解析它们。将其添加到 `Tuist.swift` 文件中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你希望确保每次解析依赖项时都使用注册表，则需要更新 `Tuist/Package.swift` 文件中的 `dependencies`，以使用注册表标识符而不是 URL。注册表标识符始终采用 `{organization}.{repository}` 的形式。例如，要为 `swift-composable-architecture` 包使用注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
