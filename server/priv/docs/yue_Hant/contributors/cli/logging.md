---
{
  "title": "日誌記錄",
  "titleTemplate": ":title · CLI · 貢獻者 · Tuist",
  "description": "Tuist CLI 中日誌記錄的運作方式，以及給貢獻者的指引。"
}
---
# 記錄日誌 {#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 介面進行日誌記錄。該套件將日誌實作細節抽象化，令 CLI 無需依賴特定後端。日誌器透過 task locals 進行依賴注入，可於任何位置使用以下方式存取：

```bash
Logger.current
```

> [!NOTE]
> 使用 `Dispatch` 或 detached tasks 時，task locals 不會傳播值，因此若你使用它們，需要取得該值並傳遞至非同步作業。


## 應記錄甚麼 {#what-to-log}

日誌並非 CLI 的使用者介面。它們是用於在問題出現時進行診斷的工具。因此，提供的資訊愈多愈好。在開發新功能時，請設身處地為遇到意外行為的開發者著想，思考哪些資訊對他們有幫助。確保你使用正確的 [日誌級別](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否則開發者將無法過濾雜訊。
