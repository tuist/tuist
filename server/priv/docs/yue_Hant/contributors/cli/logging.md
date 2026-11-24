---
{
  "title": "日誌記錄",
  "titleTemplate": ":title · CLI · 貢獻者 · Tuist",
  "description": "Tuist CLI 中日誌記錄的運作方式及貢獻者指南。"
}
---
# 記錄日誌 {#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 介面進行日誌記錄。該套件將日誌實作細節抽象化，令 CLI 無需依賴特定後端。記錄器透過任務區域變數注入依賴，可隨處透過以下方式存取：

```bash
Logger.current
```

> [!NOTE]
> 使用 `Dispatch` 或分離任務時，任務區域變數不會傳遞值，因此若使用它們，你需要取得該值並傳入非同步作業。


## 應記錄甚麼 {#what-to-log}

日誌並非 CLI 的使用者介面，而是用於在問題出現時進行診斷。因此，提供的資訊愈多愈好。開發新功能時，請設身處地想像開發人員遇到意外行為的情境，思考哪些資訊對他們有幫助。請確保使用正確的 [日誌級別](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)，否則開發人員將無法過濾雜訊。
