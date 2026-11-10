---
{
  "title": "以 XcodeProj 為基礎的套件整合所產生的專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "在產生的專案中，將 Tuist Registry 與以 XcodeProj 為基礎的套件整合搭配使用。"
}
---
# 使用 XcodeProj 型套件整合產生的專案 {#generated-project-with-xcodeproj-based-integration}

使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 型整合</.localized_link> 時，若註冊表中存在相依性，你可以使用 `--replace-scm-with-registry` 旗標從註冊表解析它們。將其加入你的 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

若要確保每次解析相依性時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，改用註冊表識別符而非 URL。

<!-- @snippet: ./_registry-identifier -->
