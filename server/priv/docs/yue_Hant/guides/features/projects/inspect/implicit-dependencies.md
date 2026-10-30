---
{
  "title": "隱式匯入",
  "titleTemplate": ":title · 檢查 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 尋找隱式匯入。"
}
---
# 隱式匯入 {#implicit-imports}

為減輕使用原始 Xcode 專案維護 Xcode 專案圖的複雜性，Apple 設計的建構系統允許以隱式方式定義相依性。這意味著產品（例如 App）可以依賴某個 Framework，即使沒有明確宣告該相依性。在小型專案中這沒問題，但隨著專案圖變得複雜，這種隱式特性可能導致增量建構不穩定，或影響編輯器功能（例如預覽或程式碼補全）。

問題在於你無法阻止隱式相依性發生。任何開發者都可以在其 Swift 程式碼中加入 `import` 陳述式，從而建立隱式相依性。這正是 Tuist 發揮作用的地方。Tuist 提供一個指令，透過靜態分析專案中的程式碼來檢查隱式相依性。以下指令會輸出你專案的隱式相依性：

```bash
tuist inspect dependencies --only implicit
```

如果指令偵測到任何隱式匯入，它會以非零的結束碼退出。

> [!TIP]
> **在 CI 中驗證**
>
> 我們強烈建議每次有新程式碼推送到上游時，都將此指令作為你 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 流程的一部分執行。


> [!WARNING]
> **並非所有隱式情況都能被偵測到**
>
> 由於 Tuist 依賴靜態程式碼分析來偵測隱式相依性，它可能無法捕捉所有情況。例如，Tuist 無法理解透過程式碼中編譯器指示詞進行的條件式匯入。
