---
{
  "title": "文件",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist 文件網站做出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 用途 {#what-it-is-for}

文件網站託管 Tuist 的產品與貢獻者文件。它是 Tuist 伺服器（一個 Phoenix 應用程式）的一部分，負責將 `server/priv/docs/en` 下的 Markdown 頁面渲染至 `/docs`。

## 如何貢獻 {#how-to-contribute}

編輯 `server/priv/docs/en` 下的英文頁面。翻譯由獨立流程管理，因此請勿編輯其他語系目錄。側邊欄定義於 `server/lib/tuist/docs_sidebar.ex`；請在此處新增頁面，以便讀者找到它們。

當多個頁面共用相同文字時（例如不同建置系統中的相同章節），請將其放入名稱以 `_` 開頭、並置於這些頁面旁的檔案中，然後使用指向該檔案的 `@snippet:` HTML 註解來引入，如同不穩定測試頁面所做的那樣。以 `_` 開頭的檔案不會作為獨立頁面發布。

### 本機設定 {#set-up-locally}

從 `server` 目錄啟動伺服器，並遵循其[設定說明](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)：

```bash
cd server
mise install
mise run dev
```

接著開啟 [http://localhost:8080/en/docs](http://localhost:8080/en/docs)。

### 自動產生的內容 {#generated-content}

CLI 參考文件是根據最新 CLI 版本的命令規格自動產生，因此無需在本機建置。

ProjectDescription API 參考文件以 DocC 網站的形式獨立託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。若要在本機建置，請從儲存庫根目錄執行 `mise run docs:project-description`。
