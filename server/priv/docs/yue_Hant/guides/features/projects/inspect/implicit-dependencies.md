---
{
  "title": "隱式匯入",
  "titleTemplate": ":title · 檢查 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 尋找隱式匯入。"
}
---
# 隱式匯入 {#implicit-imports}

為咗減輕用原始 Xcode 專案維護 Xcode 專案圖嘅複雜性，Apple 設計咗一套允許隱式定義依賴關係嘅建構系統。這意味著一個產品（例如一個應用程式）可以依賴一個框架，即使沒有明確聲明該依賴關係。喺小規模下，這無問題，但隨著專案圖變得更加複雜，隱式依賴可能會導致增量建構不可靠，或者影響基於編輯器嘅功能，例如預覽或代碼補全。

問題在於你無法阻止隱式依賴發生。任何開發者都可以喺佢哋嘅 Swift 代碼中加入 `import` 語句，從而創建隱式依賴。這就是 Tuist 派上用場嘅地方。Tuist 提供咗一個命令，通過靜態分析你專案中嘅代碼來檢查隱式依賴。以下命令將輸出你專案嘅隱式依賴：

```bash
tuist inspect dependencies --only implicit
```

如果命令檢測到任何隱式匯入，它會以非零嘅退出碼結束。

> [!TIP]
> **喺 CI 中驗證**
>
> 我哋強烈建議每次有新代碼推送到上游時，都將此命令作為你 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 命令嘅一部分運行。


> [!WARNING]
> **並非所有隱式情況都能被檢測到**
>
> 由於 Tuist 依賴靜態代碼分析來檢測隱式依賴，它可能無法捕捉所有情況。例如，Tuist 無法理解通過代碼中嘅編譯器指令進行嘅條件匯入。
