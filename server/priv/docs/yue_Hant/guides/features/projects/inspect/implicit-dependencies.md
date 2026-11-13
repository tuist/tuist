---
{
  "title": "隱式匯入",
  "titleTemplate": ":title · 檢查 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 找出隱式匯入。"
}
---
# 隱式匯入 {#implicit-imports}

為咗減輕用原始 Xcode 專案維護 Xcode 專案圖嘅複雜性，Apple 設計咗一個允許隱式定義依賴關係嘅構建系統。即係話，一個產品（例如一個 app）可以依賴某個 framework，即使冇明確聲明呢個依賴關係。喺小規模情況下，咁做冇問題，但隨著專案圖變得更加複雜，隱式依賴可能會導致增量構建不穩定，或者影響基於編輯器嘅功能，例如預覽或代碼補全。

問題在於你無法阻止隱式依賴發生。任何開發者都可以喺佢哋嘅 Swift 代碼中加入 `import` 語句，從而創建隱式依賴。呢個時候就輪到 Tuist 出場。Tuist 提供咗一個命令，透過靜態分析你專案中嘅代碼嚟檢查隱式依賴。以下命令會輸出你專案嘅隱式依賴：

```bash
tuist inspect dependencies --only implicit
```

如果命令檢測到任何隱式匯入，佢會以非零嘅退出碼結束。

> [!TIP]
> **喺 CI 中驗證**
>
> 我哋強烈建議每次有新代碼推送 upstream 時，都將此命令作為你 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 流程嘅一部分嚟執行。


> [!WARNING]
> **並非所有隱式情況都會被檢測到**
>
> 由於 Tuist 依靠靜態代碼分析嚟檢測隱式依賴，佢可能無法捕捉所有情況。例如，Tuist 無法理解代碼中透過編譯器指令實現嘅條件匯入。
