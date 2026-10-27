---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# 使用基于 XcodeProj 的软件包集成生成项目{#generated-project-with-xcodeproj-based-integration}

在使用基于
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 的集成</LocalizedLink>时，您可以使用``--replace-scm-with-registry``
标志来解析注册表中的依赖项（如果有的话）。将其添加到`Tuist.swift` 文件中的`installOptions` ：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果要确保每次解析依赖关系时都使用注册表，则需要更新`Tuist/Package.swift` 文件中的`依赖关系` ，以使用注册表标识符而不是
URL。注册表标识符的形式总是`{organization}.{repository}`
。例如，要使用`swift-composable-architecture` 软件包的注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
