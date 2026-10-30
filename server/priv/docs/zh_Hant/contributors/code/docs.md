---
{
  "title": "文件",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist 文件網站做出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途 {#what-it-is-for}

此文件網站託管 Tuist 的產品與貢獻者文件。它以 VitePress 建構。

## 如何貢獻 {#how-to-contribute}

### 本機設定 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 選擇性產生的資料 {#optional-generated-data}

我們在文件中嵌入部分產生的資料：

- CLI 參考資料：`mise run generate-cli-docs`

這些為選擇性項目。文件可在沒有它們的情況下呈現，因此僅在需要重新整理產生內容時才執行。

ProjectDescription API 參考文件以 DocC 網站的形式獨立託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。若要在本機建置，請從儲存庫根目錄執行 `mise run docs:project-description`。
