---
{
  "title": "文件",
  "titleTemplate": ":title · 代碼 · 貢獻者 · Tuist",
  "description": "為 Tuist 文件網站作出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## 用途 {#what-it-is-for}

文件網站託管 Tuist 的產品及貢獻者文件。它屬於 Tuist 伺服器（一個 Phoenix 應用程式），會將 `server/priv/docs/en` 底下的 Markdown 頁面渲染到 `/docs`。

## 如何貢獻 {#how-to-contribute}

編輯 `server/priv/docs/en` 底下的英文頁面。翻譯由其他流程管理，請勿編輯其他語系目錄。側邊欄定義於 `server/lib/tuist/docs_sidebar.ex`；請在那裡新增頁面，讓讀者可以找到。

當多個頁面共用相同文字（例如不同建構系統中的同一章節）時，請將文字放入與這些頁面相鄰、名稱以 `_` 開頭的檔案，並使用指向該檔案的 `@snippet:` HTML 註解來引入，就像不穩定測試頁面那樣。以 `_` 開頭的檔案不會單獨發布為頁面。

### 本機設定 {#set-up-locally}

從 `server` 目錄啟動伺服器，並按照其[設定說明](https://github.com/tuist/tuist/blob/main/server/AGENTS.md)：

```bash
cd server
mise install
mise run dev
```

然後開啟 [http://localhost:8080/en/docs](http://localhost:8080/en/docs)。

### 自動產生內容 {#generated-content}

CLI 參考文件是根據最新 CLI 版本的命令規格自動產生，因此不需要在本機建置。

ProjectDescription API 參考文件以 DocC 網站形式獨立託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。若要在本機建置，請從儲存庫根目錄執行 `mise run docs:project-description`。
