---
{
  "title": "發布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本及穩定渠道發佈 CLI，以及如何將團隊鎖定在值得信賴的版本線上。"
}
---

# 發佈渠道 {#release-channels}

Tuist CLI 透過三個渠道發佈，每個渠道提供不同嘅穩定性保證。推薦安裝 **stable** 版本，更新節奏較慢：唔會每次有新功能合併就升級，所以升級唔再等於要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 渠道運行每次提交嘅構建，而 **release candidate** 渠道則讓團隊喺新版本成為穩定版之前先行試用。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 更新頻率 | 預設解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交到 `main` | 否 — 需明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否 — 需明確選擇 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨試用後，每週一提升為穩定版 | **是** |

Canary 同 release candidate 構建會以預發佈版本形式發佈。Mise 同 Homebrew 等工具喺解析 `latest`、直接安裝或鎖定版本線時會排除預發佈版本，所以你只有喺明確指定時才會使用佢哋。

### Canary {#canary}

每次提交到 `main` 都會發佈一個 canary 版本。Canary 始終代表 **下一個未發佈嘅次版本**：一旦某個版本線被切出用於發佈，`main` 就會推進到下一個次版本（例如，從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。Canary 適合希望盡早獲得信號嘅早期採用者，或者想喺修復進入穩定版之前驗證你報告或貢獻嘅修復是否按預期運作。

### Release candidate {#release-candidate}

當一個次版本準備好發佈時，其版本線會被凍結到受保護嘅 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 形式發佈。該版本線功能已凍結；只會挑選關鍵修復同回歸問題，每個被接受嘅修復都會增加 RC 版本號（`-rc.2`、`-rc.3`、…）。經過乾淨嘅試用期後，該版本線會被提升為穩定版。

### Stable {#stable}

Stable 係推薦渠道，亦係所有文檔指向嘅版本。只有當 release candidate 經過乾淨試用後，穩定次版本（`X.Y.0`）才會發佈，並且當新功能合併到 `main` 時，它 **不會** 自動推進。穩定版本線上嘅補丁版本（`X.Y.1`、`X.Y.2`、…）只包含回溯修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（推薦）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 永遠安裝最新穩定版；預發佈版本唔會透過公式分發。

## 推薦策略 {#recommended-strategy}

1. **鎖定到一個穩定版本線**，例如 `tuist@4.200`。該版本線只接收回溯修復，絕無新功能，因此日常升級風險較低。
2. **有意識地採用新功能。** 當你準備好迎接下一個次版本時，先喺 release candidate 渠道試用，然後將你嘅鎖定版本移動到新嘅穩定版本線。
3. 如果你係希望盡早獲得信號嘅早期採用者，可以喺非關鍵環境中 **試用 canary**。

## 支援同回溯修復 {#support-and-backports}

任何時候都積極維護兩個穩定版本線：

| 版本線 | 接收 |
| --- | --- |
| 當前（`X.Y.x`） | 回歸問題同安全修復 |
| 上一個（`X.(Y-1).x`） | 只接收關鍵修復同安全修復 |
| 更舊版本 | 無 — 請升級到受維護嘅版本線 |

修復首先會合併到 `main`（canary）。回歸問題同安全修復會被回溯到當前穩定版本線，而上一個版本線只接收關鍵修復同安全修復。其他錯誤修復唔會回溯；佢哋會隨下一個次版本一齊發佈。當一個新版本線被提升為穩定版時，原本「當前」嘅版本線會變成「上一個」，而原本「上一個」嘅版本線就會停止接收回溯修復。

無論使用邊個渠道，Tuist server 都會與過去 3 個月內發佈嘅任何 CLI 保持 <.localized_link href="/cli/compatibility">兼容</.localized_link>，所以只要你喺該期間內升級，鎖定到穩定版本線就永遠唔會超出支援範圍。
