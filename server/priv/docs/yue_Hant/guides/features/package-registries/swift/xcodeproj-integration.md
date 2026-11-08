---
{
  "title": "以 XcodeProj 為基礎嘅套件整合生成專案",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "喺生成專案入面，將 Tuist Registry 同以 XcodeProj 為基礎嘅套件整合一齊使用。"
}
---
# 使用 XcodeProj 基礎套件整合生成專案 {#generated-project-with-xcodeproj-based-integration}

當使用 <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj 基礎整合</.localized_link> 時，你可以使用 `--replace-scm-with-registry` 旗標從 Registry 解析依賴項（如果可用）。將它加入到你 `Tuist.swift` 檔案中嘅 `installOptions`：
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

如果你想確保每次解析依賴項時都使用 Registry，你需要更新 `Tuist/Package.swift` 檔案中嘅 `dependencies`，改用 Registry 識別符而非 URL。

<!-- @snippet: ./_registry-identifier -->
