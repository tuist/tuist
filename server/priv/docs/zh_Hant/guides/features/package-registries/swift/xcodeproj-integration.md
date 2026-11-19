---
{
  "title": "使用基於 XcodeProj 的套件整合之生成專案",
  "titleTemplate": ":title · Swift · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "在生成的專案中，將 Tuist Registry 與基於 XcodeProj 的套件整合搭配使用。"
}
---
# 使用 XcodeProj 型套件整合產生的專案 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 型整合</.localized_link> 時，若註冊表中存在相依性，你可以使用 `--replace-scm-with-registry` 旗標從註冊表解析它們。將其加入 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若要確保每次解析相依性時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，改用註冊表識別碼而非 URL。

<!-- @snippet: ./_registry-identifier -->
