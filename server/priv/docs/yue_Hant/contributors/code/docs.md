---
{
  "title": "文件",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "為 Tuist 文件網站作出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途 {#what-it-is-for}

文件網站託管 Tuist 的產品及貢獻者文件。它以 VitePress 構建。

## 如何貢獻 {#how-to-contribute}

### 本機設定 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可選的生成資料 {#optional-generated-data}

我們在文件中嵌入部分生成資料：

- CLI 參考資料：`mise run generate-cli-docs`

這些為可選項。文件無需它們亦可渲染，因此僅於需要刷新生成內容時才執行。

ProjectDescription API 參考以 DocC 網站形式獨立託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。要於本機構建，請從儲存庫根目錄執行 `mise run docs:project-description`。
