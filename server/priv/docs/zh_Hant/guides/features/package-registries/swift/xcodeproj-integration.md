---
{
  "title": "使用 XcodeProj 基礎套件整合的產生專案",
  "titleTemplate": ":title · Swift · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "在產生的專案中，將 Tuist Registry 與 XcodeProj 基礎套件整合搭配使用。"
}
---
# 使用 XcodeProj 基礎套件整合產生的專案 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 基礎整合</.localized_link> 時，若註冊表中有所需的相依性，你可以使用 ``--replace-scm-with-registry`` 旗標從註冊表解析相依性。將其加入 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若要確保每次解析相依性時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，改用註冊表識別碼而非 URL。註冊表識別碼的格式一律為 `{organization}.{repository}`。例如，若要對 `swift-composable-architecture` 套件使用註冊表，請執行以下操作：
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
