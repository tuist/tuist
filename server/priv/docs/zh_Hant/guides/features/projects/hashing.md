---
{
  "title": "雜湊",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "Tuist 雜湊如何驅動二進位快取與選擇性測試。"
}
---
# 雜湊 {#hashing}

<.localized_link href="/guides/features/cache">快取</.localized_link>或選擇性測試執行等功能，需要一種方法來判斷目標是否已變更。Tuist 會計算相依圖中每個目標的雜湊值，以判斷目標是否已變更。雜湊值是根據以下屬性計算：

- 目標的屬性（例如名稱、平台、產品等）
- 目標的檔案
- 目標相依性的雜湊值

### 快取屬性 {#cache-attributes}

此外，在計算 <.localized_link href="/guides/features/cache">快取</.localized_link>的雜湊值時，我們也會將以下屬性納入雜湊。

#### Swift 版本 {#swift-version}

我們會對執行 `/usr/bin/xcrun swift --version` 指令取得的 Swift 版本進行雜湊，以避免因目標與二進位檔之間的 Swift 版本不符而導致編譯錯誤。

> [!NOTE]
> **模組穩定性**
>
> 先前版本的二進位快取依賴 `BUILD_LIBRARY_FOR_DISTRIBUTION` 建置設定來啟用 [模組穩定性](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)，並允許使用任何編譯器版本的二進位檔。然而，這會在包含不支援模組穩定性之目標的專案中造成編譯問題。產生的二進位檔會綁定至編譯它們時使用的 Swift 版本，且該 Swift 版本必須與編譯專案時使用的版本相符。


#### 組態 {#configuration}

在計算快取雜湊值時，Tuist 會將每個專案和目標的設定範圍限定於已解析的建置組態。也就是透過 `--configuration` 指定的組態；若未指定，則使用專案的 `defaultConfiguration`；若仍無，則使用第一個除錯組態。Tuist 會將該組態的名稱、變體、建置設定和組態檔案內容，連同適用於它的共用基礎設定一起進行雜湊。新增、移除或變更其他組態不會影響已解析組態的快取雜湊值。由於只有已解析的組態重要，因此使用明確 `--configuration` 填入的快取，可被解析至相同組態但未傳遞該旗標的指令讀取。

## 除錯 {#debugging}

如果你在不同環境或呼叫中使用快取時發現非確定性行為，可能與環境差異或雜湊邏輯中的錯誤有關。我們建議依照以下步驟來除錯：

1. 執行 `tuist hash cache` 或 `tuist hash selective-testing`（分別為 <.localized_link href="/guides/features/cache">二進位快取</.localized_link> 或 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 的雜湊值），複製雜湊值，重新命名專案目錄，然後再次執行指令。雜湊值應該相符。
2. 如果雜湊值不相符，可能是產生的專案依賴環境。在兩種情況下都執行 `tuist graph --format json` 並比較圖表。或者，產生專案並使用如 [Diffchecker](https://www.diffchecker.com) 的差異比較工具來比較它們的 `project.pbxproj` 檔案。
3. 如果雜湊值相同但在不同環境（例如 CI 和本機）之間不同，請確保各處都使用相同的 [組態](#configuration) 和 [Swift 版本](#swift-version)。Swift 版本與 Xcode 版本綁定，因此請確認 Xcode 版本相符。

如果雜湊值仍然非確定性，請告訴我們，我們可以協助除錯。


> [!NOTE]
> **規劃更好的除錯體驗**
>
> 改善我們的除錯體驗已在路線圖中。print-hashes 指令缺乏理解差異所需的脈絡，將被一個更友善的指令取代，該指令會使用樹狀結構來顯示雜湊值之間的差異。
