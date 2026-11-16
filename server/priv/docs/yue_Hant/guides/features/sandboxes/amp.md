---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上執行你 Amp workspace 嘅 orbs，或者透過 Tuist Mac 插件為任何 Amp thread 提供 Mac 環境以進行 Xcode 建構。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 同 macOS）目前只接受邀請。[聯絡我哋](mailto:contact@tuist.dev)或者喺[社區 Slack](https://slack.tuist.dev)通知我哋，為你嘅帳戶申請存取權限。

[Amp](https://ampcode.com) 會喺 [orb](https://ampcode.com/docs/orbs)（一部已檢出該 thread 儲存庫嘅機器）入面執行每個 thread 嘅工具。Tuist 可以成為你 Amp workspace 嘅 [自託管 orb 供應商](https://ampcode.com/docs/orbs/self-hosted)：每個揀選佢嘅 thread 都會喺自己專屬嘅 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中運行，支援 Linux 或 macOS。你無須自行運行或託管任何服務。

如果你想讓執行緒留喺現有嘅 orbs 上面，並且只喺 Mac 上編譯、測試同運行 Apple 平台代碼，請改用[Tuist Mac 插件](#remote-mac)。

## 連接 Amp {#connect}

你需要同時係 Amp 工作區同 Tuist 帳戶嘅管理員。

1. 喺 Amp 入面，打開你工作區嘅**Settings → Orbs**，點擊**Add Orb Provider**，並為佢命名，例如`tuist`。成員會根據呢個名稱選擇提供者。複製`aop_live_…` token；Amp 只會顯示一次。
2. 喺 Amp 提供者嘅**Edit**對話框中，加入你想提供嘅**Orb types**並選擇預設值。Linux 類型對應[Amp 自家 orbs](https://ampcode.com/docs/orbs/sizes-and-costs)嘅規格：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區 |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB 工作區 |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB 工作區 |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB 工作區（同`linux`一樣） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB 工作區 |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB 工作區 |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB 工作區 |
   | `macos` | macOS（連 Xcode） | 8 vCPU、8 GiB RAM、10 GB 工作區 |

3. 喺 Tuist 入面，打開你帳戶儀表板中嘅**Sandboxes**，點擊 Amp 卡片上嘅**Connect**，然後貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示**Connected**。一個 Tuist 帳戶對應一個提供者。任何喺 Amp 中使用該提供者嘅人，都會喺已連接嘅 Tuist 帳戶上運行 orbs 並由該帳戶計費。要停止服務，請點擊卡片上嘅**Disconnect**，或者喺 Amp 中關閉該提供者。

## 開始一個執行緒 {#start-a-thread}

喺 Amp 嘅新執行緒建立器中，點擊**Orb**，喺**Self-Hosted**下面選擇 Tuist 提供者，然後揀一個類型，例如對於需求少過`linux`嘅儲存庫選`linux-small`，對於需求更大嘅選`linux-large`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保留其 orb 類型。如果無指定類型，就會使用提供者嘅預設值。如果想讓每個新執行緒都使用同一種類型，請喺 Amp 嘅**Settings → Orbs**中嘅**Default Orb**下面選擇提供者及其類型。

Amp 會克隆儲存庫，運行你嘅`.agents/setup`腳本並設定 Git 憑證，就像對待每個 orb 一樣。每個 orb 亦都可以讀取你帳戶嘅 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當執行緒閒置時，Amp 會暫停其 orb。下一條訊息會恢復它，並且文件保持完整。

- **Linux：** 運行中嘅進程喺暫停後仍然存活。長期暫停嘅 orb 會移入歸檔存儲，並喺收到下一條訊息時恢復，但唔會恢復進程。Linux orbs 會保留文件，直到 Amp 刪除該執行緒嘅 orb。
- **macOS：** 處於暫停狀態或錯誤狀態達 7 日嘅 orb 會被刪除。執行緒嘅下一條訊息會啟動一個全新嘅 orb，並且 Amp 會再次運行`.agents/setup`。機器上第一個 macOS orb 會安裝 Amp CLI，所以啟動可能需要長達兩分鐘。

如果 orb 閒置而 Amp 無暫停它（例如因為暫停指令從未到達），十分鐘後它會被暫停，此時幾乎唔使用 CPU。

## 喺任何 Amp 執行緒中使用 Mac {#remote-mac}

Tuist Mac 插件為 Amp 執行緒提供一個包含 Xcode、iOS 模擬器同 Homebrew 嘅 macOS sandbox，而執行緒會繼續喺原位運行，例如喺 Amp 自己嘅其中一個 Linux orb 上。向 Amp 指派工作，佢會喺需要時啟動一台 Mac：

> 喺設定畫面加入深色模式切換掣，喺 iOS Simulator 中運行應用程式，並向我展示截圖。

Amp 會喺運行位置繼續編輯代碼。喺 Mac 上執行每個命令之前，插件會運行 `tuist sandbox sync`，複製 Git 無忽略嘅文件（無論有無 commit），之後只複製已更改嘅文件。Mac 建立嘅構建產物同其他被忽略嘅文件會留喺嗰度，令構建保持增量。插件會加入呢啲工具，以及一個告訴 Amp 何時同如何使用佢哋嘅 `remote-mac` 技能：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 建立執行緒嘅 Mac，或重用現有嘅，並進行同步 |
| `tuist_mac_shell` | 同步後，喺 Mac 上執行命令 |
| `tuist_mac_screenshot` | 喺執行緒中顯示模擬器或螢幕 |
| `tuist_mac_download` | 將文件複製回來，例如已構建嘅 `.app` |
| `tuist_mac_stop` | 刪除執行緒嘅 Mac |

Mac 本身無 Tuist CLI：第一次同步後，Amp 會喺儲存庫根目錄運行 `mise install` 以安裝項目指定嘅 Tuist 版本，而 `tuist_mac_shell` 會將 mise 嘅 shims 加入 `PATH`。Mac 上嘅每個命令都會使用 Tuist 4.218.0 或更高版本自行<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登入你帳戶嘅 cache</.localized_link>；如果使用 4.215.0 至 4.217.x 版本，Amp 會先運行 `tuist auth login`。

一個執行緒使用一台 Mac。當它閒置時，Tuist 會暫停它，下一個命令會恢復它。任務完成後，Amp 會刪除它；遺留嘅 Mac 會喺暫停 14 日後被刪除。Mac 會計入你嘅 Tuist 帳戶用量，就好似其他 sandbox 一樣。

### 設定 {#remote-mac-setup}

1. **安裝插件。** 它只係一個文件：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。要讓 Amp 工作區中嘅所有人都可以使用，工作區管理員需要喺執行緒中向 Amp 請求：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入我哋嘅工作區插件。

   Amp 會將其提交到工作區嘅 [plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills)，並在推送前詢問。如果想只為自己安裝，可以改為請求「my personal plugins」，或者將文件保存為儲存庫中嘅 `.amp/plugins/tuist-mac.ts` 以僅喺該處使用。插件係一份副本：要更新它，請要求 Amp 用同一 URL 嘅最新版本替換它。
2. **安裝 Tuist CLI** 喺 Amp 運行嘅地方。喺 orbs 上，將其加入儲存庫嘅 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本，例如 `mise use -g tuist@latest`，或者 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允許 CLI 使用你帳戶嘅 sandboxes。** 喺 orbs 上，按照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 中嘅描述，將你嘅 Amp 工作區連接到你嘅 Tuist 帳戶。Orbs 隨後會自行登入，並擁有訪問 sandboxes 嘅權限。喺其他地方，例如 Linux 機器上嘅 Amp CLI，請以帳戶成員身份運行 `tuist auth login`，或者將 `TUIST_MAC_TOKEN` 設置為具有 `account:sandboxes:write` 範圍嘅 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並加上 `ci` 以便 Mac 使用 cache。插件會將 `TUIST_MAC_TOKEN` 傳遞給 CLI 以代替 `TUIST_TOKEN`，所以即使你嘅 orbs 已經有無該範圍嘅 `TUIST_TOKEN`，都要設置它。
4. **告訴它使用哪個帳戶**，如果儲存庫中無包含 `project = "<account>/<project>"` 嘅 `tuist.toml`。喺 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳戶資訊。請喺你 Amp 項目嘅環境變數中將 `TUIST_MAC_ACCOUNT` 設置為你嘅帳戶 handle。如果無設置，Amp 會將 `Tuist.swift` 中嘅 `fullHandle` 傳遞給 `tuist_mac_start`。

CLI 只會通過 `tuist.dev` 連接 Mac，所以限制網絡訪問嘅環境需要允許該域名。要使用無喺 `PATH` 中嘅 CLI，請將 `TUIST_MAC_CLI` 設置為其路徑。

唔支持 Amp 插件嘅代理（例如 Claude Code 或 Cursor）可以通過 Tuist MCP 伺服器同 CLI 執行相同操作，詳情請參閱 <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>。

### 使用 Tuist Macs 代替 Amp 嘅 macOS Satellites {#remote-mac-satellites}

Amp 亦有自己嘅雲端 Mac，即 [macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前處於測試階段，供加入其等候名單嘅工作區使用。當執行緒可以同時啟動兩者時，Amp 嘅內置指令會將 macOS 工作發送畀其 satellites，因此好少會選擇插件。要讓執行緒使用 Tuist Macs，請執行以下其中一項操作：

- **為自己關閉 macOS Satellites。** 每個成員都可以喺 Amp 嘅 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 中嘅 **Mac Satellites** 下關閉它們。
- **為工作區關閉它們。** 當你工作區嘅 orbs [run on Tuist](#connect) 時，工作區管理員可以喺 Amp 工作區設定中嘅 **Orbs** 下，將 **Where Orbs Run** 設置為 **Self-Hosted Only**。代理隨後無法啟動 Amp 託管嘅 satellites，但成員亦無法使用 Amp 嘅內置 orbs，所以只有當你所有執行緒都喺你自己嘅 orb 提供者上運行時，才執行此操作。
- **請求使用 Tuist Macs。** 喺提示詞中加入「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或者加入 Amp 工作區設定中嘅工作區代理指引，令每個執行緒都遵循它。
