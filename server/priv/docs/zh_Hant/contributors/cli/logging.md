---
{
  "title": "記錄",
  "titleTemplate": ":title · CLI · 貢獻者 · Tuist",
  "description": "Tuist CLI 中的記錄運作方式及給貢獻者的指南。"
}
---
# 記錄{#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 介面進行記錄。該套件抽象化了記錄的實作細節，讓 CLI 無需依賴特定的記錄後端。記錄器透過工作區域變數進行依賴注入，並可隨時透過以下方式存取：

```bash
Logger.current
```

> [!NOTE]
> 使用 `Dispatch` 或分離工作時，工作區域變數不會傳播值，因此若你使用它們，需要取得該值並傳遞給非同步作業。


## 應記錄的內容{#what-to-log}

記錄並非 CLI 的使用者介面。它們是用於在問題發生時進行診斷的工具。因此，提供的資訊愈多愈好。在建置新功能時，請設身處地為遇到非預期行為的開發者著想，思考哪些資訊對他們有幫助。請確保使用正確的[記錄層級](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否則，開發者將無法過濾雜訊。
