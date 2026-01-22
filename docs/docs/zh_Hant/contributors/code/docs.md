---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# 文件{#docs}

來源：[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## 用途說明{#what-it-is-for}

文件網站託管 Tuist 的產品與貢獻者文件，採用 VitePress 建置。

## 如何貢獻{#how-to-contribute}

### 在本地端設定{#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### 可選生成資料{#optional-generated-data}

我們在文件中嵌入了部分生成數據：

- CLI 參考資料：`mise run generate-cli-docs`
- 專案清單參考資料：`mise run generate-manifests-docs`

這些是可選的。文件即使沒有這些設定也能正常顯示，因此僅在需要重新生成內容時才執行這些設定。
