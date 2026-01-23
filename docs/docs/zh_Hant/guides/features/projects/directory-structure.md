---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# 目錄結構{#directory-structure}

雖然 Tuist 專案通常用於取代 Xcode 專案，但其用途不限於此。Tuist 專案亦可生成其他類型專案，例如 SPM
套件、範本、外掛程式及任務。本文檔說明 Tuist 專案的結構與組織方式，後續章節將探討如何定義範本、外掛程式及任務。

## 標準 Tuist 專案{#standard-tuist-projects}

Tuist 專案是**Tuist 生成的最常見專案類型。** 它們用於構建應用程式、框架、函式庫等。與 Xcode 專案不同，Tuist 專案以 Swift
定義，使其更具靈活性且易於維護。Tuist 專案也更具聲明性，因此更易於理解和分析。以下結構展示一個典型的 Tuist 專案，該專案會生成 Xcode 專案：

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

- **Tuist 目錄：** 此目錄具雙重用途：首先，它向**標示專案根目錄** 的位置，使系統能建立相對於專案根目錄的路徑，並允許從專案內任何目錄執行
  Tuist 指令；其次，此目錄用於存放下列檔案：
  - **ProjectDescriptionHelpers:** 此目錄存放所有清單檔案共用的 Swift 程式碼。清單檔案可透過 ``` 導入
    `ProjectDescriptionHelpers` 模組（參見 ``
    `），以使用此目錄定義的程式碼。共享程式碼有助避免重複編寫，並確保專案間的一致性。
  - **Package.swift：** 此檔案包含 Tuist 的 Swift Package 依賴項，用於透過 Xcode 專案與目標（如
    [CocoaPods](https://cococapods)）進行整合，具備可配置與可優化特性。<LocalizedLink href="/guides/features/projects/dependencies">更多資訊請參閱</LocalizedLink>此處。

- **根目錄** ：專案根目錄，此處亦包含`Tuist` 目錄。
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    此檔案包含 Tuist 的全域設定，適用於所有專案、工作區及環境。例如可用於停用方案自動生成功能，或定義專案的部署目標。
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    此清單代表一個 Xcode 工作區。用於群組其他專案，亦可新增額外檔案與方案。
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    此清單代表一個 Xcode 專案。用於定義專案所包含的目標及其依賴關係。

與上述專案互動時，指令預期在工作目錄或透過`--path` 標記指定的目錄中，找到以下任一檔案：`Workspace.swift`
或`Project.swift` 清單檔案應位於包含`Tuist` 目錄的目錄或子目錄中，該目錄代表專案根目錄。

::: tip
<!-- -->
Xcode 工作區功能可將專案分割為多個 Xcode 專案，以降低合併衝突機率。若您原先使用工作區正是為此目的，則在 Tuist 中無需此功能。Tuist
會自動生成包含主專案及其依賴專案的工作區。
<!-- -->
:::

## Swift Package <Badge type="warning" text="beta" />{#swift-package-badge-typewarning-textbeta-}

Tuist 同時支援 SPM 套件專案。若您正在開發 SPM 套件，無需進行任何更新。Tuist 會自動識別您的根目錄`Package.swift` ，並使所有
Tuist 功能如同處理`Project.swift` 專案清單般運作。

開始前請於您的 SPM 套件中執行：`tuist install` 以及`tuist generate` 此時您的專案應具備與原生 Xcode SPM
整合相同的架構與檔案。此外，您現在還能執行 <LocalizedLink href="/guides/features/cache">`tuist
cache`</LocalizedLink>，預先編譯多數 SPM 依賴項與模組，大幅提升後續建置速度。
