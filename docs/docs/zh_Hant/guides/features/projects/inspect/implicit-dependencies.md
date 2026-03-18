---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 隱含導入{#implicit-imports}

為減輕維護原始 Xcode 專案圖的複雜性，Apple
設計了可隱式定義依賴項的建置系統。這意味著某個產品（例如應用程式）即使未明確宣告依賴關係，仍可依賴某個框架。在小規模專案中這並無問題，但隨著專案圖的複雜度增加，這種隱式依賴可能會導致增量建置不穩定，或影響預覽、程式碼完成等編輯器功能。

問題在於，您無法阻止隱含依賴關係的產生。任何開發者都能在 Swift 程式碼中加入`import` 語句，此時隱含依賴關係便會建立。這正是 Tuist
派上用場的地方。Tuist 提供了一項命令，可透過靜態分析專案中的程式碼來檢視隱含依賴關係。以下命令將輸出專案的隱含依賴關係：

```bash
tuist inspect dependencies --only implicit
```

若指令偵測到任何隱含的匯入，將以非零的退出代碼結束執行。

::: tip VALIDATE IN CI
<!-- -->
我們強烈建議您在每次將新程式碼推送至上游時，將此指令納入您的
<LocalizedLink href="/guides/features/automate/continuous-integration">持續整合</LocalizedLink>
流程中執行。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
由於 Tuist 仰賴靜態程式碼分析來偵測隱含的依賴關係，因此可能無法偵測到所有情況。例如，Tuist 無法理解透過程式碼中的編譯器指令所進行的條件式匯入。
<!-- -->
:::
