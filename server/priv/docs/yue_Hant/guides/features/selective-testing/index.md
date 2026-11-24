---
{
  "title": "選擇性測試",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，只執行受你最新改動影響的測試，讓持續整合在數秒內提供反饋。"
}
---
# 選擇性測試 {#selective-testing}

隨著項目規模擴大，每次推送都執行所有測試變得不可行。Tuist 選擇性測試透過只執行受上次成功運行以來變更影響的測試，大幅縮短測試時間，並使用我哋嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。如需其他縮短測試時間的方法，例如分片執行同修復緩慢測試，請參閱 [緩慢測試](https://tuist.dev/solutions/slow-tests)。

## 支援的構建系統 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

計劃支援其他構建系統。
