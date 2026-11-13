---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上運行你 Amp workspace 嘅 orbs，或者透過 Tuist Mac plugin 為任何 Amp thread 提供 Mac 環境以進行 Xcode 建置。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 同 macOS）目前只限邀請使用。[聯絡我哋](mailto:contact@tuist.dev)或者喺[社區 Slack](https://slack.tuist.dev)通知我哋，為你嘅帳戶申請存取權限。

[Amp](https://ampcode.com)會喺一個[orb](https://ampcode.com/docs/orbs)入面執行每個 thread 嘅工具；orb 係一部已 checkout 該 thread 儲存庫嘅機器。Tuist 可以成為你 Amp workspace 嘅[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個揀咗佢嘅 thread 都會喺自己專屬嘅 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>入面運行，支援 Linux 或 macOS。你唔需要自己運行或託管任何東西。

如果想令你嘅 thread 繼續使用現有嘅 orbs，並且只在 Mac 上構建、測試同運行 Apple 平台代碼，請改用[Tuist Mac plugin](#remote-mac)。

## 連接 Amp {#connect}

你需要同時係 Amp workspace 同 Tuist 帳戶嘅管理員。

1. 喺 Amp 入面，開啟你 workspace 嘅**Settings → Orbs**，點擊**Add Orb Provider**，並為佢命名，例如`tuist`。成員會透過呢個名稱揀選提供者。複製`aop_live_…` token；Amp 只會顯示一次。
2. 喺 Amp 提供者嘅**Edit**對話框中，加入你想提供嘅**Orb types**並揀選預設值。Linux 類型對應[Amp 自家 orbs](https://ampcode.com/docs/orbs/sizes-and-costs)嘅規格：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB workspace |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB workspace |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB workspace |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB workspace（同`linux`一樣） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB workspace |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB workspace |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB workspace |
   | `macos` | macOS（連 Xcode） | 8 vCPU、8 GiB RAM、10 GB workspace |

3. 喺 Tuist 入面，開啟你帳戶儀表板中嘅**Sandboxes**，喺 Amp 卡片上點擊**Connect**，然後貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示**Connected**。一個 Tuist 帳戶對應一個提供者。任何能夠喺 Amp 中使用該提供者嘅人，都會喺已連接嘅 Tuist 帳戶上運行 orbs 並由該帳戶計費。要停止服務，請喺卡片上點擊**Disconnect**，或者喺 Amp 中關閉該提供者。

## 啟動 thread {#start-a-thread}

喺 Amp 嘅新 thread 編寫器中，點擊**Orb**，喺**Self-Hosted**底下揀選 Tuist 提供者，然後揀選一個類型，例如對於需求低於`linux`嘅儲存庫揀選`linux-small`，或者對於需求更高嘅揀選`linux-large`。透過 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Thread 會終身保持其 orb 類型。如果無指定類型，佢會使用提供者嘅預設值。如果想讓每個新 thread 都使用同一種類型，請喺 Amp 嘅**Settings → Orbs**中嘅**Default Orb**底下揀選提供者及其類型。

Amp 會 clone 儲存庫、執行你嘅`.agents/setup`腳本並設定 Git 憑證，就好似佢對每個 orb 所做嘅一樣。每個 orb 亦都可以讀取你帳戶嘅 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當 thread 進入閒置狀態時，Amp 會暫停其 orb。下一條訊息會恢復它，並保持文件完整。

- **Linux：** 運行中嘅進程喺暫停後仍然存活。長期暫停嘅 orb 會移入歸檔儲存空間，並喺收到下一條訊息時恢復，但唔會恢復其進程。Linux orbs 會保留其文件，直到 Amp 刪除該 thread 嘅 orb。
- **macOS：** 處於暫停狀態或錯誤狀態達 7 日嘅 orb 會被刪除。Thread 嘅下一條訊息會啟動一個全新嘅 orb，而 Amp 會再次執行`.agents/setup`。機器上第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

如果 orb 保持閒置而 Amp 無暫停佢（例如因為從未收到暫停指令），佢會喺十分鐘後被暫停，此時幾乎無 CPU 使用量。

## 從任何 Amp thread 使用 Mac {#remote-mac}

Tuist Mac 插件為 Amp thread 提供一個包含 Xcode、iOS 模擬器同 Homebrew 嘅 macOS sandbox，而 thread 會繼續喺原本位置運行，例如喺 Amp 自己嘅其中一個 Linux orb 上。向 Amp 指派工作，佢會喺需要時啟動一部 Mac：

> 喺設定畫面加入深色模式切換按鈕，喺 iOS Simulator 中運行應用程式，然後俾張截圖我睇。

Amp 會喺運行位置繼續編輯代碼。喺 Mac 上執行每個命令之前，插件會運行 `tuist sandbox sync`，複製 Git 無忽略嘅文件（無論有無 commit），之後只複製有變更嘅文件。Mac 建立嘅建構產物同其他被忽略嘅文件會留喺嗰度，令建構保持增量式。插件會加入呢啲工具，以及一個告訴 Amp 何時同如何使用佢哋嘅 `remote-mac` skill：

| 工具 | 作用 |
| --- | --- |
| `tuist_mac_start` | 建立 thread 嘅 Mac，或者重用佢，並進行同步 |
| `tuist_mac_shell` | 同步後，喺 Mac 上執行命令 |
| `tuist_mac_screenshot` | 喺 thread 中顯示模擬器或螢幕 |
| `tuist_mac_download` | 將文件複製返嚟，例如已建構嘅 `.app` |
| `tuist_mac_stop` | 刪除 thread 嘅 Mac |

一個 thread 使用一部 Mac。當佢閒置時，Tuist 會暫停佢，下一個命令會恢復佢。當任務完成時，Amp 會刪除佢；如果 Mac 被遺留，暫停 14 日後會被刪除。Mac 會計入你嘅 Tuist 帳戶用量，就好似其他 sandbox 一樣。

### 設定 {#remote-mac-setup}

1. **安裝插件。** 佢係單一文件，[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。要令佢對你 Amp workspace 中嘅所有人可用，workspace 管理員可以喺 thread 中要求 Amp：

   > 將 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 加入我哋嘅 workspace 插件。

   Amp 會將佢提交到 workspace 嘅 [plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills)，並喺推送前詢問。如果想只為自己安裝，可以改為要求「my personal plugins」，或者將文件儲存為儲存庫中嘅 `.amp/plugins/tuist-mac.ts` 以僅喺嗰度使用。該插件係一份副本：要更新佢，請要求 Amp 用同一 URL 嘅最新版本替換佢。
2. **安裝 Tuist CLI** 喺 Amp 運行嘅地方。喺 orbs 上，將佢加入儲存庫嘅 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 腳本，例如 `mise use -g tuist@latest`，或者 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **讓 CLI 使用你帳戶嘅 sandboxes。** 喺 orbs 上，按照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 中所述，將你嘅 Amp workspace 連接到你嘅 Tuist 帳戶。Orbs 隨後會自行登入，並擁有訪問 sandboxes 嘅權限。喺其他地方，例如 Linux 機器上嘅 Amp CLI，以帳戶成員身份運行 `tuist auth login`，或者將 `TUIST_MAC_TOKEN` 設定為具有 `account:sandboxes:write` 範圍嘅 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。插件會將 `TUIST_MAC_TOKEN` 傳遞畀 CLI 以取代 `TUIST_TOKEN`，所以即使你嘅 orbs 已經有無該範圍嘅 `TUIST_TOKEN`，都要設定佢。
4. **告訴佢使用哪個帳戶**，如果儲存庫中無包含 `project = "<account>/<project>"` 嘅 `tuist.toml`。喺 Linux 上，CLI 無法從 `Tuist.swift` 讀取帳戶。喺你 Amp 項目嘅環境變數中，將 `TUIST_MAC_ACCOUNT` 設定為你嘅帳戶 handle。如果無設定，Amp 會將 `Tuist.swift` 嘅 `fullHandle` 傳遞畀 `tuist_mac_start`。

CLI 只能透過 `tuist.dev` 連接 Mac，所以限制網絡訪問嘅環境需要允許該域名。要使用無喺 `PATH` 上嘅 CLI，請將 `TUIST_MAC_CLI` 設定為其路徑。

唔支援 Amp 插件嘅代理（例如 Claude Code 或 Cursor）可以透過 Tuist MCP 伺服器同 CLI 做到同樣嘅事，詳情請參閱 <.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理喺 Mac 上建構</.localized_link>。

### 使用 Tuist Macs 代替 Amp 嘅 macOS Satellites {#remote-mac-satellites}

Amp 亦有自己嘅雲端 Mac，即 [macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前處於測試階段，供加入其等候名單嘅 workspace 使用。當 thread 可以同時啟動兩者時，Amp 嘅內建指令會將 macOS 工作發送畀其 satellites，因此好少會揀選插件。要讓 thread 使用 Tuist Macs，請執行以下其中一項操作：

- **為自己關閉 macOS Satellites。** 每個成員都可以喺 Amp 嘅 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 中嘅 **Mac Satellites** 底下關閉佢哋。
- **為 workspace 關閉佢哋。** 當你 workspace 嘅 orbs [喺 Tuist 上運行](#connect) 時，workspace 管理員可以喺 Amp workspace 設定中嘅 **Orbs** 底下，將 **Where Orbs Run** 設定為 **Self-Hosted Only**。代理隨後無法啟動 Amp 託管嘅 satellites，但成員亦無法使用 Amp 嘅內建 orbs，所以只有當你所有 thread 都喺你自己嘅 orb 提供者上運行時，才執行此操作。
- **要求使用 Tuist Macs。** 喺提示詞中加入「Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.」，或者加入 Amp workspace 設定中嘅 workspace 代理指引，令每個 thread 都遵循佢。
