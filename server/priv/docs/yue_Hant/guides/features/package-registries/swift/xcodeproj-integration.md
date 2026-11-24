---
{
  "title": "使用 XcodeProj 套件整合的生成專案",
  "titleTemplate": ":title · Swift · Package Registries · 功能 · 指南 · Tuist",
  "description": "在生成的專案中，將 Tuist Registry 與基於 XcodeProj 的套件整合搭配使用。"
}
---
# 使用 XcodeProj 基礎套件整合生成專案 {#generated-project-with-xcodeproj-based-integration}

當使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 基礎整合</.localized_link> 時，如果註冊表中有可用嘅依賴項，你可以使用 `--replace-scm-with-registry` 標誌從註冊表解析依賴項。將佢加入到你 `Tuist.swift` 檔案中嘅 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你想確保每次解析依賴項時都使用註冊表，你需要更新 `Tuist/Package.swift` 檔案中嘅 `dependencies`，以使用註冊表識別符代替 URL。

<!-- @snippet: ./_registry-identifier -->
