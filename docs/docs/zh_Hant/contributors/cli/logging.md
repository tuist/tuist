---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 記錄{#logging}

此命令列介面採用[swift-log](https://github.com/apple/swift-log)介面進行記錄。此套件抽象化記錄的實作細節，使命令列介面能獨立於記錄後端運作。記錄器透過任務局部變數進行依賴注入，可於任何位置透過以下方式存取：

```bash
Logger.current
```

::: info
<!-- -->
使用`調度` 或分離任務時，任務局部變數不會傳遞其值，因此若需使用，必須自行取得該值並傳遞至非同步操作中。
<!-- -->
:::

## 記錄事項{#what-to-log}

日誌並非命令列介面的使用者介面，而是用於診斷問題發生的工具。因此提供的資訊越詳盡越好。開發新功能時，請設身處地想像開發者遭遇異常行為時的處境，思考哪些資訊對他們最有幫助。務必使用正確的[日誌等級](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)，否則開發者將無法過濾無用訊息。
