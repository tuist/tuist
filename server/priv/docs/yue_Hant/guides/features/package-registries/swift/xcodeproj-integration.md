---
{
  "title": "使用基於 XcodeProj 的套件整合生成專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "在生成的專案中，將 Tuist Registry 與基於 XcodeProj 的套件整合搭配使用。"
}
---
# 使用 XcodeProj 套件整合的生成專案 {#generated-project-with-xcodeproj-based-integration}

當使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-based integration</.localized_link> 時，如果註冊表中有可用的依賴項，你可以使用 `--replace-scm-with-registry` 標誌從註冊表解析它們。將其添加到你的 `Tuist.swift` 檔案中的 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你想確保每次解析依賴項時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中的 `dependencies`，以使用註冊表識別符而不是 URL。

<!-- @snippet: ./_registry-identifier -->
