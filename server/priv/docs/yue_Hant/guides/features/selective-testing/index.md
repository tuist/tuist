---
{
  "title": "選擇性測試",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Selective Testing，只執行受你最新改動影響嘅測試，讓持續整合喺幾秒內提供反饋。"
}
---
# 選擇性測試 {#selective-testing}

隨著項目規模擴大，每次推送都執行所有測試變得不可行。Tuist 選擇性測試透過只執行受上次成功運行後變更影響的測試，大幅縮短測試時間，並使用我哋嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>。

## 支援嘅建構系統 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

計劃支援其他建構系統。
