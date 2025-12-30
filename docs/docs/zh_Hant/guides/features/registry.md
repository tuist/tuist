---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# 註冊{#registry}

隨著相依性數量的增加，解決這些相依性的時間也隨之增加。其他套件管理員，例如 [CocoaPods](https://cocoapods.org/) 或
[npm](https://www.npmjs.com/) 都是集中式的，但 Swift Package Manager 並非如此。因此，SwiftPM
需要透過深入克隆每個套件庫來解決依賴關係，這可能會比集中式的方式更費時，也會佔用更多記憶體。為了解決這個問題，Tuist 提供了 [Package
Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)
的實作，因此您可以只下載_實際需要的提交_ 。註冊表中的套件基於 [Swift 套件索引](https://swiftpackageindex.com/)。-
如果您能在那裡找到套件，該套件也可以在 Tuist Registry
中找到。此外，這些套件使用邊緣儲存區分佈在全球各地，以便在解析這些套件時將延遲時間降至最低。

## 使用方式{#usage}

要設定註冊表，請在專案目錄中執行下列指令：

```bash
tuist registry setup
```

此指令會產生一個註冊表組態檔，為您的專案啟用註冊表。確保已提交此檔案，以便您的團隊也能受惠於註冊表。

### 驗證（可選）{#authentication}

**** 身份驗證是可選的。在沒有認證的情況下，您可以使用註冊表，速率限制為**，每個 IP 位址每分鐘 1,000 次請求**
。要獲得更高的速率限制**每分鐘 20,000 次請求** ，您可以執行驗證：

```bash
tuist registry login
```

::: info
<!-- -->
驗證需要 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 帳戶和專案</LocalizedLink>。
<!-- -->
:::

### 解決依賴性{#resolving-dependencies}

若要從登錄而非原始碼控制解決相依性問題，請根據您的專案設定繼續閱讀：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode 專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">使用 Xcode 套件整合產生專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">使用基於 XcodeProj 的套件整合產生專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">快速套裝</LocalizedLink>

若要在 CI
上設定註冊表，請遵循此指南：<LocalizedLink href="/guides/features/registry/continuous-integration">Continuous integration</LocalizedLink>.

### 套件登錄識別碼{#package-registry-identifiers}

當您在`Package.swift` 或`Project.swift` 檔案中使用套件註冊表識別符時，您需要將套件的 URL
轉換為註冊表慣例。註冊表識別符的形式總是`{organization}.{repository}`
。例如，若要使用`https://github.com/pointfreeco/swift-composable-architecture`
套件的註冊表，套件註冊表識別符應為`pointfreeco.swift-composable-architecture` 。

::: info
<!-- -->
識別符不能包含多於一個點。如果儲存庫名稱包含一個點，就會用下劃線取代。例如，`https://github.com/groue/GRDB.swift`
套件的註冊表標識符為`groue.GRDB_swift` 。
<!-- -->
:::
