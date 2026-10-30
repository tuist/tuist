---
{
  "title": "雜湊",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "Tuist 雜湊如何驅動二進位快取與選擇性測試。"
}
---
# 雜湊 {#hashing}

<.localized_link href="/guides/features/cache">快取</.localized_link>或選擇性測試執行等功能，需要一種方法來判斷目標是否已變更。Tuist 會為依賴關係圖中的每個目標計算雜湊值，以判斷目標是否已變更。雜湊值是根據以下屬性計算：

- 目標的屬性（例如名稱、平台、產品等）
- 目標的檔案
- 目標依賴項的雜湊值

### 快取屬性 {#cache-attributes}

此外，在為 <.localized_link href="/guides/features/cache">快取</.localized_link> 計算雜湊時，我們亦會對以下屬性進行雜湊。

#### Swift 版本 {#swift-version}

我們會對執行命令 `/usr/bin/xcrun swift --version` 所取得的 Swift 版本進行雜湊，以防止因目標與二進位檔之間的 Swift 版本不相符而導致編譯錯誤。

> [!NOTE]
> **模組穩定性**
>
> 早期版本的二進位快取依賴 `BUILD_LIBRARY_FOR_DISTRIBUTION` 建置設定來啟用 [模組穩定性](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)，並允許使用任何編譯器版本的二進位檔。然而，這會在包含不支援模組穩定性之目標的專案中引起編譯問題。產生的二進位檔會綁定至編譯它們時使用的 Swift 版本，而該 Swift 版本必須與編譯專案時使用的版本相符。


#### 組態 {#configuration}

在計算快取雜湊時，Tuist 會將每個專案和目標的設定範圍限定於已解析的建置組態。即透過 `--configuration` 指定的名稱；若未指定，則使用專案的 `defaultConfiguration`；若仍未指定，則使用第一個偵錯組態。Tuist 會將該組態的名稱、變體、建置設定及組態檔案內容，連同適用於它的共用基礎設定一併進行雜湊。新增、移除或變更其他組態不會影響已解析組態的快取雜湊值。由於只有已解析的組態至關重要，因此透過明確指定 `--configuration` 填入的快取，可被解析至相同組態但未傳遞該旗標的命令讀取。

## 除錯 {#debugging}

如果你發現在不同環境或多次呼叫中使用快取時出現非確定性行為，這可能與環境差異或雜湊邏輯中的錯誤有關。我們建議按照以下步驟來除錯問題：

1. 執行 `tuist hash cache` 或 `tuist hash selective-testing`（分別為 <.localized_link href="/guides/features/cache">二進位快取</.localized_link> 或 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 的雜湊值），複製雜湊值，重新命名專案目錄，然後再次執行命令。雜湊值應該相符。
2. 如果雜湊值不相符，很可能產生的專案依賴於環境。在兩種情況下均執行 `tuist graph --format json` 並比較圖表。或者，產生專案並使用如 [Diffchecker](https://www.diffchecker.com) 的差異比較工具來比較它們的 `project.pbxproj` 檔案。
3. 如果雜湊值相同但在不同環境（例如 CI 和本地）之間存在差異，請確保所有地方都使用相同的 [組態](#configuration) 和 [Swift 版本](#swift-version)。Swift 版本與 Xcode 版本綁定，因此請確認 Xcode 版本相符。

如果雜湊值仍然非確定性，請告訴我們，我們可以協助除錯。


> [!NOTE]
> **計劃改善除錯體驗**
>
> 改善我們的除錯體驗已在路線圖中。print-hashes 命令由於缺乏理解差異所需的上下文，將被一個更使用者友善的命令取代，該命令使用樹狀結構來顯示雜湊值之間的差異。
