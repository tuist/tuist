---
{
  "title": "發布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 如何透過 Canary、候選版本及穩定渠道發布 CLI，以及如何將團隊固定於你可信賴的發布線。"
}
---

# 發佈渠道 {#release-channels}

Tuist CLI 透過三個渠道發佈，每個渠道提供不同嘅穩定性保證。推薦安裝嘅係 **stable**，更新節奏較慢：佢唔會每次有新功能合併就升級，所以升級唔再意味著要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 上運行每次提交嘅構建，而 **release candidate** 渠道則讓團隊喺新版本成為穩定版之前進行充分測試。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 更新頻率 | 默認解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交到 `main` | 否 — 需明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，測試約 1 週 | 否 — 需明確選擇 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過充分測試後，每週一提升為穩定版 | **是** |

Canary 同 release candidate 構建會以預發佈版本形式發佈。Mise 同 Homebrew 等工具喺解析 `latest`、直接安裝或鎖定版本線時會排除預發佈版本，所以你只有喺明確請求時才會使用其中一個。

### Canary {#canary}

每次提交到 `main` 都會發佈一個 canary 版本。Canary 始終代表 **下一個未發佈嘅次版本**：一旦某個版本線被切出用於發佈，`main` 就會推進到下一個次版本（例如，從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。Canary 適合希望獲得最早信號嘅早期採用者，或者用於驗證你報告或貢獻嘅修復喺進入穩定版之前是否按預期工作。

### Release candidate {#release-candidate}

當一個次版本準備好發佈時，其版本線會被凍結到受保護嘅 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 形式發佈。該版本線功能凍結；只會揀選關鍵修復同回歸問題，每個接受嘅修復都會增加 RC 版本號（`-rc.2`、`-rc.3`、…）。經過充分測試後，該版本線會提升為穩定版。

### Stable {#stable}

Stable 係推薦渠道，亦係所有文檔指向嘅渠道。穩定次版本（`X.Y.0`）只有在 release candidate 經過充分測試後才會發佈，並且當新功能合併到 `main` 時，它 **不會** 自動推進。穩定版本線上嘅補丁版本（`X.Y.1`、`X.Y.2`、…）只包含回溯修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 [Mise](/en/guides/install-tuist)（推薦）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 始終安裝最新穩定版；預發佈版本不會透過 formula 分發。

## 推薦策略 {#recommended-strategy}

1. **鎖定到一個穩定版本線**，例如 `tuist@4.200`。該版本線只接收回溯修復，絕不包含新功能，因此日常升級風險較低。
2. **有意識地採用新功能。** 當你準備好使用下一個次版本時，先喺 release candidate 渠道進行測試，然後將你嘅鎖定版本移動到新嘅穩定版本線。
3. 如果你係希望獲得最早信號嘅早期採用者，可以喺非關鍵環境中 **嘗試 canary**。

## 支持同回溯修復 {#support-and-backports}

任何時候都積極維護兩個穩定版本線：

| 版本線 | 接收 |
| --- | --- |
| 當前（`X.Y.x`） | 回歸問題同安全修復 |
| 上一個（`X.(Y-1).x`） | 只限關鍵同安全修復 |
| 較舊版本 | 無 — 請升級到受維護嘅版本線 |

修復首先會合併到 `main`（canary）。回歸問題同安全修復會回溯到當前穩定版本線，而上一個版本線只接收關鍵同安全修復。其他錯誤修復不會回溯；它們會隨下一個次版本一併發佈。當新版本線提升為穩定版時，原本「當前」嘅版本線會變成「上一個」，而原本「上一個」嘅版本線則停止接收回溯修復。

無論使用哪個渠道，Tuist 伺服器都與過去 3 個月內發佈嘅任何 CLI 保持 [兼容](/en/cli/compatibility)，因此只要你喺該期間內升級，鎖定到穩定版本線就不會令你超出支持範圍。
