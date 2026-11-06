---
{
  "title": "Swift",
  "titleTemplate": ":title · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "透過由 Tuist 全球快取網絡支援嘅 Tuist Swift 套件註冊表，將 Swift Package Manager 解析時間由幾分鐘縮短至幾秒。"
}
---
# Swift Package Registry {#swift-package-registry}

隨著依賴項數量增加，解析它們所需的時間也會增長。雖然其他套件管理器如 [CocoaPods](https://cocoapods.org/) 或 [npm](https://www.npmjs.com/) 採用集中式架構，但 Swift Package Manager 並非如此。因此，SwiftPM 需要透過深度克隆每個儲存庫來解析依賴項，這不僅耗時，而且比集中式方法佔用更多記憶體。為了解決這個問題，Tuist 提供了 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 的實作，讓你可以只下載你 _真正需要_ 的提交記錄。Registry 中的套件基於 [Swift Package Index](https://swiftpackageindex.com/) —— 如果你在那裡能找到某個套件，該套件也會在 Tuist Registry 中提供。此外，這些套件透過邊緣儲存分發至全球，以在解析時實現最低延遲。

## 使用方法 {#usage}

有兩種方式可以設定 Registry：

### 選項 1：在生成期間自動設定（推薦） {#automatic-setup}

如果你使用 Tuist 來生成專案，可以透過在 `Tuist.swift` 設定中設定 `registryEnabled` 選項來啟用 Registry：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

使用此選項後，`tuist generate` 會自動在你的工作區中建立 Registry 設定檔。這樣就無需單獨執行 `tuist registry setup`。

> [!TIP]
> `registryEnabled` 也會為那些透過 Xcode 預設 Swift Package Manager 整合（而非 Tuist 基於 XcodeProj 的整合）來整合依賴項的專案設定 Registry。它不會設定 Xcode 從 Registry 解析以原始碼控制 URL 聲明的套件。若要這樣做，請依照 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link> 中的說明，在每台機器上執行一次 `tuist registry setup`。


### 選項 2：手動設定 {#manual-setup}

若要手動設定 Registry，請在專案目錄中執行以下命令：

```bash
tuist registry setup
```

此命令會生成一個啟用專案 Registry 的設定檔。請確保提交此檔案，以便你的團隊也能受惠於 Registry。

### 驗證（可選） {#authentication}

驗證是 **可選的**。如果不進行驗證，你可以使用 Registry，每個 IP 位址的限制為每分鐘 **1,000 次請求**。若要獲得每分鐘 **20,000 次請求** 的更高限制，你可以透過執行以下命令進行驗證：

```bash
tuist registry login
```

> [!NOTE]
> 驗證需要一個 <.localized_link href="/guides/server/accounts-and-projects">Tuist 帳戶和專案</.localized_link>。


### 解析依賴項 {#resolving-dependencies}

若要從 Registry 而非原始碼控制解析依賴項，請根據你的專案設定繼續閱讀：
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

若要在 CI 上設定 Registry，請遵循此指南：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">持續整合</.localized_link>。

### 套件 Registry 識別符 {#package-registry-identifiers}

當你在 `Package.swift` 或 `Project.swift` 檔案中使用套件 Registry 識別符時，你需要將套件的 URL 轉換為 Registry 慣例格式。Registry 識別符始終採用 `{organization}.{repository}` 的形式。例如，若要為 `https://github.com/pointfreeco/swift-composable-architecture` 套件使用 Registry，其套件 Registry 識別符將為 `pointfreeco.swift-composable-architecture`。

> [!NOTE]
> 識別符不能包含超過一個點號。如果儲存庫名稱包含點號，則會替換為底線。例如，`https://github.com/groue/GRDB.swift` 套件的 Registry 識別符將為 `groue.GRDB_swift`。
