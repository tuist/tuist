---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 與 Claude 等編碼代理設計的持久化 Linux 與 macOS 虛擬機器。每個代理工作階段都會獲得專屬的機器，在代理閒置時暫停，並在恢復時保留所有檔案。"
}
---
# 沙箱 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist 沙箱（Linux 與 macOS）目前因擴充容量而採邀請制。請[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中留言，為你的帳號申請存取權限。待沙箱全面開放時，我們將公布定價方案。

沙箱是虛擬機器，讓程式碼代理程式在其中執行指令並編輯檔案。每個代理程式工作階段都會獲得專屬的沙箱，在該工作階段存續期間保留其檢出的程式碼、建置產物與已安裝的工具。當代理程式閒置時，沙箱會暫停；收到下一則訊息時，會從上次停下的位置繼續執行。

沙箱與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行於相同的機群，並緊鄰你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式來使用沙箱：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行你的 Amp 工作區 orbs。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙箱並在其中執行指令，或透過 API 從你自己的工具進行操作。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從終端機建立沙箱並在其中執行指令。

### 1. 登入 {#cli-log-in}

管理沙箱需要帳號管理員：

```bash
tuist auth login
```

### 2. 建立沙箱 {#cli-create}

```bash
tuist sandbox create --platform macos
```

若為 Linux 請省略 `--platform`。若要更大的[規格](#platforms)，請搭配 `--memory-gb` 傳遞 `--vcpus`；若要更大的磁碟空間，請傳遞 `--workspace-gb`。當沙箱開始運作後，指令便會返回並印出其詳細資訊，包括其 ID。它會使用目前目錄中 Tuist 專案所屬的帳號；若要選擇其他帳號，請傳遞 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙箱中以 `bash -lc` 執行，若沙箱處於暫停狀態會先恢復，且 `tuist` 會以該指令的狀態結束。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙箱 | `tuist sandbox list` |
| 顯示單一沙箱 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加上 `--json` 以取得機器可讀取的輸出。查看所有選項請參閱 <.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若想從程式碼驅動沙箱，請透過 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下執行相同的操作，或讓代理程式透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它們。

## Linux 與 macOS {#platforms}

**Linux** 沙箱執行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（預設）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙箱在搭載 Xcode 的 Apple silicon 上執行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

## 安全性 {#security}

- 每個沙箱都是獨立的虛擬機器。沙箱之間不會共用檔案系統、記憶體或處理程序，也不會與 CI 工作共用。
- 沙箱隸屬於某個帳號，只有該帳號的管理員可以管理它們。來自整合的工作階段只能存取該整合所連接之帳號的沙箱。
- 你提供給 Tuist 用以連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不會再次顯示。
- 沙箱可以存取網際網路。請將代理程式從沙箱能夠存取的內容，視為如同 CI 工作一般謹慎處理。
