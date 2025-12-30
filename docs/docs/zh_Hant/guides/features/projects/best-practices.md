---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# 最佳實踐{#best-practices}

多年來與不同的團隊和專案合作，我們發現了一套最佳實務，建議您在使用 Tuist 和 Xcode
專案時遵循。這些實務並不是強制性的，但它們可以幫助您以更容易維護和擴充的方式來架構專案。

## Xcode{#xcode}

### 沮喪模式{#discouraged-patterns}

#### 模擬遠端環境的配置{#configurations-to-model-remote-environments}

許多組織使用建立組態來模擬不同的遠端環境 (例如`Debug-Production` 或`Release-Canary`)，但這種方法有一些缺點：

- **不一致：** 如果整個圖形中的組態不一致，建立系統可能會為某些目標使用錯誤的組態。
- **複雜性：** 專案最終可能會產生一長串的本機設定和遠端環境，難以推理和維護。

建置配置的設計是為了體現不同的建置設定，專案很少只需要`Debug` 和`Release` 。建模不同環境的需求可以用不同的方式來實現：

- **在偵錯建置中：** 您可以在應用程式中包含開發中應可存取的所有配置
  (例如端點)，並在執行時進行切換。切換可以使用方案啟動環境變數，或是應用程式內的使用者介面。
- **在釋出建置中：** 在釋出的情況下，您只能包含釋出建置綁定的組態，而不能包含使用編譯器指令切換組態的執行時邏輯。

::: info Non-standard configurations
<!-- -->
雖然 Tuist 支援非標準的組態，並使它們比起 vanilla Xcode
專案更容易管理，但如果整個相依圖中的組態不一致，您將會收到警告。這有助於確保建立的可靠性，並防止與組態相關的問題。
<!-- -->
:::

## 專案生成

### 可建立的資料夾

Tuist 4.62.0 新增了對**buildable folders** (Xcode 的同步群組) 的支援，這是 Xcode 16
中為了減少合併衝突而引入的功能。

雖然 Tuist 的通配符模式 (例如`Sources/**/*.swift`) 已經消除了產生專案中的合併衝突，但可建立資料夾提供了額外的好處：

- **自動同步** ：您的專案結構與檔案系統保持同步 - 新增或移除檔案時無需重新生成
- **AI 友好的工作流程** ：編碼助手和代理可以修改您的程式碼庫，而不會觸發專案再生
- **更簡單的配置** ：定義資料夾路徑而非管理明確的檔案清單

我們建議採用可建立資料夾，取代傳統的`Target.sources` 和`Target.resources` 屬性，以獲得更精簡的開發體驗。

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 依賴

#### 在 CI 上強制已解決的版本

在 CI 上安裝 Swift 套件管理員相依性時，我們建議使用`--force-resolved-versions` 旗標，以確保確定性的建置：

```bash
tuist install --force-resolved-versions
```

此旗標可確保使用`Package.resolved` 中的精確版本解決相依性，消除相依性解決的非決定性所導致的問題。這在 CI
上尤其重要，因為可重複的建置是非常重要的。
