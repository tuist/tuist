---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# 登錄檔{#registry}

隨著依賴項數量增加，解析所需的時間也會隨之增加。雖然其他套件管理工具如 [CocoaPods](https://cocoapods.org/) 或
[npm](https://www.npmjs.com/) 採集中式架構，但 Swift Package Manager 並非如此。正因如此，SwiftPM
必須透過深度複製每個儲存庫來解析依賴項，這不僅耗時，所佔用的記憶體也比集中式方法更多。 為解決此問題，Tuist 提供了一種
[套件註冊表](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)
的實作，讓您只需下載_實際需要的提交_ 。註冊表中的套件基於 [Swift Package
Index](https://swiftpackageindex.com/) —— 若您能在該處找到某個套件，則該套件在 Tuist
註冊表中亦可取得。此外，這些套件透過邊緣儲存分佈於全球各地，以確保解析時的延遲降至最低。

## 用法{#usage}

要設定登錄檔，請在專案目錄中執行以下指令：

```bash
tuist registry setup
```

此指令會產生一個註冊表設定檔，用以啟用您專案的註冊表。請務必將此檔案提交至版本控制系統，以便您的團隊也能使用該註冊表。

### 驗證（可選）{#authentication}

驗證是可選的**** 。若未進行驗證，您可使用此註冊表，但每 IP 位址的請求速率上限為**每分鐘 1,000 次** 。若要獲得更高的速率上限**每分鐘
20,000 次** ，您可以執行以下指令進行驗證：

```bash
tuist registry login
```

::: info
<!-- -->
驗證需要 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
帳戶和專案</LocalizedLink>。
<!-- -->
:::

### 解決依賴關係{#resolving-dependencies}

若要從登錄檔而非版本控制系統解決依賴關係，請根據您的專案設定繼續閱讀：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">已透過 Xcode
  套件整合生成的專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">使用基於
  XcodeProj 的套件整合所生成的專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift
  套件</LocalizedLink>

若要在 CI
上設定登錄檔，請參閱此指南：<LocalizedLink href="/guides/features/registry/continuous-integration">持續整合</LocalizedLink>。

### 套件登錄識別碼{#package-registry-identifiers}

當您在`Package.swift` 或`Project.swift` 檔案中使用套件註冊表識別碼時，需將套件的 URL 轉換為註冊表規範格式。
套件註冊表識別碼始終採用`{organization}.{repository}`
的格式。例如，若要使用`https://github.com/pointfreeco/swift-composable-architecture`
套件的註冊表，其套件註冊表識別碼即為`pointfreeco.swift-composable-architecture` 。

::: info
<!-- -->
識別碼中不得包含多個點。若儲存庫名稱包含點，則會被替換為底線。例如，`https://github.com/groue/GRDB.swift`
套件的註冊識別碼將為`groue.GRDB_swift` 。
<!-- -->
:::
