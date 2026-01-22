---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不穩定測試{#flaky-tests}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">測試洞察</LocalizedLink>必須進行設定
<!-- -->
:::

不穩定測試是指使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。這類測試會削弱對測試套件的信任度，並浪費開發人員調查虛假失敗的時間。Tuist
能自動偵測不穩定測試，並協助您長期追蹤其狀態。

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定檢測的運作原理{#how-it-works}

Tuist 透過兩種方式偵測不穩定的測試：

### 測試重試{#test-retries}

當您使用 Xcode 的重試功能執行測試（例如透過`-retry-tests-on-failure` 或`-test-iterations` 執行），Tuist
會分析每次嘗試的結果。若某項測試在部分嘗試中失敗而在其他嘗試中通過，則標記為不穩定測試。

例如，若某項測試首次執行失敗但重試成功，Tuist 會將其記錄為不穩定測試。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測{#cross-run-detection}

即使不進行測試重試，Tuist 也能透過比對同一提交在不同 CI 執行中的結果來偵測不穩定測試。若某項測試在一次 CI
執行中通過，但在同一提交的另一次執行中失敗，則兩次執行皆會標記為不穩定。

此功能特別適用於偵測不穩定測試：這些測試因失敗率不足以觸發重試機制，卻仍會導致持續性CI失敗。

## 管理不穩定測試{#managing-flaky-tests}

### 自動清除

Tuist 會自動清除已連續 14 天未出現不穩定現象的測試項目之「不穩定」標記。此機制可確保已修復的測試項目不會永久保留不穩定狀態。

### 手動管理

您亦可從測試案例詳情頁面手動標記或取消標記測試為不穩定。此功能適用於以下情況：
- 您希望在修復過程中標註已知不穩定測試
- 因基礎設施問題導致測試被錯誤標記

## Slack 通知{#slack-notifications}

透過在 Slack 整合中設定
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</LocalizedLink>，即可在測試出現不穩定時立即收到通知。
