---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# 目錄結構{#directory-structure}

雖然 Tuist 專案通常用來取代 Xcode 專案，但它們並不限於此使用情況。Tuist 專案也可用於產生其他類型的專案，例如 SPM
套件、範本、外掛程式和任務。本文件將說明 Tuist 專案的結構以及如何組織專案。在稍後的章節中，我們將介紹如何定義模板、外掛程式和任務。

## 標準 Tuist 專案{#standard-tuist-projects}

Tuist 專案是**由 Tuist 產生的最常見的專案類型。** 它們可用於建立應用程式、框架和函式庫等。與 Xcode 專案不同，Tuist 專案是以
Swift 定義，這使得它們更靈活、更容易維護。Tuist 專案也更具宣告性，使其更容易理解和推理。以下結構顯示了一個典型的 Tuist 專案，它會產生一個
Xcode 專案：

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Tuist 目錄：** 此目錄有兩個目的。首先，它顯示**專案的根目錄在** 。這樣就可以建構相對於專案根目錄的路徑，也可以從專案中的任何目錄執行
  Tuist 指令。第二，它是下列檔案的容器：
  - **ProjectDescriptionHelpers：** 此目錄包含所有清單檔案共用的 Swift 程式碼。Manifest 檔案可以`import
    ProjectDescriptionHelpers` 來使用此目錄定義的程式碼。共用程式碼有助於避免重複，並確保各專案間的一致性。
  - **Package.swift：** 此檔案包含 Swift 套件的相依性，供 Tuist 使用 Xcode 專案與目標 (如
    [CocoaPods](https://cococapods))進行整合，這些專案與目標是可設定與最佳化的。瞭解更多資訊<LocalizedLink href="/guides/features/projects/dependencies"> 這裡</LocalizedLink>。

- **根目錄** ：您專案的根目錄，其中也包含`Tuist` 目錄。
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>此檔案包含
    Tuist 的設定，可在所有專案、工作區和環境中共用。例如，它可用於停用自動產生方案，或定義專案的部署目標。
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>此清單代表
    Xcode 工作區。它用於將其他專案分組，也可以新增額外的檔案和方案。
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>此清單代表一個
    Xcode 專案。它用於定義作為專案一部分的目標及其相依性。

與上述專案互動時，指令希望在工作目錄或透過`--path` 旗標指示的目錄中找到`Workspace.swift` 或`Project.swift`
檔案。manifest應該在包含`Tuist` 目錄的目錄或子目錄中，該目錄代表專案的根目錄。

::: tip
<!-- -->
Xcode 工作區允許將專案分割成多個 Xcode 專案，以減少合併衝突的可能性。如果這就是您使用工作區的目的，您在 Tuist 中就不需要它們了。Tuist
自動產生一個工作區，包含一個專案及其依賴的專案。
<!-- -->
:::

## Swift 套件 <Badge type="warning" text="beta" />{#swift-package-badge-typewarning-textbeta-}

Tuist 也支援 SPM 套件專案。如果您正在處理 SPM 套件，應該不需要更新任何東西。Tuist 會自動接收您的根`Package.swift`
，Tuist 的所有功能都會像`Project.swift` 的清單一樣運作。

要開始使用，請在您的 SPM 套件中執行`tuist install` 和`tuist generate` 。現在，您的專案應該擁有所有與您在 vanilla
Xcode SPM 整合中看到的相同方案與檔案。不過，現在您也可以執行
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>
並預先編譯大部分的 SPM 依賴項目與模組，讓後續的建置速度極快。
