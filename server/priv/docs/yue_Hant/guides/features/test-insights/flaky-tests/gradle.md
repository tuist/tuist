---
{
  "title": "Gradle 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理並隔離 Gradle 專案中的不穩定測試。"
}
---
# Gradle 不穩定測試 {#gradle-flaky-tests}

不穩定測試係指喺相同代碼下多次執行時，會產生唔同結果（通過或失敗）嘅測試。佢哋會削弱你對測試套件嘅信任，並浪費開發人員排查誤報失敗嘅時間。Tuist 會自動偵測不穩定測試，並幫你隨時間追蹤佢哋。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測點樣運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試嘅結果。如果一個測試喺某啲嘗試中失敗，但喺其他嘗試中通過，佢就會被標記為不穩定。

你可以使用 [Test Retry plugin](https://github.com/gradle/test-retry-gradle-plugin) 或類似機制來重新運行失敗嘅測試。Tuist 會偵測到嗰啲喺某啲嘗試中通過、但喺其他嘗試中失敗嘅測試。

將外掛程式加入到你嘅 `build.gradle.kts`：

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使冇測試重試，Tuist 都可以透過比較同一個 commit 同同一個 Gradle 專案喺唔同 CI 執行中嘅結果，嚟偵測不穩定測試。如果一個測試喺某次 CI 執行中通過，但喺同一個 commit 同專案嘅另一次執行中失敗，兩次執行都會被標記為不穩定。

Gradle 專案係比較鍵嘅一部分，因為同一個測試喺唔同專案中可能會以確定性但唔同嘅方式表現——例如，一個共享測試類別用唔同依賴編譯，或者喺唔同模組 fixture 上運行。同一個 commit 喺唔同 Gradle 專案上嘅兩次執行會被視為獨立嘅執行變體，唔會互相標記為不穩定。

這對於捕捉嗰啲失敗頻率唔足以被重試捕捉、但仍然導致間歇性 CI 失敗嘅不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測同清除係透過專案上嘅 **自動化警報** 進行。每個專案都會有一個預設嘅「不穩定測試偵測」自動化，其 *觸發器* 會將測試標記為不穩定，而其 *恢復* 則會喺測試經過設定嘅恢復窗口（預設 **14 天**）且冇再次觸發後清除標記。你可以喺 **Settings → Automations** 下編輯佢，以更改恢復窗口、更換恢復動作（例如同時解除隔離），或者完全禁用恢復，令測試保持標記為不穩定，直到你手動清除佢哋。

### 手動管理

你亦可以喺測試案例詳情頁面手動將測試標記為或取消標記為不穩定。這喺以下情況很有用：
- 你想喺修復已知不穩定測試期間確認佢
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，令佢喺你修復期間唔會阻塞 CI。預設情況下，這是一個 **手動操作**——你可以喺儀表板嘅測試案例詳情頁面進行隔離、解除隔離同切換模式——但你亦可以將其連接到 **Settings → Automations** 下嘅 **自動化警報**，令測試喺超過不穩定閾值時自動靜音（或跳過），並喺恢復時解除隔離。每次轉換，無論係手動定自動化，都會記錄喺測試案例嘅審計日誌中。

預設情況下，恢復會等待直到觸發條件不再成立，所以測試會保持隔離狀態，直到其舊嘅不穩定執行離開觸發窗口。若要更快恢復，請將 **Recover when** 設置為 **No new flaky runs**：測試會喺恢復窗口（天數或執行次數）過去而冇新嘅不穩定執行後恢復，每次新嘅不穩定執行都會重新開始該等待，而恢復後只有新嘅不穩定執行會再次將其隔離。

被隔離嘅測試處於以下兩種模式之一：

- **Muted**：測試仍然運行，但外掛程式會設置 `ignoreFailures = true`，並且只喺非隔離失敗時重新使構建失敗。失敗仍然會輸入到不穩定測試偵測器，所以你可以繼續觀察測試而唔會破壞構建。選擇此模式用於你正在積極調查嘅測試。
- **Skipped**：外掛程式會透過 Gradle 嘅 `excludeTestsMatching` 過濾掉測試，令佢從不啟動。佢唔會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用佢。當測試損壞、緩慢，或者不穩定到運行佢只係浪費 CI 分鐘時，選擇此模式。

### 點解被隔離嘅測試會顯示為通過 {#quarantined-passing}

- **Muted tests** 仍然執行。一個失敗嘅靜音測試會喺測試案例執行中被記錄為 **failed** 並標記為不穩定——每個測試嘅狀態唔會被改寫。被覆蓋嘅係 **overall test run**：如果執行中每個失敗嘅測試案例都係靜音嘅，那麼整個執行會被報告為通過，所以靜音失敗唔會破壞 CI。
- **Skipped tests** 根本唔會運行，所以儀表板會繼續顯示測試最後一次實際執行嘅狀態——該快照可能已經係幾週前嘅。

### 啟用隔離 {#enabling-quarantine}

隔離會喺 CI 上 **自動啟用**（當設置咗 `CI` 環境變量時），並喺本地構建時禁用。外掛程式會喺每次測試任務之前從 Tuist 伺服器獲取被隔離測試嘅列表；靜音測試正常運行並屏蔽其失敗，跳過嘅測試則被過濾掉。

你可以喺你嘅 `settings.gradle.kts` 中明確控制這一點：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

當 `enabled` 未設置時，預設為自動偵測：喺 CI 上啟用，喺本地禁用。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新運行你嘅分支添加嘅測試案例，每個案例喺全新進程中運行幾次，並報告結果為不穩定嘅案例。你會喺引入佢嘅拉取請求上看到新嘅不穩定測試，而唔係幾週後。

當一個測試案例喺過去 90 天內冇喺專案嘅預設分支上運行過 CI，或者冇喺已合併到該分支嘅 commit 上運行過，佢就被視為新嘅。使用合併隊列時，隊列運行過嘅測試案例會喺隊列嘅 commit 合併後被知悉，如果隊列丟棄咗佢，佢會保持為新。Commit 係透過 Tuist 喺 CI 上收集嘅 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git history</.localized_link> 進行匹配。

### 啟用它

閘門預設係關閉嘅。設置一種模式：

- **`report`**：警告每個不穩定測試案例。執行仍然以其自身結果退出。
- **`enforce`**：不穩定測試案例會令執行失敗，並返回與測試失敗相同嘅退出代碼。

先用 `report` 幾星期，睇下 `enforce` 本來會攔截啲乜嘢。

喺 `settings.gradle.kts` 中聲明，或者設置 `TUIST_TEST_STRESS_NEW_TESTS` 以按 CI 流水線變更模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

同隔離唔同，呢個閘門冇針對 CI 嘅預設行為。如果冇設置 `mode`，佢喺任何地方都唔會運行。

### 每個測試重新運行嘅次數

取決於測試案例喺第一輪運行中所花嘅時間：

| 第一輪 | 重試次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 唔會重試 |

每次重試都係一個嵌套嘅 Gradle 構建，並過濾到該單一測試案例，所以每次重試都會獲得一個全新嘅測試 JVM。當達到 200 個測試案例或 10 分鐘時（以先到者為準），運行就會停止，並指出觸發咗邊個限制。

### 閘門唔會運行嘅情況

- 第一輪已經失敗。先修復嗰啲測試。
- 專案冇預設分支，或者仲未喺 CI 上運行過任何嘢。
- 超過 30% 嘅專案測試案例看起來係新嘅。重新運行咁多案例會得不償失。這通常發生喺剛開始向 Tuist 報告數據嘅專案，或者喺一次改名移動咗大量測試之後。

## Slack 通知 {#slack-notifications}

透過喺你嘅 Slack 集成中設置 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">flaky test alerts</.localized_link>，喺測試變得不穩定時立即收到通知。

## 查詢不穩定同隔離狀態 {#querying}

### CLI

`tuist test case` 命令樹展示咗 Tuist 追蹤關於測試案例嘅所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有呢啲命令都接受 `--json` 以便進行腳本編寫。

### REST API

同樣嘅數據可以透過 HTTP 獲取——請參閱 API 參考中嘅 [Test Cases endpoints](https://tuist.dev/api/docs#tag/test-cases) 以獲取完整嘅路由、過濾器同響應字段列表。要更改測試案例嘅狀態（標記或取消標記為不穩定、靜音、跳過），請發送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並帶上 `is_flaky` 或 `state`。同樣嘅更改亦可透過 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具進行。
