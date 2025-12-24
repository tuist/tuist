---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 記錄{#logging}

CLI 採用 [swift-log](https://github.com/apple/swift-log) 記錄介面。此套件抽象出記錄的實作細節，讓 CLI
與記錄後端無關。日誌記錄器是使用任務本地端（task locals）進行依賴注入（dependency-injected），並可在任何地方使用以下方式存取：

```bash
Logger.current
```

::: info
<!-- -->
當使用`Dispatch` 或分離的任務時，任務本地端不會傳播值，所以如果您使用它們，您需要取得該值並將它傳給異步操作。
<!-- -->
:::

## 記錄什麼{#what-to-log}

日誌不是 CLI
的使用者介面。當問題發生時，它們是診斷問題的工具。因此，您提供的資訊越多越好。在建立新功能時，站在開發人員遇到意外行為的立場，想想哪些資訊會對他們有幫助。確保使用正確的
[日誌層級](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)。否則開發人員無法濾除雜訊。
