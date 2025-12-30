---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隱含進口{#implicit-imports}

為了減輕用原始 Xcode 專案維護 Xcode 專案圖的複雜性，Apple
在設計建立系統時允許隱式定義依賴關係。這表示一個產品，例如一個應用程式，可以依賴於一個框架，甚至不需要明確地宣告依賴關係。在小規模的情況下，這是沒問題的，但隨著專案圖形的複雜度增加，隱含性可能會表現為不可靠的增量建立或基於編輯器的功能，例如預覽或程式碼完成。

問題是您無法阻止隱含相依性的發生。任何開發人員都可以在他們的 Swift 程式碼中加入`import` 語句，隱含相依性就會產生。這就是 Tuist
的用武之地。Tuist 提供了一個命令，透過靜態分析專案中的程式碼來檢查隱含相依性。以下命令將輸出專案的隱含相依性：

```bash
tuist inspect implicit-imports
```

如果指令偵測到任何隱含的匯入，它會以 0 以外的退出代碼退出。

::: tip VALIDATE IN CI
<!-- -->
我們強烈建議每次有新程式碼推送到上游時，就執行這個指令，作為
<LocalizedLink href="/guides/features/automate/continuous-integration">continuous integration</LocalizedLink> 指令的一部分。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
由於 Tuist 依賴靜態程式碼分析來偵測隱含的依賴關係，因此可能無法偵測到所有的情況。例如，Tuist 無法理解程式碼中透過編譯器指令的條件匯入。
<!-- -->
:::
