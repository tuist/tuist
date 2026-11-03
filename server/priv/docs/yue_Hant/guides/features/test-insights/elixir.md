---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Elixir 專案的測試，以監察測試效能。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 嘅 Hex 套件會喺每次測試執行之後上傳你 Elixir 專案嘅測試結果，令你可以直接喺 Tuist 儀表板睇到測試表現同不穩定測試。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 匯報你嘅測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出同退出碼都保持不變：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會喺測試執行完成時匯報；唔需要額外嘅測試 alias。

你可以喺 Tuist 儀表板存取你嘅測試洞察，並觀察佢哋隨時間嘅變化：

![Phoenix 應用程式嘅測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 嘅結果，包括：
- 個別測試嘅通過/失敗狀態同持續時間
- 每個測試所屬嘅模組同 `describe` 區塊
- 每次失敗嘅訊息同位置
- 跨多次執行偵測不穩定測試
- 分支同提交，以及喺持續集成環境中嘅提供者同執行
- 喺持續集成環境中，檢出嘅 [Git 歷史](#git-history)

Doctest 會好似其他測試一樣被匯報。使用 `--cover` 時，執行嘅行覆蓋率亦會上傳：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit formatter 進行匯報，該 formatter 會附加到你已經使用嘅 formatter 旁邊。如果你喺命令行傳遞 `--formatter`，Mix 會替換整個列表，導致執行唔會被匯報，任務會向你發出警告。

### Git 歷史 {#git-history}

喺持續集成環境中，套件亦會上傳檢出嘅提交歷史：提交 SHA、它們嘅父提交、提交日期，以及執行同其拉取請求基礎分支所在嘅分支。唔會上傳文件內容、提交訊息或作者。這讓 Tuist 知道哪些提交已合併到你嘅預設分支，例如合併隊列測試過嘅提交。套件會讀取檢出已有嘅歷史，如果檢出沒有基礎分支，則會向遠端查詢其最新提交 (`git ls-remote`)。除咗代碼覆蓋率 (`--cover`) 之外，它唔會獲取歷史。

| 變量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 唔會讀取或上傳任何 Git 歷史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 只讀取檢出，唔會聯繫遠端。 |

## 疑難排解 {#troubleshooting}

匯報永遠唔會改變你測試嘅結果：如果報告無法發送，執行會照常退出且唔會打印任何內容。要查看報告為何未發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
