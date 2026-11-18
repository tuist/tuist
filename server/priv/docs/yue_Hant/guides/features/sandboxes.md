---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理而設嘅持久化 Linux 同 macOS 虛擬機器。每個代理會話都有獨立嘅機器，當代理閒置時會暫停，並喺恢復時保持文件完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 同 macOS）目前仲係僅限邀請，等我哋擴展容量。你可以[聯絡我哋](mailto:contact@tuist.dev)或者喺[社區 Slack](https://slack.tuist.dev) 留言，為你嘅帳戶申請存取權限。當 Sandboxes 正式公開可用時，我哋會公佈定價。

沙盒係一個虛擬機器，編碼代理喺入面執行指令同編輯檔案。每個代理工作階段都會有自己專屬嘅沙盒，喺整個工作階段期間保留簽出內容、構建產物同已安裝嘅工具。當代理進入閒置狀態，沙盒會暫停；收到下一條訊息時，就會由上次暫停嘅位置繼續。

沙盒同<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行喺同一個基礎設施集群，並排部署於你團隊嘅<.localized_link href="/guides/features/cache">緩存</.localized_link>旁邊，所以代理嘅構建可以使用同你 CI 同本機一樣嘅緩存產物。

你可以透過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：喺 Tuist 上運行你 Amp workspace 嘅 orbs。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：喺 Tuist 上運行 Claude Managed Agents 工作階段同 Claude Code 雲端工作階段（claude.ai、桌面同流動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機或者透過 API 用你自己嘅工具建立沙盒並喺入面執行指令。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從終端機建立沙盒並喺入面執行指令。

### 1. 登入 {#cli-log-in}

管理沙盒需要帳戶管理員：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux 省略 `--platform`。如需更大嘅[規格](#platforms)，請將 `--vcpus` 同 `--memory-gb` 一齊傳遞；如需更大磁碟，請傳遞 `--workspace-gb`。當沙盒開始運行後，指令就會返回並列印其詳細資料，包括 ID。佢會使用當前目錄中 Tuist 專案所屬嘅帳戶；傳遞 `--account` 可以選擇其他帳戶。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

指令會喺沙盒中以 `bash -lc` 運行，如果沙盒處於暫停狀態會先恢復，然後 `tuist` 會以指令嘅退出狀態結束。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加入 `--json` 以獲取機器可讀取嘅輸出。查看所有選項請參考 <.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。如果想從程式碼驅動沙盒，可以透過 [Tuist API](https://tuist.dev/api/docs) 喺 `/api/accounts/{account_handle}/sandboxes` 下執行相同操作，或者讓代理透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用佢哋。

## Linux 同 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（預設）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒喺 Apple silicon 上運行，配備 Xcode：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

## 安全性 {#security}

- 每個沙盒都係獨立嘅虛擬機器。沙盒之間以及同 CI 工作之間唔會共用檔案系統、記憶體或進程。
- 沙盒屬於某個帳戶，只有該帳戶嘅管理員先可以管理佢哋。來自整合嘅工作階段只能存取該整合所連接帳戶嘅沙盒。
- 你提供畀 Tuist 用於連接整合嘅憑證（例如 Amp provider token 或 Claude environment key）會以加密方式儲存，並且永遠唔會再次顯示。
- 沙盒可以存取互聯網。請將代理從沙盒能夠存取嘅內容，視作同 CI 工作一樣處理。
