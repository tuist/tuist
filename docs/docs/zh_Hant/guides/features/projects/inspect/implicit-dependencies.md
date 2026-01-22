---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隱式導入{#implicit-imports}

為減輕維護原始 Xcode 專案圖的複雜性，Apple
設計了能隱式定義依賴關係的建置系統。這意味著產品（例如應用程式）即使未明確定義依賴關係，仍可依賴框架。在小規模專案中此設計尚可運作，但當專案圖結構日益複雜時，隱式依賴可能導致增量建置不可靠，或影響編輯器功能（如預覽與程式碼完成）。

問題在於無法阻止隱含依賴關係的產生。任何開發者都可能在 Swift 程式碼中加入`import` 這類陳述，隱含依賴關係便會自動建立。這正是 Tuist
的用武之地。Tuist 提供指令透過靜態分析專案程式碼來檢視隱含依賴關係。執行以下指令即可輸出專案的隱含依賴關係：

```bash
tuist inspect dependencies --only implicit
```

若指令偵測到任何隱含的輸入，將以非零退出代碼結束執行。

::: tip VALIDATE IN CI
<!-- -->
我們強烈建議將此指令納入您的<LocalizedLink href="/guides/features/automate/continuous-integration">持續整合</LocalizedLink>流程，每當新程式碼推送至上游時自動執行。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
由於 Tuist 依賴靜態程式碼分析來偵測隱含依賴關係，可能無法涵蓋所有情況。例如，Tuist 無法理解程式碼中透過編譯器指令實現的條件式導入。
<!-- -->
:::
