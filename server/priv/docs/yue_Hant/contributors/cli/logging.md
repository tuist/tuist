---
{
  "title": "記錄",
  "titleTemplate": ":title · CLI · 貢獻者 · Tuist",
  "description": "Tuist CLI 中記錄功能嘅運作方式同埋給貢獻者嘅指引。"
}
---
# 記錄日誌 {#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 介面進行日誌記錄。該套件抽象化日誌實作細節，令 CLI 無需依賴特定後端。日誌器透過任務區域變數注入依賴，可隨處透過以下方式存取：

```bash
Logger.current
```

> [!NOTE]
> 使用 `Dispatch` 或分離任務時，任務區域變數不會傳遞值，因此若使用它們，你需要取得該值並傳入異步操作。


## 應該記錄甚麼 {#what-to-log}

日誌並非 CLI 的使用者介面。它們是用於診斷問題的工具。因此，提供的資訊愈多愈好。開發新功能時，請代入遇到意外行為的開發者角度，思考哪些資訊對他們有幫助。確保使用正確的 [日誌層級](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)，否則開發者將無法過濾雜訊。
