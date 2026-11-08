---
{
  "title": "使用基于 XcodeProj 的包集成的生成项目",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "在生成的项目中使用带有基于 XcodeProj 的包集成的 Tuist Registry。"
}
---
# 使用基于 XcodeProj 的包集成生成的项目 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">基于 XcodeProj 的集成</.localized_link> 时，如果注册表中存在依赖项，你可以使用 `--replace-scm-with-registry` 标志从注册表解析它们。将其添加到 `Tuist.swift` 文件中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你希望确保每次解析依赖项时都使用注册表，则需要更新 `Tuist/Package.swift` 文件中的 `dependencies`，以使用注册表标识符而非 URL。

<!-- @snippet: ./_registry-identifier -->
