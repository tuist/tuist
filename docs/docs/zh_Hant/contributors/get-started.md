---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# 開始{#get-started}

如果您有為 Apple 平台 (如 iOS) 建立應用程式的經驗，那麼為 Tuist 加入程式碼應該沒有太大的不同。與開發應用程式相比，有兩點差異值得一提：

- **與 CLI 的互動是透過終端機進行的。** 使用者執行 Tuist，Tuist
  會執行所需的任務，然後成功或以狀態代碼返回。在執行過程中，使用者可以透過向標準輸出和標準錯誤傳送輸出資訊來獲得通知。沒有手勢或圖形互動，只有使用者的意圖。

- **沒有 runloop 讓進程持續等待輸入** ，就像 iOS 應用程式收到系統或使用者事件時會發生的情況一樣。CLI
  在其流程中執行，並在工作完成後結束。異步工作可以使用
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  或 [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)
  等系統 API 來完成，但需要確保在執行異步工作時，進程仍在執行。否則，進程會終止異步工作。

如果您沒有使用 Swift 的經驗，我們建議您參考 [Apple 官方書籍](https://docs.swift.org/swift-book/)，以熟悉
Swift 語言和基金會 API 中最常用的元素。

## 最低要求{#minimum-requirements}

要向 Tuist 捐款，最低要求是：

- macOS 14.0+
- Xcode 16.3+

## 在本機設定專案{#set-up-the-project-locally}

要開始進行專案工作，我們可以遵循以下步驟：

- 執行下列步驟複製套件庫：`git clone git@github.com:tuist/tuist.git`
- [Install](https://mise.jdx.dev/getting-started.html)Mise 以提供開發環境。
- 執行`mise install` 以安裝 Tuist 所需的系統相依性
- 執行`tuist install` 以安裝 Tuist 所需的外部相依性
- (可選）執行`tuist auth login` 以取得
  <LocalizedLink href="/guides/features/cache">Tuist Cache 的存取權限</LocalizedLink>
- 執行`tuist generate` 以使用 Tuist 本身產生 Tuist Xcode 專案

**生成的專案會自動打開** 。如果您需要在未產生的情況下再次開啟，請執行`開啟 Tuist.xcworkspace` (或使用 Finder)。

::: info XED .
<!-- -->
如果您嘗試使用`xed .` 開啟專案，它會開啟套件，而不是 Tuist 產生的專案。我們建議使用 Tuist 產生的專案來狗啃工具。
<!-- -->
:::

## 編輯專案{#edit-the-project}

如果需要編輯專案，例如新增相依性或調整目標，可以使用
<LocalizedLink href="/guides/features/projects/editing">`tuist edit` 指令</LocalizedLink>。這個功能幾乎用不到，但知道它的存在是件好事。

## 運行圖斯特{#run-tuist}

### 從 Xcode{#from-xcode}

若要從產生的 Xcode 專案執行`tuist` ，請編輯`tuist` 方案，並設定您要傳給命令的參數。例如，若要執行`tuist generate`
指令，您可以將參數設定為`generate --no-open` ，以防止專案在產生後打開。

![使用 Tuist 執行 generate 指令的方案設定範例](/images/contributors/scheme-arguments.png)。

您還必須設定工作目錄為所產生專案的根目錄。您可以使用所有指令都接受的`--path` 參數，或是在方案中設定工作目錄，如下所示：


![如何設定執行 Tuist 的工作目錄的範例](/images/contributors/scheme-working-directory.png)。

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
`tuist` CLI 取決於`ProjectDescription` 框架是否存在於建立的產品目錄中。如果`tuist`
因為找不到`ProjectDescription` 框架而無法執行，請先建立`Tuist-Workspace` 方案。
<!-- -->
:::

### 從終端{#from-the-terminal}

您可以使用 Tuist 本身透過`run` 指令執行`tuist` ：

```bash
tuist run tuist generate --path /path/to/project --no-open
```

另外，您也可以直接透過 Swift 套件管理員執行：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
