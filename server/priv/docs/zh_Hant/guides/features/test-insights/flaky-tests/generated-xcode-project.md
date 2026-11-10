---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 產生的 Xcode 專案中偵測、管理與隔離不穩定測試。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>（自動產生的 Scheme 包含 `tuist inspect test` 後續動作；自訂 Scheme 需要手動加入）。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行具備重試功能的測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，就會被標記為不穩定。

透過 `tuist test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但 `tuist test` 會遮蔽失敗結果。失敗仍會提供給不穩定測試偵測器，因此你可以持續觀察該測試而不影響建置。適用於你正在積極調查的測試。
- **略過**：xcodebuild 會收到 `-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生新結果，並會從不穩定測試儀表板中移除，直到你重新啟用為止。當測試損壞、緩慢，或過於持續不穩定以致於執行只會浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 執行測試 {#running-tests}

`tuist test` 會自動遵循這兩種模式：

```sh
tuist test
```

略過的測試會以 `-skip-testing` 傳遞給 xcodebuild，且永遠不會啟動。靜音測試會正常執行；如果失敗，失敗結果會在最終建置狀態中被遮蔽。

若要完全繞過隔離並執行所有內容（包括靜音和略過的測試）：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行時，即視為新測試案例。使用合併佇列時，佇列執行的測試案例會在佇列提交合併後被識別，若佇列將其移除則保持為新測試案例。提交是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link> 進行比對。

<!-- @snippet: ./_stress-modes -->

在這兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 不會在下一次執行時略過包含不穩定新測試案例的測試目標。該目標會再次執行，閘道會再次對測試案例進行壓力測試，直到其通過所有重試為止。

將其放在透傳參數之前，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據 CI 管線調整模式：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

重試會重複使用第一次通行所建置的內容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
