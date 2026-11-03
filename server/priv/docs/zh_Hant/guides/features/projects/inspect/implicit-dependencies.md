---
{
  "title": "隱含匯入",
  "titleTemplate": ":title · 檢查 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 找出隱含匯入。"
}
---
# 隱式匯入 {#implicit-imports}

為了降低使用原始 Xcode 專案維護 Xcode 專案圖的複雜度，Apple 設計的建置系統允許以隱式方式定義相依性。這表示產品（例如 App）可以依賴某個 Framework，即使未明確宣告該相依性。在規模較小時，這不成問題，但隨著專案圖日益複雜，這種隱式特性可能導致增量建置不穩定，或影響預覽與程式碼完成等編輯器功能。

問題在於你無法防止隱式相依性發生。任何開發者都能在 Swift 程式碼中加入 `import` 陳述式，進而產生隱式相依性。這時 Tuist 就派上用場了。Tuist 提供一個指令，可透過靜態分析專案中的程式碼來檢查隱式相依性。以下指令會輸出你專案中的隱式相依性：

```bash
tuist inspect dependencies --only implicit
```

如果指令偵測到任何隱式匯入，它會以非零的結束碼退出。

> [!TIP]
> **在 CI 中驗證**
>
> 我們強烈建議每次將新程式碼推送至上游時，都將此指令作為 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 流程的一部分執行。


> [!WARNING]
> **並非所有隱式情況都能被偵測到**
>
> 由於 Tuist 仰賴靜態程式碼分析來偵測隱式相依性，因此可能無法涵蓋所有情況。例如，Tuist 無法理解透過程式碼中的編譯器指示詞進行的條件式匯入。
