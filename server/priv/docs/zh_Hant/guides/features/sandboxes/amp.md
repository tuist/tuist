---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes（Linux 或 macOS）上執行 Amp 工作區的 orbs，或透過 Tuist Mac 外掛程式為任何 Amp 執行緒提供 Mac 以進行 Xcode 建置。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中留言，以申請你帳戶的存取權限。

[Amp](https://ampcode.com) 會在一個[orb](https://ampcode.com/docs/orbs)（已檢出該執行緒倉庫的機器）中執行每個執行緒的工具。Tuist 可以成為你 Amp 工作區的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的執行緒都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中執行，支援 Linux 或 macOS。你無需自行執行或託管任何服務。

若要讓你的執行緒保留在目前的 orb 上，並僅在 Mac 上建置、測試與執行 Apple 平台程式碼，請改用[Tuist Mac 外掛程式](#remote-mac)。

## 連接 Amp {#connect}

你需要同時是 Amp 工作區與 Tuist 帳戶的管理員。

1. 在 Amp 中，開啟工作區的**Settings → Orbs**，點擊**Add Orb Provider**，並為其命名，例如 `tuist`。成員會依此名稱選擇提供者。複製 `aop_live_…` 權杖；Amp 僅顯示一次。
2. 在 Amp 中提供者的**Edit**對話框中，新增你想要提供的**Orb types**並選擇預設值。Linux 類型對應[Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs)的記憶體規格。每個類型保證每 GiB 記憶體分配四分之一個 vCPU，並在機器有空閒核心時突發至 16 個 vCPU（參見<.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link>）：

   | 類型 | 規格 |
   | --- | --- |
   | `linux` | Linux，8 GiB RAM，2 個保證 vCPU |
   | `linux-tiny` | Linux，2 GiB RAM，0.5 個保證 vCPU |
   | `linux-small` | Linux，4 GiB RAM，1 個保證 vCPU |
   | `linux-medium` | 同 `linux` |
   | `linux-large` | Linux，16 GiB RAM，4 個保證 vCPU |
   | `linux-xxlarge` | Linux，32 GiB RAM，8 個保證 vCPU |
   | `linux-3xlarge` | Linux，44 GiB RAM，11 個保證 vCPU |
   | `macos` | macOS，搭載預設 Xcode，8 vCPU，8 GiB RAM |
   | `macos-xcode-<version>` | macOS，搭載該[Xcode](#xcode)，8 vCPU，8 GiB RAM |

   Linux 類型的工作區空間為 10 GB，macOS 類型為 30 GB。

3. 在 Tuist 中，於你帳戶的儀表板開啟**Sandboxes**，點擊 Amp 卡片上的**Connect**，並貼上權杖。

當 Tuist 開始服務該提供者時，卡片會顯示**Connected**。一個 Tuist 帳戶服務一個提供者。任何能在 Amp 中使用該提供者的人，其 orb 將在已連接的 Tuist 帳戶上執行並計費。若要停止，請點擊卡片上的**Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新執行緒建立器中，點擊**Orb**，在**Self-Hosted**下選擇 Tuist 提供者，並挑選類型，例如需要較少資源的倉庫選 `linux-small`（低於 `linux`），需要較多資源則選 `linux-large`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保留其 orb 類型。若未指定類型，則使用提供者的預設值。若要讓每個新執行緒都使用同一類型，請在 Amp 的**Settings → Orbs**中，於**Default Orb**下選擇提供者及其類型。

### 選擇 Xcode {#xcode}

`macos` 會執行預設的<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>。若要使用其他版本，請新增以其命名的 orb 類型，並將點號替換為連字號：`macos-xcode-26-1-1` 執行 Xcode 26.1.1，`macos-xcode-27-0` 執行 Xcode 27.0。為你倉庫所固定的每個 Xcode 版本新增一個類型，並像其他類型一樣為每個執行緒挑選：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

若 Tuist 不提供某個 Xcode 版本，針對該版本的類型在新 orb 啟動時會失敗。若 orb 已在該版本上啟動，即使 Tuist 停止提供該 Xcode，它仍會繼續恢復執行。

Amp 會複製倉庫、執行你的 `.agents/setup` 腳本並設定 Git 憑證，這與對每個 orb 的操作相同。每個 orb 也能讀取你帳戶的 Tuist <.localized_link href="/guides/features/cache">快取</.localized_link>。

## 暫停與保留 {#retention}

當執行緒進入閒置狀態時，Amp 會暫停其 orb。下一則訊息會恢復它，且檔案保持完整。

- **Linux：** 執行中的程序在暫停後會保留。長時間暫停的 orb 會移至歸檔儲存空間，並在收到下一則訊息時恢復，但不包含其程序。Linux orb 會保留其檔案，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 若 orb 處於暫停或錯誤狀態達 7 天，將會被刪除。執行緒的下一則訊息會啟動全新的 orb，且 Amp 會再次執行 `.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要最多兩分鐘。

若 orb 保持閒置而 Amp 未將其暫停（例如因為暫停指令從未到達），十分鐘後它會被暫停，且幾乎不消耗 CPU。

## 從任何 Amp 執行緒使用 Mac {#remote-mac}

Tuist Mac 外掛程式能讓 Amp 執行緒獲得一個包含 Xcode、iOS 模擬器與 Homebrew 的 macOS sandbox，同時執行緒仍在原處執行（例如在 Amp 自有的 Linux orb 上）。向 Amp 指派工作，它會在需要時啟動一台 Mac：

> 在設定畫面新增深色模式切換按鈕，在 iOS 模擬器中執行應用程式，並向我顯示截圖。

Amp 會在原處繼續編輯程式碼。在 Mac 上執行每個命令之前，外掛程式會執行 `tuist sandbox sync`，複製所有未被 Git 忽略的檔案（無論是否已提交），之後則僅複製變更過的檔案。Mac 產生的建置產物與其他被忽略的檔案會保留在該處，因此建置能保持增量。外掛程式會新增這些工具，以及一個 `remote-mac` 技能，用以告知 Amp 何時及如何使用它們：

| 工具 | 功能說明 |
| --- | --- |
| `tuist_mac_start` | 建立或重複使用執行緒的 Mac，並進行同步 |
| `tuist_mac_shell` | 先同步，然後在 Mac 上執行命令 |
| `tuist_mac_screenshot` | 在執行緒中顯示模擬器或螢幕畫面 |
| `tuist_mac_download` | 將檔案複製回來，例如已建置的 `.app` |
| `tuist_mac_stop` | 刪除執行緒的 Mac |

Mac 上安裝了 Tuist CLI，並在專案透過 mise 鎖定版本時執行該版本；`tuist_mac_shell` 會將 mise 的 shims 置於 `PATH` 的最前面。Mac 上的每個命令都會使用 Tuist 4.218.0 或更新版本<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登入你帳戶的快取</.localized_link>；若使用 4.215.0 至 4.217.x 版本，Amp 會先執行 `tuist auth login`。

一個執行緒使用一台 Mac。Amp 會將倉庫鎖定的 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例如在 `.xcode-version` 中指定）傳遞給 `tuist_mac_start`，或者你可以指定版本（「使用 Xcode 26.1.1」）；若未指定，Mac 會執行預設版本。Mac 會保留其 Xcode，因此切換版本意味著停止當前 Mac 並啟動另一台。Tuist 會在閒置時暫停它，下一個命令則會恢復它。任務完成後 Amp 會將其刪除；遺留的 Mac 在暫停 14 天後會被刪除。Mac 與其他 sandbox 一樣，會計入你的 Tuist 帳戶用量。

### 設定步驟 {#remote-mac-setup}

1. **安裝外掛程式。** 它只有一個檔案：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要讓 Amp 工作區中的所有成員都能使用，工作區管理員需在執行緒中要求 Amp：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入我們的工作區外掛程式。

   Amp 會將其提交至工作區的 [外掛程式倉庫](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前徵求同意。若只想為自己安裝，請改為要求「my personal plugins」；或將檔案儲存為倉庫中的 `.amp/plugins/tuist-mac.ts`，僅在該倉庫中使用。此外掛程式為複本：若要更新，請要求 Amp 以相同 URL 的最新版本取代它。
2. **安裝 Tuist CLI** 到 Amp 執行的環境中。在 orb 上，將其加入倉庫的 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本，例如 `mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳戶的 sandboxes。** 在 orb 上，依照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 中的說明，將你的 Amp 工作區連接至 Tuist 帳戶。orb 隨後會自動登入並存取 sandboxes。在其他環境（例如 Linux 機器上的 Amp CLI），請以帳戶成員身分執行 `tuist auth login`，或將 `TUIST_MAC_TOKEN` 設為具備 `account:sandboxes:write` 權限範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>，並加上 `ci` 以便 Mac 使用快取。外掛程式會將 `TUIST_MAC_TOKEN` 傳遞給 CLI 以取代 `TUIST_TOKEN`，因此當你的 orb 已擁有不含該權限範圍的 `TUIST_TOKEN` 時，也需設定此變數。
4. **指定要使用的帳戶**（若倉庫中沒有包含 `project = "<account>/<project>"` 的 `tuist.toml`）。在 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳戶資訊。請在 Amp 專案的環境變數中將 `TUIST_MAC_ACCOUNT` 設為你的帳戶代號。若未設定，Amp 會將 `Tuist.swift` 中的 `fullHandle` 傳遞給 `tuist_mac_start`。

CLI 僅透過 `tuist.dev` 連線至 Mac，因此限制網路存取的環境需允許該網域。若要使用不在 `PATH` 中的 CLI，請將 `TUIST_MAC_CLI` 設為其路徑。

不支援 Amp 外掛程式的代理程式（例如 Claude Code 或 Cursor）可以透過 Tuist MCP 伺服器與 CLI 達成相同效果，詳情請參閱 <.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理程式在 Mac 上建置</.localized_link>。

### 使用 Tuist Macs 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 也有自己的雲端 Mac，即 [macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前對已加入等候名單的工作區開放測試。當執行緒可以同時啟動兩者時，Amp 的內建指令會將 macOS 工作發送給其 satellites，因此很少選擇使用此外掛程式。若要讓執行緒使用 Tuist Macs，請執行以下其中一項操作：

- **為自己關閉 macOS Satellites。** 每位成員可在 Amp 的 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 下的 **Mac Satellites** 中將其關閉。
- **為工作區關閉它們。** 當工作區的 orb [在 Tuist 上執行](#connect) 時，工作區管理員可在 Amp 工作區設定的 **Orbs** 下，將 **Where Orbs Run** 設為 **Self-Hosted Only**。此時代理程式無法啟動 Amp 託管的 satellites，但成員也無法使用 Amp 內建的 orbs，因此僅在所有執行緒都運行於你自己的 orb 提供者時才執行此操作。
- **要求使用 Tuist Macs。** 在提示詞中加入「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或將其加入 Amp 工作區設定中的代理程式指引，讓每個執行緒都遵循此規則。
