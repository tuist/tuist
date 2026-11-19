---
{
  "title": "隱式匯入",
  "titleTemplate": ":title · 檢查 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 尋找隱式匯入。"
}
---
# 隱式匯入 {#implicit-imports}

為減輕使用原始 Xcode 專案維護 Xcode 專案圖的複雜度，Apple 設計了允許隱式定義依賴項目的建構系統。這表示產品（例如應用程式）可以在未明確宣告依賴的情況下依賴某個框架。在小型專案中這沒問題，但隨著專案圖變得複雜，這種隱式性可能導致增量建構不穩定，或影響預覽、程式碼補全等編輯器功能。

問題在於你無法阻止隱式依賴發生。任何開發者都可以在 Swift 程式碼中加入 `import` 陳述式，從而建立隱式依賴。Tuist 正是為此而來。Tuist 提供一個指令，透過靜態分析專案中的程式碼來檢查隱式依賴。以下指令會輸出你專案中的隱式依賴：

```bash
tuist inspect dependencies --only implicit
```

如果指令偵測到任何隱式匯入，它會以非零的退出碼結束。

> [!TIP]
> **在 CI 中驗證**
>
> 我們強烈建議每次將新程式碼推送到上游時，都將此指令作為 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 流程的一部分執行。


> [!WARNING]
> **並非所有隱式情況都能被偵測到**
>
> 由於 Tuist 依賴靜態程式碼分析來偵測隱式依賴，因此可能無法捕捉所有情況。例如，Tuist 無法理解透過程式碼中編譯器指示詞進行的條件式匯入。
