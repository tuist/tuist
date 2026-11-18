---
{
  "title": "發布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本（RC）及穩定版渠道發布 CLI，以及如何將團隊固定於可信賴的發布線。"
}
---

# 發布渠道 {#release-channels}

Tuist CLI 透過三個渠道發布，各自提供不同嘅穩定性保證。推薦安裝 **stable** 渠道，更新節奏較慢：每次有新功能合併時並唔會自動升級，所以升級不再意味著要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 渠道運行每次提交嘅構建，而 **release candidate** 渠道則讓團隊喺某個版本線成為穩定版之前進行充分測試。

## 當前發布 {#live-release-status}

穩定版推廣定於每週一 UTC 時間 06:00 進行。成功推廣後，下一個候選發布版將從 `main` 分支切出，隨後嘅 canary 版本會轉移到下一個次要版本。請參閱 <.localized_link href="/cli/release/calendar">發布日曆</.localized_link> 以查看即將到來嘅窗口同最近發布，包括補丁同回溯修復。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 默認解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交到 `main` | 否 — 需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，測試約 1 週 | 否 — 需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨測試後，每週一推廣 | **是** |

Canary 同候選發布版構建會作為預發布版發布。Mise 同 Homebrew 等工具喺解析 `latest`、全新安裝或鎖定版本線時會排除預發布版，因此除非你明確要求，否則唔會安裝到呢些版本。

### Canary {#canary}

每次提交到 `main` 都會發布一個 canary 版本。Canary 始終代表 **下一個未發布嘅次要版本**：一旦某個版本線被切出用於發布，`main` 就會推進到下一個次要版本（例如，從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。如果你係早期採用者，想要最早嘅信號，或者想喺修復進入穩定版之前驗證你報告或貢獻嘅修復是否符合預期，Canary 就係合適嘅渠道。

### Release candidate {#release-candidate}

當某個次要版本準備好發布時，其版本線會被凍結到受保護嘅 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 形式發布。該版本線處於功能凍結狀態；只會揀選關鍵修復同回歸修復，每個被接受嘅修復都會遞增 RC 版本號（`-rc.2`、`-rc.3`、…）。經過乾淨嘅測試期後，該版本線會被推廣為穩定版。

### Stable {#stable}

Stable 係推薦渠道，亦係所有文檔指向嘅渠道。穩定版次要版本（`X.Y.0`）僅喺候選發布版經過乾淨測試後才會發布，並且當新功能合併到 `main` 時，它並**不會**自動推進。穩定版版本線上嘅補丁（`X.Y.1`、`X.Y.2`、…）只包含回溯修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（推薦）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 始終安裝最新穩定版；預發布版唔會通過 formula 分發。

## 推薦策略 {#recommended-strategy}

1. **鎖定到一個穩定版本線**，例如 `tuist@4.200`。該版本線只接收回溯修復，絕無新功能，因此日常升級風險較低。
2. **有意識地採用新功能。** 當你準備好迎接下一個次要版本時，先喺候選發布渠道進行測試，然後將你嘅鎖定版本移動到新嘅穩定版本線。
3. 如果你係想要最早信號嘅早期採用者，可以喺非關鍵環境中**嘗試 canary**。

## 支持同回溯修復 {#support-and-backports}

任何時候都積極維護兩個穩定版本線：

| 版本線 | 接收 |
| --- | --- |
| 當前（`X.Y.x`） | 回歸問題同安全修復 |
| 上一個（`X.(Y-1).x`） | 僅限關鍵同安全修復 |
| 更舊版本 | 無 — 請升級至受維護嘅版本線 |

修復首先會合併到 `main`（canary）。回歸問題同安全修復會被回溯到當前穩定版本線，而上一個版本線僅接收關鍵同安全修復。其他錯誤修復不會被回溯；它們會隨下一個次要版本發布。當新版本線被推廣為穩定版時，原本嘅「當前」版本線會變成「上一個」，而原本嘅「上一個」版本線則停止接收回溯修復。

無論使用邊個渠道，Tuist 伺服器都與過去 3 個月內發布嘅任何 CLI 保持<.localized_link href="/cli/compatibility">兼容</.localized_link>，因此只要你喺該期間內進行升級，鎖定到穩定版本線就不會令你超出支持範圍。
