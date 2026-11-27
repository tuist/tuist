---
{
  "title": "選擇性測試",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 選擇性測試，只執行受你最新變更影響的測試，讓持續整合喺幾秒內提供反饋。"
}
---
# 選擇性測試 {#selective-testing}

隨著專案規模擴大，每次推送都執行所有測試已不再可行。Tuist 選擇性測試利用我哋嘅 <.localized_link href="/guides/features/projects/hashing">雜湊演算法</.localized_link>，只執行受上次成功運行以來變更影響嘅測試，從而大幅縮短測試時間。如需其他縮短測試時間嘅方法（例如分片同修復緩慢測試），請參閱 [緩慢測試](https://tuist.dev/solutions/slow-tests)。

## 支援嘅建置系統 {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

我哋計劃支援其他建置系統。
