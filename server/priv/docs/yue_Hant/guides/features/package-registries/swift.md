---
{
  "title": "Swift",
  "titleTemplate": ":title · Package Registries · Features · Guides · Tuist",
  "description": "透過 Tuist Swift 套件註冊表，將 Swift Package Manager 的解析時間由數分鐘縮短至數秒，背後由 Tuist 的全球快取網絡支援。"
}
---
# Swift Package Registry {#swift-package-registry}

隨著依賴項目增多，解析它們所需的時間亦會增加。雖然其他套件管理器（例如 [CocoaPods](https://cocoapods.org/) 或 [npm](https://www.npmjs.com/)）採用集中式架構，但 Swift Package Manager 並非如此。因此，SwiftPM 需要透過深度克隆每個儲存庫來解析依賴，這不僅耗時，而且比起集中式方法會佔用更多記憶體。為了解決這個問題，Tuist 提供 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 的實作，讓你可以只下載你 _真正需要_ 的提交記錄。註冊表中的套件基於 [Swift Package Index](https://swiftpackageindex.com/) —— 只要你能在那裡找到某個套件，該套件亦可在 Tuist Registry 中使用。此外，這些套件透過邊緣儲存分發至全球，以在解析時將延遲降至最低。

## 使用方法 {#usage}

有兩種方式可以設定註冊表：

### 選項 1：在建置產生期間自動設定（推薦）{#automatic-setup}

如果你使用 Tuist 來產生專案，可以透過在 `Tuist.swift` 設定中設定 `registryEnabled` 選項來啟用註冊表：

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

啟用此選項後，`tuist generate` 會自動在你的工作區中建立註冊表設定檔案。這樣就無須另行執行 `tuist registry setup`。

> [!TIP]
> `registryEnabled` 亦會為那些透過 Xcode 預設 Swift Package Manager 整合（而非 Tuist 基於 XcodeProj 的整合）來整合依賴的專案設定註冊表。它不會設定 Xcode 從註冊表解析以原始碼控制 URL 宣告的套件。如需執行此操作，請按照 <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">解析原始碼控制套件</.localized_link> 中的說明，在每台機器上執行一次 `tuist registry setup`。


### 選項 2：手動設定 {#manual-setup}

若要手動設定註冊表，請在專案目錄中執行以下指令：

```bash
tuist registry setup
```

此指令會產生一個註冊表設定檔案，為你的專案啟用註冊表。請確保提交此檔案，讓你的團隊成員也能受惠於註冊表。

### 驗證（可選）{#authentication}

驗證是**可選**的。未進行驗證時，你可以使用註冊表，每個 IP 位址的速率限制為每分鐘 **1,000 個請求**。若要獲得更高的速率限制（每分鐘 **20,000 個請求**），你可以執行以下指令進行驗證：

```bash
tuist registry login
```

> [!NOTE]
> 驗證需要擁有 <.localized_link href="/guides/server/accounts-and-projects">Tuist 帳戶和專案</.localized_link>。


### 解析依賴 {#resolving-dependencies}

若要從註冊表而非原始碼控制解析依賴，請根據你的專案設定繼續閱讀：
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

若要在 CI 上設定註冊表，請參閱此指南：<.localized_link href="/guides/features/package-registries/swift/continuous-integration">持續整合</.localized_link>。

### 套件註冊表識別符 {#package-registry-identifiers}

當你在 `Package.swift` 或 `Project.swift` 檔案中使用套件註冊表識別符時，你需要將套件的 URL 轉換為註冊表慣例格式。註冊表識別符一律採用 `{organization}.{repository}` 的形式。例如，若要為 `https://github.com/pointfreeco/swift-composable-architecture` 套件使用註冊表，其套件註冊表識別符將為 `pointfreeco.swift-composable-architecture`。

> [!NOTE]
> 識別符不能包含超過一個句點。如果儲存庫名稱包含句點，則會替換為底線。例如，`https://github.com/groue/GRDB.swift` 套件的註冊表識別符將為 `groue.GRDB_swift`。
