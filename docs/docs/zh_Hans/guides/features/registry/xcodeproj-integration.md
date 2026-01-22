---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# 基于XcodeProj的包集成生成的项目{#generated-project-with-xcodeproj-based-integration}

使用<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj集成方案</LocalizedLink>时，可通过``--replace-scm-with-registry``
参数从注册库解析依赖项（若可用）。请在`Tuist.swift` 文件的`安装选项` 中添加此参数：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若需确保每次解析依赖时都使用注册库，请在`Tuist/Package.swift` 文件中将`dependencies`
修改为使用注册库标识符替代URL。注册库标识符始终采用`{organization}.{repository}`
格式。例如，要为`swift-composable-architecture` 包启用注册库，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
