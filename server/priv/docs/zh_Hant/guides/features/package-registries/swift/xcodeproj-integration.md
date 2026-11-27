---
{
  "title": "使用 XcodeProj 套件整合的產生專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "在產生的專案中，將 Tuist Registry 與 XcodeProj 套件整合搭配使用。"
}
---
# 使用 XcodeProj 型套件整合的已產生專案 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 型整合</.localized_link> 時，若相依性可用於登錄庫，你可以使用 `--replace-scm-with-registry` 旗標從登錄庫解析相依性。將其加入你的 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若要確保每次解析相依性時都使用登錄庫，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，改用登錄庫識別碼而非 URL。

<!-- @snippet: ./_registry-identifier -->
