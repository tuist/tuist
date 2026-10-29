---
{
  "title": "文件",
  "titleTemplate": ":title · 程式碼 · 貢獻者 · Tuist",
  "description": "為 Tuist 文件網站作出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途 {#what-it-is-for}

文件網站承載 Tuist 的產品與貢獻者文件。它以 VitePress 建構。

## 如何貢獻 {#how-to-contribute}

### 本機設定 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可選的產生資料 {#optional-generated-data}

我們會在文件中嵌入部分產生的資料：

- CLI 參考資料：`mise run generate-cli-docs`

這些是可選的。文件無需它們亦可渲染，因此只在你需要刷新產生內容時才執行。

ProjectDescription API 參考以獨立的 DocC 網站形式託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。要在本機構建，請從儲存庫根目錄執行 `mise run docs:project-description`。
