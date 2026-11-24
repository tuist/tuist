---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "喺 Tuist 生成嘅 Xcode 專案入面偵測、管理同隔離不穩定測試。"
}
---
# 已生成嘅 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>（自動生成嘅 scheme 會包含 `tuist inspect test` post-action；自訂 scheme 需要手動加入）。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定測試偵測運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行帶有重試功能嘅測試時，Tuist 會分析每次嘗試嘅結果。如果一個測試案例喺某啲嘗試中失敗，但喺其他嘗試中通過，就會被標記為不穩定。

透過 `tuist test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔離嘅測試處於以下兩種模式之一：

- **靜音**：測試仍然會執行，但 `tuist test` 會隱藏失敗結果。失敗記錄仍會提供俾不穩定測試偵測器，因此你可以繼續監察該測試而唔會導致建構失敗。適用於你積極調查中嘅測試。
- **略過**：xcodebuild 會收到 `-skip-testing <identifier>`，因此測試永遠唔會啟動。佢唔會產生新結果，並會從不穩定測試儀表板中移除，直到你重新啟用為止。當測試損壞、緩慢，或者持續不穩定到執行只係浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 執行測試 {#running-tests}

`tuist test` 會自動遵循兩種模式：

```sh
tuist test
```

略過嘅測試會以 `-skip-testing` 形式傳遞俾 xcodebuild 且永遠唔會啟動。靜音測試會正常執行；如果失敗，失敗結果會喺最終建構狀態中被隱藏。

要完全繞過隔離並執行所有內容（包括靜音同略過嘅測試）：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

如果一個測試案例喺過去 90 日內未喺專案嘅預設分支上執行過 CI，或者未喺已合併至該分支嘅提交中執行過，則會被視為新測試案例。使用合併佇列時，佇列執行過嘅測試案例喺佇列提交合併後會被識別，如果佇列將其丟棄，則保持為新測試案例。提交係透過 Tuist 喺 CI 上收集嘅 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link> 進行匹配。

<!-- @snippet: ./_stress-modes -->

喺兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 都唔會喺下一次運行中略過包含不穩定新測試案例嘅測試目標。該目標會再次運行，閘門會再次對該測試案例進行壓力測試，直到其通過所有重試為止。

將佢放喺透傳參數之前，或者設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據每個 CI 流程變更模式：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

重試會重用第一次構建所產生嘅內容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
