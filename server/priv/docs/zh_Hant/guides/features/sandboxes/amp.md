---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes 上於 Linux 或 macOS 執行你的 Amp 工作區 orb，或使用 Tuist Mac 外掛程式為任何 Amp 執行緒提供 Mac 以進行 Xcode 建置。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯絡我們，為你的帳號申請存取權限。

[Amp](https://ampcode.com) 會在一個 [orb](https://ampcode.com/docs/orbs)（已檢出該執行緒倉庫的機器）中執行每個執行緒的工具。Tuist 可以作為你 Amp 工作區的 [自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的執行緒都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中執行，支援 Linux 或 macOS。你無需自行執行或託管任何服務。

若要讓執行緒保留在目前的 orb 上，並僅在 Mac 上建置、測試及執行 Apple 平台程式碼，請改用 [Tuist Mac 外掛程式](#remote-mac)。

## 連接 Amp {#connect}

你需要同時是 Amp 工作區與 Tuist 帳號的管理員。

1. 在 Amp 中，開啟工作區的 **Settings → Orbs**，點擊 **Add Orb Provider**，並為其命名，例如 `tuist`。成員會依此名稱選擇提供者。複製 `aop_live_…` token；Amp 僅顯示一次。
2. 在 Amp 的提供者 **Edit** 對話框中，新增你想要提供的 **Orb types** 並選擇預設值。Linux 類型對應於 [Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs) 的記憶體規格。每種類型保證每 GiB 記憶體配備四分之一個 vCPU，並在機器有空閒核心時突發至 16 個 vCPU（參見 <.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link>）：

   | 類型 | 規格 |
   | --- | --- |
   | `linux` | Linux，8 GiB RAM，2 個保證 vCPU |
   | `linux-tiny` | Linux，2 GiB RAM，0.5 個保證 vCPU |
   | `linux-small` | Linux，4 GiB RAM，1 個保證 vCPU |
   | `linux-medium` | 同 `linux` |
   | `linux-large` | Linux，16 GiB RAM，4 個保證 vCPU |
   | `linux-xxlarge` | Linux，32 GiB RAM，8 個保證 vCPU |
   | `linux-3xlarge` | Linux，44 GiB RAM，11 個保證 vCPU |
   | `macos` | macOS（預設 Xcode），8 vCPU，8 GiB RAM |
   | `macos-xcode-<version>` | macOS（搭載該 [Xcode](#xcode)），8 vCPU，8 GiB RAM |

   Linux 類型擁有 10 GB 工作區空間，macOS 類型則為 30 GB。

3. 在 Tuist 中，開啟帳號儀表板的 **Sandboxes**，點擊 Amp 卡片上的 **Connect**，並貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示 **Connected**。一個 Tuist 帳號服務一個提供者。任何能在 Amp 中使用該提供者的使用者，其 orb 將在已連接的 Tuist 帳號上執行並計費。若要停止，請點擊卡片上的 **Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新建執行緒介面中，點擊 **Orb**，在 **Self-Hosted** 下選擇 Tuist 提供者，並挑選類型，例如需要較少資源的倉庫可選 `linux-small`（低於 `linux`），需要較多資源則選 `linux-large`。透過 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保留其 orb 類型。若未指定類型，則使用提供者的預設值。若要為每個新執行緒使用同一類型，請在 Amp 的 **Settings → Orbs** 中，於 **Default Orb** 下選擇提供者及其類型。

### 選擇 Xcode {#xcode}

`macos` 會執行預設的 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>。若要使用其他版本，請新增以其命名的 orb 類型，並將點號替換為連字號：`macos-xcode-26-1-1` 執行 Xcode 26.1.1，`macos-xcode-27-0` 執行 Xcode 27.0。為每個倉庫鎖定的 Xcode 新增對應類型，並像其他類型一樣為每個執行緒挑選：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

若 Tuist 未提供某 Xcode 版本，針對該版本的類型在新 orb 啟動時會失敗。已在該類型上啟動的 orb，即使 Tuist 停止提供該 Xcode，仍會繼續恢復執行。

Amp 會複製倉庫、執行你的 `.agents/setup` 腳本並設定 Git 憑證，這與處理每個 orb 的方式相同。每個 orb 也能讀取你帳號的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當執行緒進入閒置狀態時，Amp 會暫停其 orb。下一則訊息會恢復它，且檔案保持完整。

- **Linux：** 執行中的程序在暫停後仍會存活。長時間暫停的 orb 會移至歸檔儲存空間，並在收到下一則訊息時恢復，但不包含其程序。Linux orb 會保留其檔案，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 暫停或處於錯誤狀態達 7 天的 orb 會被刪除。執行緒的下一則訊息會啟動全新的 orb，且 Amp 會再次執行 `.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

若 orb 保持閒置而 Amp 未將其暫停（例如從未收到暫停指令），則在十分鐘後幾乎不使用 CPU 的情況下將其暫停。

## 從任何 Amp 執行緒使用 Mac {#remote-mac}

Tuist Mac 外掛程式能讓 Amp 執行緒獲得具備 Xcode、iOS 模擬器與 Homebrew 的 macOS sandbox，同時執行緒仍在原位執行（例如在 Amp 自身的 Linux orb 上）。向 Amp 指派工作，它會在需要時啟動 Mac：

> 在設定畫面新增深色模式切換按鈕，在 iOS 模擬器中執行應用程式，並向我顯示截圖。

Amp 會在原處繼續編輯程式碼。在 Mac 上執行每個命令之前，外掛程式會執行 `tuist sandbox sync`，複製 Git 未忽略的檔案（無論是否已提交），之後僅複製變更過的檔案。Mac 產生的建置產物與其他被忽略的檔案會保留在該處，因此建置能保持增量。外掛程式會新增這些工具，以及一個 `remote-mac` 技能，用於告知 Amp 何時及如何使用它們：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 建立執行緒的 Mac，或重複使用並同步 |
| `tuist_mac_shell` | 同步後，在 Mac 上執行命令 |
| `tuist_mac_screenshot` | 在執行緒中顯示模擬器或螢幕畫面 |
| `tuist_mac_download` | 將檔案複製回來，例如已建置的 `.app` |
| `tuist_mac_stop` | 刪除執行緒的 Mac |

Mac 本身沒有 Tuist CLI：首次同步後，Amp 會在倉庫根目錄執行 `mise install` 以安裝專案指定的 Tuist 版本，而 `tuist_mac_shell` 會將 mise 的 shims 加入 `PATH`。Mac 上的每個命令都會使用 Tuist 4.218.0 或更新版本自行<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登入你帳號的快取</.localized_link>；若使用 4.215.0 至 4.217.x 版本，Amp 會先執行 `tuist auth login`。

一個執行緒使用一台 Mac。Amp 會將倉庫指定的 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例如在 `.xcode-version` 中設定）傳遞給 `tuist_mac_start`，或者你可以指定版本（「使用 Xcode 26.1.1」）；若未指定，Mac 會執行預設版本。Mac 會保留其 Xcode，因此切換版本意味著停止當前 Mac 並啟動另一台。Tuist 會在閒置時將其暫停，下一個命令則會恢復執行。任務完成後，Amp 會將其刪除；遺留的 Mac 在暫停 14 天後會被刪除。Mac 會像其他 sandbox 一樣計入你的 Tuist 帳號用量。

### 設定步驟 {#remote-mac-setup}

1. **安裝外掛程式。** 它只有一個檔案：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要讓 Amp 工作區中的所有成員都能使用，工作區管理員需在執行緒中要求 Amp：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入我們工作區的外掛程式。

   Amp 會將其提交至工作區的 [外掛程式倉庫](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前詢問確認。若只想為自己安裝，請改為要求「my personal plugins」，或將檔案儲存為倉庫中的 `.amp/plugins/tuist-mac.ts` 以僅在該處使用。此外掛程式為複本：若要更新，請要求 Amp 從相同 URL 取代為最新版本。
2. **安裝 Tuist CLI** 於 Amp 執行環境中。在 orbs 上，將其加入倉庫的 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本，例如 `mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳號的 sandboxes。** 在 orbs 上，依照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 所述，將你的 Amp 工作區連接至 Tuist 帳號。Orbs 隨後會自行登入並存取 sandboxes。在其他環境（例如 Linux 機器上的 Amp CLI），請以帳號成員身分執行 `tuist auth login`，或將 `TUIST_MAC_TOKEN` 設定為具備 `account:sandboxes:write` 權限範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳號令牌</.localized_link>，並加上 `ci` 以便 Mac 使用快取。外掛程式會將 `TUIST_MAC_TOKEN` 傳遞給 CLI 以取代 `TUIST_TOKEN`，因此當你的 orbs 已擁有不具备該權限範圍的 `TUIST_TOKEN` 時，也需設定此變數。
4. **指定要使用的帳號**，若倉庫中沒有包含 `project = "<account>/<project>"` 的 `tuist.toml`。在 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳號資訊。請在 Amp 專案的環境變數中將 `TUIST_MAC_ACCOUNT` 設定為你的帳號代號。若未設定，Amp 會將 `Tuist.swift` 的 `fullHandle` 傳遞給 `tuist_mac_start`。

CLI 僅透過 `tuist.dev` 連線至 Mac，因此限制網路存取的環境需允許該網域。若要使用不在 `PATH` 中的 CLI，請將 `TUIST_MAC_CLI` 設定為其路徑。

不支援 Amp 外掛程式的代理程式（例如 Claude Code 或 Cursor）可以透過 Tuist MCP 伺服器與 CLI 達成相同效果，詳情請參閱 <.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理程式在 Mac 上建置</.localized_link>。

### 使用 Tuist Macs 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 也有自己的雲端 Mac，即 [macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前針對加入等候名單的工作區提供測試版。當執行緒可以同時啟動兩者時，Amp 的內建指示會將 macOS 工作送至其 satellites，因此很少選擇使用此外掛程式。若要讓執行緒使用 Tuist Macs，請執行下列其中一項操作：

- **為自己關閉 macOS Satellites。** 每位成員可在 Amp 的 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 下的 **Mac Satellites** 中將其關閉。
- **為工作區關閉它們。** 當工作區的 orbs [在 Tuist 上執行](#connect) 時，工作區管理員可在 Amp 工作區設定的 **Orbs** 下，將 **Where Orbs Run** 設定為 **Self-Hosted Only**。此時代理程式無法啟動 Amp 託管的 satellites，但成員也無法使用 Amp 內建的 orbs，因此僅在所有執行緒都運行於你自己的 orb 提供者時才執行此操作。
- **要求使用 Tuist Macs。** 在提示詞中加入「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或加入 Amp 工作區設定中的代理程式指引，讓每個執行緒都遵循此規則。
