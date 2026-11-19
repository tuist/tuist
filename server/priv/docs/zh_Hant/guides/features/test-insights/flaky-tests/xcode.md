---
{
  "title": "Xcode 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理並隔離 Xcode 專案中的不穩定測試。"
}
---
# Xcode 不穩定測試 {#xcode-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>。Tuist 會從每次測試執行上傳的測試洞察事件中偵測不穩定測試。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果測試在某些嘗試中失敗，但在其他嘗試中通過，則會被標記為不穩定。

透過 `tuist xcodebuild test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但 `tuist xcodebuild test` 會遮蔽失敗結果。失敗結果仍會提供給不穩定測試偵測器，因此你可以持續監控該測試而不導致建置失敗。適用於你正在積極調查的測試。
- **略過**：xcodebuild 會收到 `-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生任何新結果，並會從不穩定測試儀表板中移除，直到你重新啟用為止。當測試損壞、緩慢，或不穩定情況嚴重到執行只會浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 執行測試 {#running-tests}

`tuist xcodebuild test` 是一個自動支援這兩種模式的透傳包裝器。使用方式與呼叫 xcodebuild 相同：

```sh
tuist xcodebuild test -scheme MyScheme
```

略過的測試會以 `-skip-testing <identifier>` 的形式附加到你的 xcodebuild 叫用中，且永遠不會啟動。靜音測試會正常執行；如果失敗，失敗結果會在最終的建置狀態中被遮蔽。

#### 繞過隔離 {#bypassing-quarantine}

`tuist xcodebuild test` 接受 `--skip-quarantine` 以執行所有內容，包括靜音和略過的測試：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### 直接呼叫 xcodebuild {#calling-xcodebuild-directly}

如果你無法透過 `tuist xcodebuild test` 執行，可以使用 `tuist test case list` 自行將被隔離的測試展開為 `-skip-testing` 參數：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

這是在 `tuist xcodebuild test` 之外的安全預設值：靜音測試的失敗遮蔽僅在你透過該命令執行時才會發生，因此略過這兩種模式可以避免虛假的 CI 失敗。如果你需要更精細的控制，請改用 `tuist xcodebuild test`。

## 對新測試進行壓力測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行時，即視為新測試案例。在使用合併佇列的情況下，佇列執行的測試案例會在佇列的提交合併後被識別，如果佇列將其移除，則保持為新測試案例。提交是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link> 進行比對。

<!-- @snippet: ./_stress-modes -->

將其放在透傳參數之前，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以針對每個 CI 管道變更模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

重新執行會重用第一次執行所建置的內容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
