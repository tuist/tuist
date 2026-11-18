---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上執行你 Amp workspace 嘅 orbs。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開通權限。

[Amp](https://ampcode.com) 會在一個[orb](https://ampcode.com/docs/orbs)（已檢出該執行緒倉庫的機器）中運行每個執行緒的工具。Tuist 可以成為你 Amp 工作區的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：每個選擇它的執行緒都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中運行，支援 Linux 或 macOS。你無須自行運行或託管任何服務。

## 連接 Amp {#connect}

你需要同時是 Amp 工作區和 Tuist 帳戶的管理員。

1. 在 Amp 中，開啟工作區的**Settings → Orbs**，點擊**Add Orb Provider**，並為其命名，例如 `tuist`。成員會透過此名稱選擇提供者。複製 `aop_live_…` token；Amp 只會顯示一次。
2. 在 Amp 中提供者的**Edit**對話框中，添加這些**Orb types**並選擇預設值：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU、4 GiB RAM、10 GB 工作區 |
   | `macos` | macOS（含 Xcode） | 8 vCPU、8 GiB RAM、10 GB 工作區 |

3. 在 Tuist 中，開啟帳戶儀表板中的**Sandboxes**，點擊 Amp 卡片上的**Connect**，並貼上 token。

當 Tuist 開始服務該提供者時，卡片會顯示**Connected**。一個 Tuist 帳戶對應一個提供者。任何能在 Amp 中使用該提供者的人，其運行的 orb 將計入並向已連接的 Tuist 帳戶收費。若要停止，請點擊卡片上的**Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新建執行緒介面中，點擊**Orb**，在**Self-Hosted**下選擇 Tuist 提供者，並選擇 `linux` 或 `macos`。從 Amp CLI 執行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會終身保持其 orb 類型。若未指定類型，則使用提供者的預設值。若要讓每個新執行緒都使用同一平台，請在 Amp 的**Settings → Orbs**中的**Default Orb**下選擇提供者及其類型。

Amp 會克隆倉庫，運行你的 `.agents/setup` 腳本並設定 Git 憑證，這與對每個 orb 的操作相同。每個 orb 還可以讀取你帳戶的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暫停與保留 {#retention}

當執行緒進入閒置狀態時，Amp 會暫停其 orb。下一條訊息會恢復它，且文件完好無損。

- **Linux：** 運行中的進程在暫停後仍會保留。長時間暫停的 orb 會移至歸檔儲存空間，並在收到下一條訊息時恢復，但不會恢復其進程。Linux orb 會保留其文件，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 處於暫停或錯誤狀態達 7 天的 orb 會被刪除。執行緒的下一條訊息會啟動一個全新的 orb，Amp 會再次運行 `.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要長達兩分鐘。

如果 orb 處於閒置狀態而 Amp 未將其暫停（例如因為從未收到暫停指令），則在十分鐘後幾乎不消耗 CPU 的情況下將其暫停。
