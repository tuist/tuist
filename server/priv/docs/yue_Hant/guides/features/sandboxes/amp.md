---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "喺 Tuist Sandboxes 上執行你 Amp workspace 嘅 orbs（支援 Linux 或 macOS），或者透過 Tuist Mac plugin 為任何 Amp thread 提供 Mac 環境以進行 Xcode 建構。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以申請帳戶存取權限。

[Amp](https://ampcode.com) 會在一個[orb](https://ampcode.com/docs/orbs)（已檢出該執行緒儲存庫的機器）中執行每個執行緒的工具。Tuist 可以成為你 Amp 工作區的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的執行緒都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中運行，支援 Linux 或 macOS。你無需自行運行或託管任何服務。

若要讓執行緒保留在目前的 orb 上，並只在 Mac 上建置、測試和運行 Apple 平台程式碼，請改用[Tuist Mac 外掛程式](#remote-mac)。

## 連接 Amp {#connect}

你需要同時具備 Amp 工作區和 Tuist 帳戶的管理員權限。

1. 在 Amp 中，開啟工作區的**Settings → Orbs**，點擊**Add Orb Provider**，並為其命名，例如`tuist`。成員會透過此名稱選擇提供者。複製`aop_live_…` token；Amp 只會顯示一次。
2. 在 Amp 提供者的**Edit**對話框中，新增你想要提供的**Orb types**並選擇預設值。Linux 類型對應[Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs)的大小：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區 |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB 工作區 |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB 工作區 |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區（與`linux`相同） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB 工作區 |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB 工作區 |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB 工作區 |
   | `macos` | macOS（搭載預設 Xcode） | 8 vCPU、8 GiB RAM、30 GB 工作區 |
   | `macos-xcode-<version>` | macOS（搭載指定 Xcode，例如 Xcode 26.1.1 對應`macos-xcode-26-1-1`） | 8 vCPU、8 GiB RAM、30 GB 工作區 |

3. 在 Tuist 中，開啟帳戶儀表板的**Sandboxes**，點擊 Amp 卡片上的**Connect**，並貼上 token。

當 Tuist 開始提供該提供者服務時，卡片會顯示**Connected**。一個 Tuist 帳戶對應一個提供者。任何能在 Amp 中使用該提供者的人，其運行的 orb 都會計入並向已連接的 Tuist 帳戶收費。若要停止，請點擊卡片上的**Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新執行緒編輯器中，點擊**Orb**，在**Self-Hosted**下選擇 Tuist 提供者，並挑選類型，例如對於需求低於`linux`的儲存庫選擇`linux-small`，或對於需求較高的選擇`linux-large`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保留其 orb 類型。若未指定類型，則使用提供者的預設值。若要為每個新執行緒使用同一類型，請在 Amp 的**Settings → Orbs**中的**Default Orb**下選擇提供者及其類型。

### 選擇 Xcode {#xcode}

`macos` 會運行預設的<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>。若要使用其他版本，請新增以其命名的 orb 類型，並將點號替換為連字號：`macos-xcode-26-1-1` 運行 Xcode 26.1.1，`macos-xcode-27-0` 運行 Xcode 27.0。為你的儲存庫鎖定的每個 Xcode 版本新增一個類型，並像其他類型一樣為每個執行緒選擇：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

若 Tuist 不提供某個 Xcode 版本的類型，當新 orb 啟動時會失敗。若 orb 已在該版本上啟動，即使 Tuist 停止提供該 Xcode，它仍會繼續恢復運行。

Amp 會複製儲存庫、執行你的`.agents/setup`腳本並設定 Git 憑證，這與處理每個 orb 的方式相同。每個 orb 也可以讀取你帳戶的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當執行緒閒置時，Amp 會暫停其 orb。下一則訊息會恢復它，且檔案完好無損。

- **Linux：** 運行中的進程在暫停後仍會存活。若 orb 被暫停很長時間，它會移至歸檔儲存空間，並在收到下一則訊息時恢復，但不包含其進程。Linux orb 會保留其檔案，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 若 orb 處於暫停或錯誤狀態達 7 天，就會被刪除。執行緒的下一則訊息會啟動一個全新的 orb，而 Amp 會再次運行`.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

若 orb 保持閒置而未被 Amp 暫停（例如因為從未收到暫停指令），它會在十分鐘後暫停，此時幾乎不消耗 CPU。

## 從任何 Amp 執行緒使用 Mac {#remote-mac}

Tuist Mac 外掛程式為 Amp 執行緒提供一個包含 Xcode、iOS 模擬器和 Homebrew 的 macOS sandbox，同時執行緒繼續在其原本的位置運行，例如在 Amp 自己的 Linux orb 上。向 Amp 指派工作，它會在需要時啟動 Mac：

> 在設定畫面新增深色模式切換按鈕，在 iOS 模擬器中運行應用程式，並向我顯示截圖。

Amp 會在其運行位置繼續編輯程式碼。在 Mac 上執行每個命令之前，外掛程式會運行`tuist sandbox sync`，這會複製 Git 未忽略的檔案（無論是否已提交），之後則只複製已變更的檔案。Mac 建立的建置產物和其他被忽略的檔案會留在那裡，因此建置保持增量進行。外掛程式新增了這些工具，以及一個告訴 Amp 何時及如何使用它們的`remote-mac`技能：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 建立執行緒的 Mac，或重複使用它，並進行同步 |
| `tuist_mac_shell` | 同步後，在 Mac 上運行命令 |
| `tuist_mac_screenshot` | 在執行緒中顯示模擬器或螢幕 |
| `tuist_mac_download` | 將檔案複製回來，例如已建置的`.app` |
| `tuist_mac_stop` | 刪除執行緒的 Mac |

Mac 沒有自己的 Tuist CLI：首次同步後，Amp 會在儲存庫根目錄運行`mise install`以安裝專案鎖定的 Tuist，而`tuist_mac_shell`會將 mise 的 shims 加入`PATH`。Mac 上的每個命令都會使用 Tuist 4.218.0 或更高版本自行<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登入你帳戶的快取</.localized_link>；若使用 4.215.0 至 4.217.x 版本，Amp 會先運行`tuist auth login`。

一個執行緒使用一台 Mac。Amp 會將儲存庫鎖定的<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例如在`.xcode-version`中指定）傳遞給`tuist_mac_start`，或者你可以要求特定版本（「使用 Xcode 26.1.1」）；若未指定，Mac 會運行預設版本。Mac 會保留其 Xcode，因此切換意味著停止它並啟動另一台。Tuist 會在它閒置時暫停，下一個命令會恢復它。Amp 會在任務完成後刪除它；遺留的 Mac 在暫停 14 天後會被刪除。Mac 會像其他 sandbox 一樣計入你的 Tuist 帳戶。

### 設定 {#remote-mac-setup}

1. **安裝外掛程式。** 它只有一個檔案：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要讓 Amp 工作區中的所有成員都能使用它，工作區管理員需在執行緒中要求 Amp：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入到我們的工作區外掛程式。

   Amp 會將其提交到工作區的[plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前詢問。若只想為自己安裝，請改為要求「my personal plugins」，或將檔案儲存為儲存庫中的`.amp/plugins/tuist-mac.ts`以僅在該處使用。此外掛程式是副本：若要更新，請要求 Amp 用來自相同 URL 的最新版本替換它。
2. **安裝 Tuist CLI**到 Amp 運行的位置。在 orb 上，將其添加到儲存庫的[`.agents/setup`](https://ampcode.com/docs/orbs/customizing)腳本中，例如`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳戶的 sandboxes。** 在 orb 上，按照<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>中的說明將你的 Amp 工作區連接到你的 Tuist 帳戶。orb 隨後會自行登入，並獲得訪問 sandboxes 的權限。在其他地方，例如 Linux 機器上的 Amp CLI，請以帳戶成員身份運行`tuist auth login`，或將`TUIST_MAC_TOKEN`設定為具有`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並加上`ci`以便 Mac 使用快取。外掛程式會將`TUIST_MAC_TOKEN`傳遞給 CLI 以取代`TUIST_TOKEN`，因此即使你的 orb 已經擁有沒有該範圍的`TUIST_TOKEN`，也請設定它。
4. **告訴它使用哪個帳戶**，如果儲存庫中沒有包含`project = "<account>/<project>"`的`tuist.toml`。在 Linux 上，CLI 無法從`Tuist.swift`讀取帳戶。在 Amp 專案的環境變數中將`TUIST_MAC_ACCOUNT`設定為你的帳戶句柄。若未設定，Amp 會將`Tuist.swift`的`fullHandle`傳遞給`tuist_mac_start`。

CLI 僅通過`tuist.dev`訪問 Mac，因此限制網絡訪問的環境需要僅允許該域名。若要使用不在`PATH`上的 CLI，請將`TUIST_MAC_CLI`設定為其路徑。

不支持 Amp 外掛程式的代理（例如 Claude Code 或 Cursor）可以通過 Tuist MCP 服務器和 CLI 執行相同操作，如<.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理在 Mac 上建置</.localized_link>中所述。

### 使用 Tuist Mac 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 也有自己的雲端 Mac，即[macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前針對加入等候名單的工作區處於測試階段。當執行緒可以同時啟動兩者時，Amp 的內建指令會將 macOS 工作發送到其 satellites，因此很少選擇此外掛程式。若要讓執行緒使用 Tuist Mac，請執行以下操作之一：

- **為自己關閉 macOS Satellites。** 每個成員可以在 Amp 的[Settings → Experimental Features](https://ampcode.com/settings/experimental-features)中的**Mac Satellites**下關閉它們。
- **為工作區關閉它們。** 當你的工作區的 orb [在 Tuist 上運行](#connect)時，工作區管理員可以在 Amp 的工作區設定中的**Orbs**下，將**Where Orbs Run**設定為**Self-Hosted Only**。這樣代理就無法啟動 Amp 託管的 satellites，但成員也無法使用 Amp 內建的 orb，因此僅在所有執行緒都在你自己的 orb 提供者上運行時才執行此操作。
- **要求使用 Tuist Macs。** 在提示詞中添加「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或將其添加到 Amp 工作區設定中的工作區代理指南，以便每個執行緒都遵循。
