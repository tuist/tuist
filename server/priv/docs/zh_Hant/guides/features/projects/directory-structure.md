---
{
  "title": "目錄結構",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 專案的結構以及如何組織它們。"
}
---
# 目錄結構 {#directory-structure}

雖然 Tuist 專案常用於取代 Xcode 專案，但其用途不限於此。Tuist 專案也可用於產生其他類型的專案，例如 SPM 套件、範本、外掛程式和任務。本文件說明 Tuist 專案的結構及其組織方式。在後續章節中，我們將介紹如何定義範本、外掛程式和任務。

## 標準 Tuist 專案 {#standard-tuist-projects}

Tuist 專案是 **Tuist 所產生最常見的專案類型。** 它們用於建置應用程式、框架和函式庫等。與 Xcode 專案不同，Tuist 專案以 Swift 定義，這使其更具彈性且更易於維護。Tuist 專案也更具宣告性，讓開發者更容易理解與推論。以下結構顯示一個典型的 Tuist 專案，它會產生一個 Xcode 專案：

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

- **Tuist 目錄：** 此目錄有兩個用途。首先，它標示 **專案根目錄的位置**。這允許建構相對於專案根目錄的路徑，並從專案內的任何目錄執行 Tuist 指令。其次，它是下列檔案的容器：
  - **ProjectDescriptionHelpers：** 此目錄包含在所有 manifest 檔案之間共用的 Swift 程式碼。Manifest 檔案可以 `import ProjectDescriptionHelpers` 以使用在此目錄中定義的程式碼。共用程式碼有助於避免重複並確保專案間的一致性。
  - **Package.swift：** 此檔案包含 Swift Package 相依性，供 Tuist 透過可設定且可優化的 Xcode 專案和 target（例如 [CocoaPods](https://cococapods)）進行整合。了解更多 <.localized_link href="/guides/features/projects/dependencies">這裡</.localized_link>。

- **根目錄**：專案的根目錄，其中也包含 `Tuist` 目錄。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift：</bold></.localized_link> 此檔案包含 Tuist 的設定，這些設定在所有專案、工作區和環境之間共用。例如，可用於停用 scheme 的自動產生，或定義專案的部署目標。
  - <.localized_link href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift：</bold></.localized_link> 此 manifest 代表一個 Xcode 工作區。它用於將其他專案分組，也可以新增額外的檔案和 scheme。
  - <.localized_link href="/guides/features/projects/manifests#project-swift"><bold>Project.swift：</bold></.localized_link> 此 manifest 代表一個 Xcode 專案。它用於定義屬於該專案的 target 及其相依性。

當與上述專案互動時，指令期望在工作目錄或透過 `--path` 旗標指定的目錄中找到 `Workspace.swift` 或 `Project.swift` 檔案。Manifest 應位於包含 `Tuist` 目錄的目錄或其子目錄中，該目錄代表專案的根目錄。

> [!TIP]
> Xcode 工作區允許將專案拆分為多個 Xcode 專案，以降低合併衝突的可能性。若你過去使用工作區是為了此目的，在 Tuist 中則不需要它們。Tuist 會自動產生一個包含專案及其相依專案的工作區。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist 也支援 SPM 套件專案。若你正在處理 SPM 套件，通常無需更新任何內容。Tuist 會自動偵測你的根目錄 `Package.swift`，且所有 Tuist 功能都會像處理 `Project.swift` manifest 一樣運作。

若要開始使用，請在你的 SPM 套件中執行 `tuist install` 和 `tuist generate`。你的專案現在應具備與原生 Xcode SPM 整合中相同的 scheme 和檔案。此外，你現在還可以執行 <.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>，讓大多數 SPM 相依性和模組預先編譯，使後續建置極為快速。
