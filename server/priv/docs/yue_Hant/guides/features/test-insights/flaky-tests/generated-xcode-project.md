---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 生成的 Xcode 專案中偵測、管理及隔離不穩定測試。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **要求**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link> 已設定（自動產生嘅 scheme 會包含 `tuist inspect test` post-action；自訂 scheme 需要手動加入）。

不穩定測試係指喺相同代碼下多次執行時，會產生唔同結果（通過或失敗）嘅測試。呢啲測試會削弱你對測試套件嘅信任，並浪費開發人員排查虛假失敗嘅時間。Tuist 會自動偵測不穩定測試，並幫你隨時間追蹤佢哋。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測點樣運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行帶有重試功能嘅測試時，Tuist 會分析每次嘗試嘅結果。如果一個測試喺某啲嘗試中失敗，但喺其他嘗試中通過，佢就會被標記為不穩定。

透過 `tuist test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使冇測試重試，Tuist 都可以透過比較同一個 commit 同同一個 scheme 下唔同 CI 執行嘅結果嚟偵測不穩定測試。如果一個測試喺一次 CI 執行中通過，但喺同一個 commit 同 scheme 嘅另一次執行中失敗，兩次執行都會被標記為不穩定。

Scheme 係比較鍵嘅一部分，因為同一個測試喺唔同 scheme 下可能會表現出確定性嘅差異——例如，只針對特定模擬器目標有效嘅快照測試，或者用唔同編譯標誌編譯嘅測試目標。同一個 commit 喺唔同 scheme 下嘅兩次執行會被視為獨立嘅執行變體，唔會互相標記為不穩定。

呢種方法對於捕捉嗰啲失敗頻率唔足以被重試捕捉，但仍然會導致間歇性 CI 失敗嘅不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測同清除會透過專案上嘅 **自動化警報** 運行。每個專案都會有一個預設嘅「不穩定測試偵測」自動化，其 *觸發器* 會將測試標記為不穩定，而其 *恢復* 動作會喺測試喺設定嘅恢復窗口（預設 **14 日**）內冇重新觸發後清除標記。你可以喺 **設定 → 自動化** 下編輯佢，以更改恢復窗口、更換恢復動作（例如同時解除隔離），或者完全停用恢復，令測試保持標記為不穩定，直到你手動清除。

### 手動管理

你亦可以喺測試案例詳情頁面手動將測試標記或取消標記為不穩定。以下情況會好有用：
- 你想喺修復已知不穩定測試期間確認佢
- 測試因為基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，令佢喺你修復期間唔會阻塞 CI。預設情況下，這係一項 **手動操作**——你可以喺儀表板嘅測試案例詳情頁面進行隔離、解除隔離同切換模式——但你亦可以將其接入 **設定 → 自動化** 下嘅 **自動化警報**，令測試喺超過不穩定閾值時自動靜音（或跳過），並喺恢復時解除隔離。每次轉換，無論係手動定自動化，都會記錄喺測試案例嘅審計日誌中。

被隔離嘅測試處於以下兩種模式之一：

- **靜音**：測試仍然會執行，但 `tuist test` 會掩蓋失敗。失敗仍然會輸入不穩定測試偵測器，所以你可以繼續觀察測試而唔會破壞構建。選擇呢種模式適用於你正在積極調查嘅測試。
- **跳過**：xcodebuild 會收到 `-skip-testing <identifier>`，所以測試永遠唔會開始。佢唔會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用佢。當測試損壞、緩慢，或者不穩定到運行佢只會浪費 CI 分鐘數時，選擇呢種模式。

### 點解被隔離嘅測試會顯示為通過 {#quarantined-passing}

- **靜音測試** 仍然會執行。一個失敗嘅靜音測試會喺測試案例執行中被記錄為 **失敗** 並標記為不穩定——每個測試嘅狀態唔會被改寫。被覆蓋嘅係 **整體測試執行**：如果執行中每個失敗嘅測試案例都被靜音，那麼整個執行會被報告為通過，所以靜音失敗唔會破壞 CI。
- **跳過嘅測試** 根本唔會運行，所以儀表板會繼續顯示測試最後一次實際執行嘅狀態——該快照可能已經幾星期舊。

### 運行測試 {#running-tests}

`tuist test` 會自動遵循兩種模式：

```sh
tuist test
```

跳過嘅測試會作為 `-skip-testing` 傳遞給 xcodebuild 並永遠唔會開始。靜音測試正常運行；如果佢哋失敗，失敗會喺最終構建狀態中被掩蓋。

要完全繞過隔離並運行所有內容，包括靜音同跳過嘅測試：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新運行你嘅分支添加嘅測試案例，每個案例喺全新進程中運行幾次，並報告結果為不穩定嘅案例。你會喺引入佢嘅拉取請求中看到新嘅不穩定測試，而唔係幾星期後。

如果一個測試案例喺過去 90 日內冇喺專案嘅預設分支上運行過 CI，或者冇喺已經合併到預設分支嘅 commit 上運行過，佢就被視為新案例。使用合併隊列時，隊列運行過嘅測試案例會喺隊列嘅 commit 合併後被識別，如果隊列丟棄咗佢，佢會保持为新。Commit 係透過 Tuist 喺 CI 上收集嘅 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史</.localized_link> 進行匹配嘅。

### 啟用佢

閘門預設係關閉嘅。設定一種模式：

- **`report`**：警告每個不穩定測試案例。執行仍然會根據自身結果退出。
- **`enforce`**：不穩定測試案例會令執行失敗，退出碼同失敗測試一樣。

喺兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 都唔會跳過包含新不穩定測試案例嘅測試目標。該目標會再次運行，閘門會再次對測試案例進行壓力測試，直到佢通過所有重新運行為止。

先用 `report` 幾星期，睇下 `enforce` 會攔截啲乜嘢。

將佢放喺透傳參數之前，或者設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據不同 CI 流水線變更模式：

```sh
tuist test --stress-new-tests report
```

### 每個測試重新運行嘅次數

取決於測試案例喺第一次運行時花費嘅時間：

| 第一次運行 | 重新運行次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 唔會重新運行 |

重新運行會重用第一次運行構建嘅內容。運行會喺達到 200 個測試案例或 10 分鐘時停止（以先到者為準），並說明觸發咗邊個限制。

### 閘門唔會運行嘅情況

- 第一次運行已經失敗。請先修復嗰啲測試。
- 專案冇預設分支，或者仲未喺上面運行過任何 CI。
- 超過 30% 嘅專案測試案例看起來係新嘅。重新運行咁多案例會花太多時間，唔值得。如果你嘅專案啱啱開始向 Tuist 報告數據，或者經過一次移動咗大量測試嘅重命名後，可能會出現呢種情況。

## Slack 通知 {#slack-notifications}

透過喺你嘅 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警報</.localized_link>，當測試變得不穩定時立即收到通知。

## 查詢不穩定同隔離狀態 {#querying}

### CLI

`tuist test case` 命令樹展示咗 Tuist 追蹤關於測試案例嘅所有信息：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有呢啲命令都接受 `--json` 以便腳本化。

### REST API

同樣嘅數據可以透過 HTTP 獲取——請參閱 API 參考中嘅 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整嘅路由、過濾器同響應字段列表。要更改測試案例嘅狀態（標記或取消標記為不穩定、靜音、跳過），請發送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並攜帶 `is_flaky` 或 `state`。同樣嘅更改亦可透過 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具實現。
