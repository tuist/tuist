---
{
  "title": "文件",
  "titleTemplate": ":title · 代碼 · 貢獻者 · Tuist",
  "description": "為 Tuist 文件網站作出貢獻。"
}
---
# 文件 {#docs}

來源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途 {#what-it-is-for}

文件網站託管 Tuist 的產品及貢獻者文件。它使用 VitePress 構建。

## 如何貢獻 {#how-to-contribute}

### 本機設定 {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可選的生成數據 {#optional-generated-data}

我們在文件中嵌入了一些生成的數據：

- CLI 參考數據：`mise run generate-cli-docs`

這些是可選的。文件可以在沒有它們的情況下渲染，因此只有在需要刷新生成內容時才運行它們。

ProjectDescription API 參考作為 DocC 網站單獨託管於 [projectdescription.tuist.dev](https://projectdescription.tuist.dev)。要在本機構建它，請從儲存庫根目錄運行 `mise run docs:project-description`。
