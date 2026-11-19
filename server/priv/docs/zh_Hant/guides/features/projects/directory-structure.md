---
{
  "title": "目錄結構",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 專案的結構以及如何組織它們。"
}
---
# 目錄結構 {#directory-structure}

雖然 Tuist 專案常用於取代 Xcode 專案，但並不限於此用途。Tuist 專案也可用來產生其他類型的專案，例如 SPM 套件、範本、外掛程式與工作任務。本文件說明 Tuist 專案的結構與組織方式。後續章節將介紹如何定義範本、外掛程式與工作任務。

## 標準 Tuist 專案 {#standard-tuist-projects}

Tuist 專案是**Tuist 最常見的專案類型。** 它們可用來建置應用程式、框架與函式庫等。與 Xcode 專案不同，Tuist 專案以 Swift 定義，因此更具彈性且更易於維護。Tuist 專案也更具宣告性，讓理解與推論更加直觀。以下結構展示一個會產生 Xcode 專案的典型 Tuist 專案：

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

- **Tuist 目錄：** 此目錄有兩個用途。首先，它標示**專案根目錄的位置**。這允許建構相對於專案根目錄的路徑，也能從專案內的任何目錄執行 Tuist 指令。其次，它是下列檔案的容器：
  - **ProjectDescriptionHelpers：** 此目錄包含在所有清單檔案之間共用的 Swift 程式碼。清單檔案可以`import ProjectDescriptionHelpers`以使用此目錄中定義的程式碼。共用程式碼有助於避免重複，並確保各專案之間的一致性。
  - **Package.swift：** 此檔案包含 Swift Package 相依性，供 Tuist 透過可設定與最佳化的 Xcode 專案與目標進行整合（例如[CocoaPods](https://cocoapods.org)）。了解更多<.localized_link href="/guides/features/projects/dependencies">這裡</.localized_link>。

- **根目錄**：你專案的根目錄，其中也包含`Tuist`目錄。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift：</strong></.localized_link>此檔案包含 Tuist 的設定，並在所有專案、工作區與環境之間共用。例如，可用來停用方案的自動產生，或定義專案的部署目標。
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift：</strong></.localized_link>此清單代表一個 Xcode 工作區。它用於將其他專案分組，也可以加入額外的檔案與方案。
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift：</strong></.localized_link>此清單代表一個 Xcode 專案。它用於定義屬於該專案的目標及其相依性。

在與上述專案互動時，指令期望在工作目錄或透過`--path`旗標指定的目錄中找到`Workspace.swift`或`Project.swift`檔案。清單檔案應位於包含`Tuist`目錄的目錄或其子目錄中，該目錄代表專案的根目錄。

> [!TIP]
> Xcode 工作區允許將專案拆分為多個 Xcode 專案，以降低合併衝突的可能性。若你過去使用工作區是為了這個目的，在 Tuist 中則不需要。Tuist 會自動產生一個包含專案及其相依專案的工作區。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist 也支援 SPM 套件專案。若你正在開發 SPM 套件，通常不需要更新任何內容。Tuist 會自動偵測你的根目錄`Package.swift`，且 Tuist 的所有功能都會像處理`Project.swift`清單一樣運作。

若要開始使用，請在你的 SPM 套件中執行`tuist install`與`tuist generate`。你的專案現在應該具備與原生 Xcode SPM 整合相同的所有方案與檔案。此外，你現在還可以執行<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>，讓大多數 SPM 相依性與模組預先編譯，使後續建置極為快速。
