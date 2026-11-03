---
{
  "title": "發布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本及穩定版渠道發布 CLI，以及如何將團隊固定於你可信賴的發布線。"
}
---

# 發布渠道 {#release-channels}

Tuist CLI 透過三個渠道發布，各自提供不同嘅穩定性保證。推薦安裝係 **stable**，更新節奏較慢：唔會每次有新功能合併就推進版本，所以升級唔再等於要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 上執行每次提交嘅構建，而 **release candidate** 渠道則讓團隊喺新版本成為 stable 之前先行試用。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 發布頻率 | 預設解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交到 `main` | 否 — 需要明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每星期一從 `main` 切出，試用約 1 週 | 否 — 需要明確選擇 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨試用後，每星期一升級 | **是** |

Canary 同 release candidate 構建會以 prerelease 形式發布。Mise 同 Homebrew 等工具喺解析 `latest`、裸安裝或鎖定分支時會排除 prerelease，所以你只有喺明確指定時才會使用佢哋。

### Canary {#canary}

每次提交到 `main` 都會發布一個 canary 版本。Canary 始終代表 **下一個未發布嘅次要版本**：一旦某個分支被切出用於發布，`main` 就會推進到下一個次要版本（例如由 `4.200.0-canary.42` 變為 `4.201.0-canary.1`）。Canary 適合希望最早收到信號嘅早期採用者，或者想喺修復到達 stable 之前驗證你報告或貢獻嘅修復是否符合預期。

### Release candidate {#release-candidate}

當某個次要版本準備發布時，其分支會被凍結到受保護嘅 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 形式發布。該分支功能凍結；只會揀選關鍵修復同回歸問題，每個接受嘅修復都會遞增 RC 版本號（`-rc.2`、`-rc.3`、…）。經過乾淨嘅試用期後，該分支會升級為 stable。

### Stable {#stable}

Stable 係推薦渠道，亦係所有文件指向嘅渠道。只有當 release candidate 經過乾淨試用後，stable 次要版本（`X.Y.0`）才會發布，而且當新功能合併到 `main` 時，它並**不會**自動推進。Stable 分支上嘅補丁版本（`X.Y.1`、`X.Y.2`、…）只包含回溯修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 [Mise](/en/guides/install-tuist)（推薦）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 永遠安裝最新嘅 stable 版本；prerelease 不會透過 formula 分發。

## 推薦策略 {#recommended-strategy}

1. **鎖定到一個 stable 分支**，例如 `tuist@4.200`。該分支只接收回溯修復，絕無新功能，因此日常升級風險較低。
2. **有意識地採用新功能。** 當你準備好迎接下一個次要版本時，先喺 release candidate 渠道試用，然後將你嘅鎖定轉移到新嘅 stable 分支。
3. 如果你係希望最早收到信號嘅早期採用者，可以喺非關鍵環境中**嘗試 canary**。

## 支援同回溯修復 {#support-and-backports}

任何時候都有兩個 stable 分支處於積極維護狀態：

| 分支 | 接收 |
| --- | --- |
| 當前（`X.Y.x`） | 回歸問題同安全修復 |
| 上一個（`X.(Y-1).x`） | 僅限關鍵修復同安全修復 |
| 更舊版本 | 無 — 請升級到受維護嘅分支 |

修復首先會合併到 `main`（canary）。回歸問題同安全修復會被回溯到當前 stable 分支，而上一個分支只接收關鍵修復同安全修復。其他錯誤修復不會被回溯；它們會隨下一個次要版本發布。當新分支被提升為 stable 時，原本「當前」嘅分支會變成「上一個」，而原本「上一個」嘅分支則停止接收回溯修復。

無論使用哪個渠道，Tuist server 都與過去 3 個月內發布嘅任何 CLI 保持[兼容](/en/cli/compatibility)，因此只要你喺該期間內升級，鎖定到 stable 分支就不會令你超出支援範圍。
