---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes 上，於 Linux 或 macOS 執行你的 Amp 工作區 Orbs。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中留言，即可為你的帳戶申請存取權限。

[Amp](https://ampcode.com)會在一個[orb](https://ampcode.com/docs/orbs)（已檢出該執行緒儲存庫的機器）中執行每個執行緒的工具。Tuist 可以作為你 Amp 工作區的[自託管 orb 提供者](https://ampcode.com/docs/orbs/self-hosted)：選擇此提供者的每個執行緒都會在其專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>中執行，支援 Linux 或 macOS。你無需自行執行或託管任何服務。

## 連接 Amp {#connect}

你需要同時是 Amp 工作區與 Tuist 帳戶的管理員。

1. 在 Amp 中，開啟工作區的**Settings → Orbs**，點擊**Add Orb Provider**並命名（例如`tuist`）。成員會依此名稱選擇提供者。複製`aop_live_…`權杖；Amp 僅顯示一次。
2. 在 Amp 中提供者的**Edit**對話框裡，新增以下**Orb types**並選擇預設值：

   | 類型 | 平台 | 規格 |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU、4 GiB RAM、10 GB 工作區 |
   | `macos` | macOS（含 Xcode） | 8 vCPU、8 GiB RAM、10 GB 工作區 |

3. 在 Tuist 中，於帳戶儀表板開啟**Sandboxes**，點擊 Amp 卡片上的**Connect**，並貼上權杖。

當 Tuist 開始提供該提供者服務時，卡片會顯示**Connected**。一個 Tuist 帳戶對應一個提供者。任何能在 Amp 中使用該提供者的人，其 orbs 都會在已連接的 Tuist 帳戶上執行並計費。若要停止，請點擊卡片上的**Disconnect**，或在 Amp 中關閉該提供者。

## 啟動執行緒 {#start-a-thread}

在 Amp 的新執行緒撰寫器中，點擊**Orb**，在**Self-Hosted**下選擇 Tuist 提供者，並挑選`linux`或`macos`。透過 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

執行緒會永久保留其 orb 類型。若未指定類型，則使用提供者的預設值。若要讓每個新執行緒都使用同一平台，請在 Amp 的**Settings → Orbs**中，於**Default Orb**下選擇提供者及其類型。

Amp 會複製儲存庫、執行你的`.agents/setup`腳本並設定 Git 憑證，這與處理每個 orb 的方式相同。每個 orb 也能讀取你帳戶的 Tuist <.localized_link href="/guides/features/cache">快取</.localized_link>。

## 暫停與保留 {#retention}

當執行緒閒置時，Amp 會暫停其 orb。下一則訊息會恢復 orb，且檔案保持完整。

- **Linux：** 執行中的程序在暫停後仍會保留。若 orb 被暫停過久，會移至歸檔儲存空間，並在收到下一則訊息時還原，但不包含先前執行的程序。Linux orbs 會保留檔案，直到 Amp 刪除該執行緒的 orb。
- **macOS：** 若 orb 處於暫停或錯誤狀態達 7 天，將被刪除。執行緒的下一則訊息會啟動全新的 orb，Amp 會再次執行`.agents/setup`。機器上的第一個 macOS orb 會安裝 Amp CLI，因此啟動可能需要最多兩分鐘。

若 orb 持續閒置而 Amp 未將其暫停（例如從未收到暫停指令），十分鐘後會進入暫停狀態，此時幾乎不消耗 CPU。
