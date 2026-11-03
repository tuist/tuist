---
{
  "title": "Swift",
  "titleTemplate": ":title · 套件註冊表 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Swift 套件註冊表，將 Swift Package Manager 的解析時間從數分鐘縮短至數秒，並由 Tuist 的全球快取網路提供支援。"
}
---
# Swift Package Registry {#swift-package-registry}

隨著相依性數量增加，解析它們所需的時間也會變長。雖然 [CocoaPods](https://cocoapods.org/) 或 [npm](https://www.npmjs.com/) 等其他套件管理器採用集中式架構，但 Swift Package Manager 並非如此。因此，SwiftPM 需要透過深度克隆每個儲存庫來解析相依性，這不僅耗時，也比集中式方法佔用更多記憶體。為了解決這個問題，Tuist 提供了 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 的實作，讓你只下載你 _真正需要_ 的提交記錄。Registry 中的套件基於 [Swift Package Index](https://swiftpackageindex.com/)；只要能在該索引中找到套件，該套件也可在 Tuist Registry 中使用。此外，這些套件透過邊緣儲存分散在全球各地，以在解析時將延遲降至最低。

## 用法 {#usage}

設定 Registry 有兩種方式：

### 選項 1：在建置期間自動設定（建議） {#automatic-setup}

如果你使用 Tuist 來產生專案，可以透過在 `Tuist.swift` 組態中設定 `registryEnabled` 選項來啟用 Registry：

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

使用此選項時，`tuist generate` 會自動在你的工作區中建立 Registry 組態檔案。這樣就不需要單獨執行 `tuist registry setup`。

> [!TIP]
> `registryEnabled` 也會為透過 Xcode 預設 Swift Package Manager 整合（而非 Tuist 基於 XcodeProj 的整合）來整合相依性的專案設定 Registry。它不會設定 Xcode 從 Registry 解析以原始碼控制 URL 宣告的套件。若要這麼做，請依照 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link> 中的說明，在每台機器上執行一次 `tuist registry setup`。


### 選項 2：手動設定 {#manual-setup}

若要手動設定 Registry，請在專案目錄中執行以下指令：

```bash
tuist registry setup
```

此指令會產生一個啟用專案 Registry 的組態檔案。請確保提交此檔案，讓你的團隊也能受惠於 Registry。

### 驗證（選用） {#authentication}

驗證是 **選用** 的。未經驗證時，你可以使用 Registry，每個 IP 位址的速率限制為 **每分鐘 1,000 次請求**。若要取得較高的速率限制 **每分鐘 20,000 次請求**，可以透過執行以下指令進行驗證：

```bash
tuist registry login
```

> [!NOTE]
> 驗證需要 <.localized_link href="/guides/server/accounts-and-projects">Tuist 帳號與專案</.localized_link>。


### 解析相依性 {#resolving-dependencies}

若要從 Registry 而非原始碼控制解析相依性，請根據你的專案設定繼續閱讀：
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

若要在 CI 上設定 Registry，請參閱此指南：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">持續整合</.localized_link>。

### 套件 Registry 識別碼 {#package-registry-identifiers}

當你在 `Package.swift` 或 `Project.swift` 檔案中使用套件 Registry 識別碼時，需要將套件的 URL 轉換為 Registry 慣例。Registry 識別碼一律採用 `{organization}.{repository}` 格式。例如，若要對 `https://github.com/pointfreeco/swift-composable-architecture` 套件使用 Registry，其套件 Registry 識別碼將為 `pointfreeco.swift-composable-architecture`。

> [!NOTE]
> 識別碼不能包含超過一個點。如果儲存庫名稱包含點，則會替換為底線。例如，`https://github.com/groue/GRDB.swift` 套件的 Registry 識別碼將為 `groue.GRDB_swift`。
