---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# 雜湊{#hashing}

<LocalizedLink href="/guides/features/cache">快取</LocalizedLink>或選擇性測試執行等功能需要一種方法來判斷目標是否已變更。Tuist
會為依賴圖表中的每個目標計算雜湊值，以判斷目標是否已變更。哈希值是根據下列屬性計算出來的：

- 目標的屬性（例如名稱、平台、產品等）
- 目標的檔案
- 目標的相依性雜湊值

### 快取屬性{#cache-attributes}

此外，在計算 <LocalizedLink href="/guides/features/cache">caching</LocalizedLink>
的散列值時，我們也會對下列屬性進行散列。

#### Swift 版本{#swift-version}

我們散列執行指令`/usr/bin/xcrun swift --version` 所獲得的 Swift 版本，以防止因目標與二進檔之間的 Swift
版本不匹配而導致編譯錯誤。

::: info MODULE STABILITY
<!-- -->
先前版本的二進位緩存依賴`BUILD_LIBRARY_FOR_DISTRIBUTION` 建立設定來啟用 [module
stability](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
並使用任何編譯器版本的二進位檔。然而，這會在不支援模組穩定性的目標專案中造成編譯問題。產生的二進位檔會與用來編譯的 Swift 版本綁定，而 Swift
版本必須與用來編譯專案的版本相符。
<!-- -->
:::

#### 組態{#configuration}

`-configuration` 這個旗號背後的想法是要確保 debug binaries 不會被用在 release builds
中，反之亦然。然而，我們仍然缺少一個機制來移除專案中的其他配置，以防止它們被使用。

## 除錯{#debugging}

如果您在跨環境或調用使用快取時發現非決定性的行為，這可能與跨環境的差異或散列邏輯中的錯誤有關。我們建議按照以下步驟來調試問題：

1. 執行`tuist hash cache` 或`tuist hash selective-testing` (哈希值為
   <LocalizedLink href="/guides/features/cache"> 二进制快取</LocalizedLink>或
   <LocalizedLink href="/guides/features/selective-testing"> 選擇性測試</LocalizedLink>)，複製哈希值，重新命名專案目錄，再執行一次指令。哈希值應該相符。
2. 如果哈希值不匹配，很可能是生成的專案取決於環境。在兩種情況下執行`tuist graph --format json` 並比較圖形。或者，生成專案，並使用
   [Diffchecker](https://www.diffchecker.com) 等差異工具比較它們的`project.pbxproj` 檔案。
3. 如果哈希值相同，但在不同的環境（例如 CI 與本機）下有所不同，請確定各處都使用相同的 [configuration](#configuration) 與
   [Swift 版本](#swift-version)。Swift 版本與 Xcode 版本相關，因此請確認 Xcode 版本相符。

如果哈希值仍然是非確定的，請告訴我們，我們可以協助除錯。


::: info BETTER DEBUGGING EXPERIENCE PLANNED
<!-- -->
改善我們的除錯經驗在我們的路線圖中。print-hashes 指令缺乏瞭解差異的上下文，將被更容易使用的指令取代，該指令使用樹狀結構來顯示哈希值之間的差異。
<!-- -->
:::
