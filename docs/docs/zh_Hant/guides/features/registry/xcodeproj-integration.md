---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# 透過基於 XcodeProj 的套件整合所產生的專案{#generated-project-with-xcodeproj-based-integration}

使用
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj
基礎整合</LocalizedLink>時，可透過``--replace-scm-with-registry``
參數從註冊表解析可用依賴項。請將此參數加入`installOptions` 設定檔中的`Tuist.swift` 檔案：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若要確保每次解析依賴項時皆使用註冊表，您需在`Tuist/Package.swift` 檔案中更新`dependencies` 設定，改用註冊表識別碼取代
URL。註冊表識別碼格式固定為`{組織}.{儲存庫}` 。例如欲使用`swift-composable-architecture`
套件的註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
