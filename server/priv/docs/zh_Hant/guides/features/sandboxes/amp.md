---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "在 Tuist Sandboxes 上於 Linux 或 macOS 執行 Amp 工作區的 Orbs，或透過 Tuist Mac 外掛程式為任何 Amp 執行緒提供 Mac 以進行 Xcode 建置。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前採邀請制。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中留言，為你的帳號申請存取權限。

[Amp](https://ampcode.com)會在一個[orb](https://ampcode.com/docs/orbs)（已检出該執行緒儲存庫的機器）中執行每個執行緒的工具。Tuist 可以成為你 Amp 工作區的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的執行緒都會在自己的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>中執行，支援 Linux 或 macOS。你無需自行執行或託管任何服務。

若要讓執行緒保留在目前的 orb 上，並僅在 Mac 上建置、測試和執行 Apple 平台程式碼，請改用[Tuist Mac 外掛程式](#remote-mac)。

## 連接 Amp {#connect}

你需要同時是 Amp 工作區和 Tuist 帳號的管理員。

1. 在 Amp 中，開啟工作區的**Settings → Orbs**，點擊**Add Orb Provider**，並命名為例如 `tuist`。成員會依此名稱選擇提供者。複製 `aop_live_…` token；Amp 僅顯示一次。
2. 在 Amp 中提供者的**Edit**對話框中，新增你想要提供的**Orb types**並選擇預設值。Linux 類型對應於[Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs)的大小：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區 |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB 工作區 |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB 工作區 |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區（與 `linux` 相同） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB 工作區 |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB 工作區 |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB 工作區 |
   | `macos` | macOS（含 Xcode） | 8 vCPU、8 GiB RAM、10 GB 工作區 |

3. 在 Tuist 中，開啟帳號儀表板的**Sandboxes**，點擊 Amp 卡片上的**Connect**，並貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示**Connected**。一個 Tuist 帳號服務一個提供者。任何能在 Amp 中使用該提供者的人，其 orb 將在已連接的 Tuist 帳號上執行並計費。若要停止，請點擊卡片上的**Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新執行緒編輯器中，點擊**Orb**，在**Self-Hosted**下選擇 Tuist 提供者，並挑選類型，例如需要資源少於 `linux` 的儲存庫可選 `linux-small`，需要更多資源則選 `linux-large`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保留其 orb 類型。若未指定類型，將使用提供者的預設值。若要讓每個新執行緒使用同一類型，請在 Amp 的**Settings → Orbs**中，於**Default Orb**下選擇提供者及其類型。

Amp 會複製儲存庫、執行你的 `.agents/setup` 腳本並設定 Git 憑證，這與處理每個 orb 的方式相同。每個 orb 也能讀取你帳號的 Tuist <.localized_link href="/guides/features/cache">快取</.localized_link>。

## 暫停與保留 {#retention}

當執行緒閒置時，Amp 會暫停其 orb。下一則訊息會恢復它，且檔案保持完整。

- **Linux：** 執行中的程序在暫停後仍會保留。長時間暫停的 orb 會移至歸檔儲存空間，並在收到下一則訊息時恢復，但不包含其程序。Linux orb 會保留其檔案，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 處於暫停或錯誤狀態達 7 天的 orb 會被刪除。執行緒的下一則訊息會啟動全新的 orb，且 Amp 會再次執行 `.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

若 orb 閒置而 Amp 未將其暫停（例如因為從未收到暫停指令），則在幾乎不使用 CPU 的情況下，十分鐘後會被暫停。

## 從任何 Amp 執行緒使用 Mac {#remote-mac}

Tuist Mac 外掛程式為 Amp 執行緒提供包含 Xcode、iOS 模擬器與 Homebrew 的 macOS 沙盒，同時執行緒仍在其原本的位置繼續執行，例如在 Amp 自有的 Linux orb 上。請 Amp 執行工作，它會在需要時啟動 Mac：

> 在設定畫面新增深色模式切換按鈕，在 iOS 模擬器中執行應用程式，並向我顯示截圖。

Amp 會在其執行位置持續編輯程式碼。在 Mac 上執行每個指令之前，外掛程式會執行 `tuist sandbox sync`，複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製變更過的檔案。Mac 建立的建置產物與其他被忽略的檔案會保留在該處，因此建置能保持增量。外掛程式會加入這些工具，以及一個 `remote-mac` 技能，告訴 Amp 何時以及如何運用它們：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 建立執行緒的 Mac，或重複使用並同步 |
| `tuist_mac_shell` | 先同步，然後在 Mac 上執行指令 |
| `tuist_mac_screenshot` | 在執行緒中顯示模擬器或螢幕畫面 |
| `tuist_mac_download` | 將檔案複製回來，例如已建置的 `.app` |
| `tuist_mac_stop` | 刪除執行緒的 Mac |

一個執行緒使用一台 Mac。Tuist 會在閒置時將其暫停，下一個指令則會恢復它。Amp 會在任務完成後將其刪除；若 Mac 被遺留，會在暫停 14 天後刪除。Mac 會像其他沙盒一樣計入你的 Tuist 帳號用量。

### 設定 {#remote-mac-setup}

1. **安裝外掛程式。** 它只有一個檔案：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要讓 Amp 工作區中的所有成員都能使用，工作區管理員需在执行緒中要求 Amp：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入我們的工作區外掛程式。

   Amp 會將其提交至工作區的[外掛程式儲存庫](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前徵求同意。若只想為自己安裝，請改為要求「my personal plugins」；或者將檔案儲存為儲存庫中的 `.amp/plugins/tuist-mac.ts`，僅在該處使用。此外掛程式為副本：若要更新，請要求 Amp 以相同 URL 的最新版本取代它。
2. **安裝 Tuist CLI**於 Amp 執行的位置。在 orb 上，將其加入儲存庫的 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本，例如 `mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳號的沙盒。** 在 orb 上，依照<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>所述，將你的 Amp 工作區連接至 Tuist 帳號。orb 隨後會自行登入，並取得沙盒存取權。在其他環境（例如 Linux 機器上的 Amp CLI），請以帳號成員身分執行 `tuist auth login`，或將 `TUIST_MAC_TOKEN` 設為具備 `account:sandboxes:write` 權限範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳號 token</.localized_link>。外掛程式會將 `TUIST_MAC_TOKEN` 傳遞給 CLI 以取代 `TUIST_TOKEN`，因此當你的 orb 已擁有不具該權限範圍的 `TUIST_TOKEN` 時，也請設定它。
4. **指定要使用的帳號**（若儲存庫中沒有包含 `project = "<account>/<project>"` 的 `tuist.toml`）。在 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳號。請在 Amp 專案的環境變數中，將 `TUIST_MAC_ACCOUNT` 設為你的帳號代號。若未設定，Amp 會將 `Tuist.swift` 的 `fullHandle` 傳遞給 `tuist_mac_start`。

CLI 僅透過 `tuist.dev` 連線至 Mac，因此限制網路存取的環境只需允許該網域。若要使用不在 `PATH` 中的 CLI，請將 `TUIST_MAC_CLI` 設為其路徑。

不支援 Amp 外掛程式的代理程式（例如 Claude Code 或 Cursor）可以透過 Tuist MCP 伺服器與 CLI 達成相同效果，詳見<.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理程式在 Mac 上建置</.localized_link>。

### 使用 Tuist Mac 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 也有自己的雲端 Mac——[macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前對已加入等候名單的工作區開放測試。當執行緒可以同時啟動兩者時，Amp 的內建指示會將 macOS 工作導向其 satellites，因此很少會選擇此外掛程式。若要讓執行緒使用 Tuist Mac，請執行下列其中一項操作：

- **為自己關閉 macOS Satellites。** 每位成員可在 Amp 的[Settings → Experimental Features](https://ampcode.com/settings/experimental-features)中，於**Mac Satellites**下將其關閉。
- **為工作區關閉它們。** 當你的工作區 orb [在 Tuist 上執行](#connect)時，工作區管理員可在 Amp 工作區設定的**Orbs**下，將**Where Orbs Run**設為**Self-Hosted Only**。如此一來，代理程式便無法啟動由 Amp 託管的 satellites，但成員也無法使用 Amp 內建的 orb，因此僅在所有執行緒都執行在你自己的 orb 提供者上時才建議這麼做。
- **要求使用 Tuist Mac。** 在提示詞中加入「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或將其加入 Amp 工作區設定中的代理程式指引，讓每個執行緒都遵循。
