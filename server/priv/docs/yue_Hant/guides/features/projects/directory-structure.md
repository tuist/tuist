---
{
  "title": "目錄結構",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 專案的結構以及如何組織它們。"
}
---
# 目錄結構 {#directory-structure}

雖然 Tuist 專案常用於取代 Xcode 專案，但並不限於此用途。Tuist 專案亦可用於產生其他類型的專案，例如 SPM 套件、範本、外掛和任務。本文說明 Tuist 專案的結構以及如何組織它們。在後續章節中，我們會介紹如何定義範本、外掛和任務。

## 標準 Tuist 專案 {#standard-tuist-projects}

Tuist 專案是**Tuist 產生的最常見專案類型。** 它們用於建構應用程式、框架和程式庫等。與 Xcode 專案不同，Tuist 專案以 Swift 定義，因此更具彈性且更易於維護。Tuist 專案也更具宣告性，令其更易於理解和分析。以下結構顯示一個會產生 Xcode 專案的典型 Tuist 專案：

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

- **Tuist 目錄：** 此目錄有兩個用途。首先，它標示**專案根目錄的位置**。這允許建構相對於專案根目錄的路徑，並可從專案內的任何目錄執行 Tuist 指令。其次，它是下列檔案的容器：
  - **ProjectDescriptionHelpers：** 此目錄包含在所有資訊清單檔案之間共用的 Swift 程式碼。資訊清單檔案可以`import ProjectDescriptionHelpers`以使用在此目錄中定義的程式碼。共用程式碼有助於避免重複並確保專案之間的一致性。
  - **Package.swift：** 此檔案包含 Swift Package 依賴項，讓 Tuist 能夠透過可設定和最佳化的 Xcode 專案和目標（例如[CocoaPods](https://cocoapods.org)）將它們整合。了解更多<.localized_link href="/guides/features/projects/dependencies">這裡</.localized_link>。

- **根目錄**：你專案的根目錄，同時包含`Tuist`目錄。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift：</strong></.localized_link>此檔案包含適用於所有專案、工作區和環境的 Tuist 設定。例如，它可用於停用方案的自動產生，或定義專案的部署目標。
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift：</strong></.localized_link>此資訊清單代表一個 Xcode 工作區。它用於將其他專案分組，亦可加入額外的檔案和方案。
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift：</strong></.localized_link>此資訊清單代表一個 Xcode 專案。它用於定義屬於該專案的目標及其依賴項。

與上述專案互動時，指令期望在工作目錄或透過`--path`旗標指定的目錄中找到`Workspace.swift`或`Project.swift`檔案。資訊清單應位於包含`Tuist`目錄的目錄或其子目錄中，該目錄代表專案的根目錄。

> [!TIP]
> Xcode 工作區允許將專案拆分為多個 Xcode 專案，以降低合併衝突的可能性。如果你過去使用工作區是為了這個目的，那麼在 Tuist 中你不需要它們。Tuist 會自動產生一個包含專案及其依賴項專案的工作區。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist 亦支援 SPM 套件專案。如果你正在處理 SPM 套件，應該無需更新任何內容。Tuist 會自動偵測你的根目錄`Package.swift`，而且所有 Tuist 功能都會像它是`Project.swift`資訊清單一樣運作。

要開始使用，請在你的 SPM 套件中執行`tuist install`和`tuist generate`。你的專案現在應該具備與原生 Xcode SPM 整合中相同的所有方案和檔案。不過，現在你也可以執行<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>，並將大多數 SPM 依賴項和模組預先編譯，令後續建構極快。
