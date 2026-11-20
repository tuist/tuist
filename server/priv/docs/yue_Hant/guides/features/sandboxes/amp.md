---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上執行你 Amp workspace 嘅 orbs，或者透過 Tuist Mac plugin 為任何 Amp thread 提供 Mac 環境以進行 Xcode 建構。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開通存取權限。

[Amp](https://ampcode.com) 會在一個 [orb](https://ampcode.com/docs/orbs)（已檢出該 thread 儲存庫的機器）中執行每個 thread 的工具。Tuist 可以成為你 Amp workspace 的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的 thread 都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中運行，支援 Linux 或 macOS。你無需自行運行或託管任何服務。

若要讓你的 thread 保持在現有的 orbs 上，並只在 Mac 上編譯、測試和運行 Apple 平台代碼，請改用 [Tuist Mac 插件](#remote-mac)。

## 連接 Amp {#connect}

你需要同時是 Amp workspace 和 Tuist 帳戶的管理員。

1. 在 Amp 中，開啟 workspace 的 **Settings → Orbs**，點擊 **Add Orb Provider**，並為其命名，例如 `tuist`。成員會根據此名稱選擇提供者。複製 `aop_live_…` token；Amp 只會顯示一次。
2. 在 Amp 中提供者的 **Edit** 對話框中，添加你想提供的 **Orb types** 並選擇預設值。Linux 類型對應 [Amp 自有 orbs](https://ampcode.com/docs/orbs/sizes-and-costs) 的記憶體配置。每種類型保證每 GiB 記憶體配備四分之一個 vCPU，並在機器有空閒核心時突發至 16 個 vCPU（參見 <.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link>）：

   | 類型 | 規格 |
   | --- | --- |
   | `linux` | Linux，8 GiB RAM，2 個保證 vCPU |
   | `linux-tiny` | Linux，2 GiB RAM，0.5 個保證 vCPU |
   | `linux-small` | Linux，4 GiB RAM，1 個保證 vCPU |
   | `linux-medium` | 與 `linux` 相同 |
   | `linux-large` | Linux，16 GiB RAM，4 個保證 vCPU |
   | `linux-xxlarge` | Linux，32 GiB RAM，8 個保證 vCPU |
   | `linux-3xlarge` | Linux，44 GiB RAM，11 個保證 vCPU |
   | `macos` | macOS，搭載預設 Xcode，8 vCPU，8 GiB RAM |
   | `macos-xcode-<version>` | macOS，搭載該 [Xcode](#xcode)，8 vCPU，8 GiB RAM |

   Linux 類型擁有 10 GB workspace，macOS 類型為 30 GB。

3. 在 Tuist 中，開啟帳戶儀表板中的 **Sandboxes**，點擊 Amp 卡片上的 **Connect**，並貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示 **Connected**。一個 Tuist 帳戶服務一個提供者。任何能在 Amp 中使用該提供者的人，其運行的 orbs 將計入並收費至已連接的 Tuist 帳戶。若要停止，點擊卡片上的 **Disconnect**，或在 Amp 中關閉該提供者。

## 啟動 thread {#start-a-thread}

在 Amp 的新 thread 編輯器中，點擊 **Orb**，在 **Self-Hosted** 下選擇 Tuist 提供者，並選擇一種類型，例如對於需求低於 `linux` 的儲存庫選擇 `linux-small`，或對於需求更高的選擇 `linux-large`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

thread 會終身保持其 orb 類型。若未指定類型，則使用提供者的預設值。若要為每個新 thread 使用同一種類型，請在 Amp 的 **Settings → Orbs** 下的 **Default Orb** 中選擇提供者及其類型。

### 選擇 Xcode {#xcode}

`macos` 會運行預設的 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>。若要使用其他版本，請添加以其命名的 orb 類型，並將點號替換為連字號：`macos-xcode-26-1-1` 運行 Xcode 26.1.1，`macos-xcode-27-0` 運行 Xcode 27.0。為你的儲存庫鎖定的每個 Xcode 添加一個類型，並像其他類型一樣按 thread 選擇：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

若 Tuist 不提供某個 Xcode 對應的類型，當新 orb 啟動時會失敗。若 orb 已在該類型上啟動，即使 Tuist 停止提供該 Xcode，它仍會繼續恢復運行。

Amp 會克隆儲存庫，運行你的 `.agents/setup` 腳本並設置 Git 憑證，這與對每個 orb 的操作相同。每個 orb 還可以讀取你帳戶的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當 thread 進入閒置狀態時，Amp 會暫停其 orb。下一條訊息會恢復它，且文件保持完整。

- **Linux：** 運行中的進程在暫停後會保留。長時間暫停的 orb 會移至歸檔儲存，並在下一條訊息時恢復，但不包含其進程。Linux orbs 會保留其文件，直到 Amp 刪除該 thread 的 orb。
- **macOS：** 暫停或處於錯誤狀態達 7 天的 orb 會被刪除。thread 的下一條訊息會啟動一個全新的 orb，Amp 會再次運行 `.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

若 orb 保持閒置而 Amp 未將其暫停（例如因為從未收到暫停指令），十分鐘後它會被暫停，此時幾乎不消耗 CPU。

## 從任何 Amp thread 使用 Mac {#remote-mac}

Tuist Mac 插件為 Amp thread 提供一個帶有 Xcode、iOS 模擬器和 Homebrew 的 macOS sandbox，同時 thread 繼續在其原有位置運行，例如在 Amp 自己的 Linux orb 上。向 Amp 請求工作，它會在需要時啟動一台 Mac：

> 在設置螢幕添加深色模式切換按鈕，在 iOS 模擬器中運行應用程式，並向我顯示截圖。

Amp 會在其運行位置繼續編輯代碼。在 Mac 上執行每個命令之前，插件會運行 `tuist sandbox sync`，複製 Git 未忽略的文件（無論是否已提交），之後僅複製更改過的文件。Mac 創建的構建產物和其他被忽略的文件會保留在那裡，從而保持增量構建。插件添加了這些工具，以及一個 `remote-mac` skill，用於告訴 Amp 何時及如何使用它們：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 建立或重用 thread 的 Mac，並進行同步 |
| `tuist_mac_shell` | 同步後在 Mac 上執行命令 |
| `tuist_mac_screenshot` | 在 thread 中顯示模擬器或螢幕畫面 |
| `tuist_mac_download` | 將文件複製回來，例如已構建的 `.app` |
| `tuist_mac_stop` | 刪除 thread 的 Mac |

Mac 內置 Tuist CLI，當項目透過 mise 鎖定特定版本時會運行該版本；`tuist_mac_shell` 會將 mise 的 shims 置於 `PATH` 的最前面。Mac 上的每個命令都會使用 Tuist 4.218.0 或更高版本自行<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登入你帳戶的 cache</.localized_link>；若使用 4.215.0 至 4.217.x 版本，Amp 會先運行 `tuist auth login`。

一個 thread 使用一台 Mac。Amp 會將儲存庫鎖定的 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例如在 `.xcode-version` 中指定）傳遞給 `tuist_mac_start`，或者你可以要求指定版本（「使用 Xcode 26.1.1」）；若未指定，Mac 會運行默認版本。Mac 會保留其 Xcode，因此切換版本意味著停止當前 Mac 並啟動另一台。Tuist 會在閒置時暫停它，下一個命令會將其恢復。任務完成後 Amp 會將其刪除；遺留的 Mac 在暫停 14 天後會被刪除。Mac 會像其他 sandbox 一樣計入你的 Tuist 帳戶用量。

### 設置 {#remote-mac-setup}

1. **安裝插件。** 它只有一個文件：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要讓 Amp workspace 中的所有成員都能使用，workspace 管理員需在 thread 中向 Amp 請求：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 添加到我們的 workspace 插件中。

   Amp 會將其提交到 workspace 的 [plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前徵求同意。若只想為自己安裝，可改為請求「my personal plugins」，或將文件保存為儲存庫中的 `.amp/plugins/tuist-mac.ts` 以僅在該處使用。該插件是副本：若要更新，請要求 Amp 用同一 URL 的最新版本替換它。
2. **安裝 Tuist CLI** 到 Amp 運行的環境。在 orbs 上，將其添加到儲存庫的 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本中，例如 `mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳戶的 sandboxes。** 在 orbs 上，按照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 中的說明將你的 Amp workspace 連接到 Tuist 帳戶。Orbs 隨後會自動登入並訪問 sandboxes。在其他環境（例如 Linux 機器上的 Amp CLI），以帳戶成員身份運行 `tuist auth login`，或將 `TUIST_MAC_TOKEN` 設置為具有 `account:sandboxes:write` 權限範圍的 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並加上 `ci` 以便 Mac 使用 cache。插件會將 `TUIST_MAC_TOKEN` 傳遞給 CLI 以代替 `TUIST_TOKEN`，因此即使你的 orbs 已有不含該權限範圍的 `TUIST_TOKEN`，也需設置此變量。
4. **指定要使用的帳戶**（若儲存庫中沒有包含 `project = "<account>/<project>"` 的 `tuist.toml`）。在 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳戶信息。請在 Amp 項目的環境變量中將 `TUIST_MAC_ACCOUNT` 設置為你的帳戶句柄。若未設置，Amp 會將 `Tuist.swift` 中的 `fullHandle` 傳遞給 `tuist_mac_start`。

CLI 僅通過 `tuist.dev` 連接 Mac，因此限制網絡訪問的環境需允許該域名。若要使用不在 `PATH` 中的 CLI，請將 `TUIST_MAC_CLI` 設置為其路徑。

不支持 Amp 插件的代理（例如 Claude Code 或 Cursor）可以透過 Tuist MCP 服務器和 CLI 實現相同功能，詳情見 <.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理在 Mac 上構建</.localized_link>。

### 使用 Tuist Macs 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 也有自己的雲端 Mac，即 [macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前對加入等候名單的 workspace 處於測試階段。當 thread 可以同時啟動兩者時，Amp 的內置指令會將 macOS 工作發送到其 satellites，因此很少選擇該插件。若要讓 threads 使用 Tuist Macs，請執行以下操作之一：

- **為自己關閉 macOS Satellites。** 每個成員可在 Amp 的 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 下的 **Mac Satellites** 中將其關閉。
- **為 workspace 關閉它們。** 當你 workspace 的 orbs [在 Tuist 上運行](#connect) 時，workspace 管理員可在 Amp 的 workspace 設置中，將 **Where Orbs Run** 設為 **Self-Hosted Only**（位於 **Orbs** 下）。這樣代理就無法啟動 Amp 託管的 satellites，但成員也無法使用 Amp 內置的 orbs，因此僅在所有 threads 都運行在你自己的 orb 提供商上時才執行此操作。
- **要求使用 Tuist Macs。** 在提示詞中添加「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或將其添加到 Amp workspace 設置中的代理指導方針，以便每個 thread 都遵循。
