---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# 使用基於 XcodeProj 的套件整合產生專案{#generated-project-with-xcodeproj-based-integration}

當使用基於
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 的整合</LocalizedLink>時，您可以使用``--replace-scm-with-registry``
標誌來解析註冊表中的依存項目（如果它們可用）。將其加入`Tuist.swift` 檔案中的`installOptions` ：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果您希望確保每次解析相依性時都使用註冊表，則需要更新`Tuist/Package.swift` 檔案中的`相依性` ，以使用註冊表識別符而非
URL。註冊表識別符的形式總是`{organization}.{repository}`
。例如，要使用`swift-composable-architecture` 软件包的注册表，请执行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
