---
{
  "title": "記錄",
  "titleTemplate": ":title · CLI · 貢獻者 · Tuist",
  "description": "Tuist CLI 中記錄嘅運作方式同貢獻者指引。"
}
---
# 記錄 {#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 介面進行記錄。該套件抽象化記錄的實作細節，讓 CLI 無需依賴特定記錄後端。記錄器透過 task locals 進行依賴注入，可以在任何地方使用以下方式存取：

```bash
Logger.current
```

> [!NOTE]
> 當使用 `Dispatch` 或 detached tasks 時，task locals 不會傳播值，因此如果你使用它們，你需要取得該值並將其傳遞給異步操作。


## 要記錄什麼 {#what-to-log}

日誌並非 CLI 的使用者介面。它們是用於在問題出現時進行診斷的工具。因此，你提供的資訊越多越好。在開發新功能時，請設身處地為遇到意外行為的開發者著想，思考哪些資訊對他們有幫助。確保你使用正確的 [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否則，開發者將無法過濾掉雜訊。
