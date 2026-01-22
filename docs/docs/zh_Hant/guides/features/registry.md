---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# 註冊表{#registry}

隨著依賴項數量增加，解析時間亦隨之增長。相較於[CocoaPods](https://cocoapods.org/)或[npm](https://www.npmjs.com/)等集中式套件管理工具，Swift
Package Manager採分散式架構。因此SwiftPM需透過深度複製每個儲存庫來解析依賴關係，此過程不僅耗時，記憶體佔用量亦高於集中式方案。
為解決此問題，Tuist
實作[套件註冊表](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)機制，讓您僅需下載實際需要的提交內容__
。註冊表中的套件皆基於[Swift Package
Index](https://swiftpackageindex.com/)——若該套件存在於該索引，則Tuist註冊表亦提供相同套件。此外，套件透過全球邊緣儲存分佈部署，確保解析時延遲降至最低。

## 用法{#usage}

要設定登錄檔，請在專案目錄中執行以下指令：

```bash
tuist registry setup
```

此指令會產生一個註冊表配置檔案，用於為您的專案啟用註冊表功能。請確保將此檔案提交至版本控制系統，以便團隊成員也能受益於該註冊表。

### 驗證（可選）{#authentication}

驗證為選用功能：**optional** 。未驗證時，可使用註冊表服務，每分鐘限額為**1,000 次請求** 每 IP 位址。若需提升限額至**每分鐘
20,000 次請求** ，請執行以下驗證程序：

```bash
tuist registry login
```

::: info
<!-- -->
驗證需具備 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
帳戶及專案</LocalizedLink>。
<!-- -->
:::

### 解決依賴關係{#resolving-dependencies}

若需從登錄檔而非原始碼控制系統解決依賴關係，請根據專案設定繼續閱讀：
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode
  專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">已生成整合 Xcode
  套件的專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">透過基於
  XcodeProj 的套件整合所產生的專案</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift
  套件</LocalizedLink>

要於持續整合環境設定登錄檔，請參照此指南：<LocalizedLink href="/guides/features/registry/continuous-integration">持續整合</LocalizedLink>。

### 套件註冊表識別碼{#package-registry-identifiers}

當您在`Package.swift` 或`Project.swift` 檔案中使用套件註冊表識別碼時，需將套件網址轉換為註冊表規範格式。
註冊表識別碼始終採用以下格式：`{組織}.{儲存庫}`
。例如，若要使用`https://github.com/pointfreeco/swift-composable-architecture`
套件的註冊表，其識別碼應為`pointfreeco.swift-composable-architecture` 。

::: info
<!-- -->
識別碼不得包含超過一個句點。若儲存庫名稱含句點，則以底線取代。例如：`https://github.com/groue/GRDB.swift`
套件的註冊識別碼為`groue.GRDB_swift` 。
<!-- -->
:::
