---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "喺 Tuist 生成嘅 Xcode 專案入面偵測、管理同隔離不穩定測試。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>（自動產生嘅 scheme 會包含 `tuist inspect test` post-action；自訂 scheme 需要手動加入）。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定測試偵測點樣運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試嘅結果。如果一個測試喺某啲嘗試中失敗，但喺其他嘗試中通過，就會被標記為不穩定。

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

- **靜音**：測試仍然會執行，但 `tuist test` 會隱藏失敗結果。失敗結果仍然會提供畀不穩定測試偵測器，所以你可以繼續監察測試而唔會導致建構失敗。如果你正積極調查某個測試，請選擇此模式。
- **跳過**：xcodebuild 會收到 `-skip-testing <identifier>`，因此測試永遠唔會開始執行。佢唔會產生新結果，並會從不穩定測試儀表板中移除，直到你重新啟用佢。當測試損壞、緩慢，或者持續不穩定到執行佢只會浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 執行測試 {#running-tests}

`tuist test` 會自動遵循兩種模式：

```sh
tuist test
```

跳過嘅測試會以 `-skip-testing` 形式傳遞畀 xcodebuild，並且永遠唔會開始執行。靜音測試會正常執行；如果佢哋失敗，失敗結果會喺最終嘅建構狀態中被隱藏。

要完全繞過隔離並執行所有內容（包括靜音同跳過嘅測試）：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

如果一個測試案例喺過去 90 日內無喺專案嘅預設分支上，或者無喺已經合併到預設分支嘅 commit 上喺 CI 中執行過，就會被視為新測試。使用合併佇列時，一旦佇列嘅 commit 合併，佇列執行過嘅測試案例就會被識別；如果佇列刪除咗佢，佢會保持為新測試。Commit 係透過 Tuist 喺 CI 上收集嘅 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link> 進行匹配。

<!-- @snippet: ./_stress-modes -->

喺兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 都唔會喺下一次運行時跳過包含不穩定新測試案例嘅測試目標。該目標會再次執行，閘門會再次對測試案例進行壓力測試，直到佢通過所有重試為止。

將佢放喺透傳參數之前，或者設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據不同嘅 CI 流程變更模式：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

重試會重用第一次執行時建構嘅內容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
