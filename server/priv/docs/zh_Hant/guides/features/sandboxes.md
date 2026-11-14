---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 和 Claude 等程式碼代理設計的持久性 Linux 與 macOS 虛擬機器。每個代理工作階段都會分配到專屬的機器，當代理處於閒置狀態時會暫停，並在恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限受邀使用者，以便我們擴充容量。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯繫我們，為你的帳戶申請存取權。當 Sandboxes 全面開放時，我們將公布定價。

沙盒是虛擬機器，編碼代理程式在其中執行指令並編輯檔案。每個代理程式工作階段都會獲得專屬沙盒，並在該工作階段期間保留其檢出內容、建置產物與已安裝的工具。當代理程式閒置時，沙盒會暫停；下一則訊息會從上次停下的位置繼續執行。

沙盒與 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 在同一機群上運行，並緊鄰你團隊的 <.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本機機器相同的快取構件。

你可以透過以下方式運用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行 Amp 工作區的 orbs，或透過 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link> 為任何 Amp 對話提供 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙盒並在其中執行指令，或透過 API 從你自己的工具中執行。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從終端機建立沙盒並在其中執行指令。

### 1. 登入 {#cli-log-in}

管理沙盒需要帳戶管理員：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

若為 Linux，請省略 `--platform`。若要更大的 [規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 一起傳遞；若要更大的磁碟，請傳遞 `--workspace-gb`。命令會在沙盒啟動後返回，並列印其詳細資訊（包含 ID）。它會使用目前目錄中 Tuist 專案的帳戶；若要選擇其他帳戶，請傳遞 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該命令在沙盒中以 `bash -l` 執行，如果沙盒處於暫停狀態，會先恢復。`tuist` 會串流輸出直到命令結束，並以命令的狀態碼退出；在沙盒中按 Ctrl-C 可取消執行。視需要傳遞 `--cwd`、`--env NAME=VALUE` 與 `--timeout`（最長六小時）。

### 常見工作 {#cli-tasks}

| 工作 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本機 Git 工作樹的檔案鏡像至沙盒 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加上 `--json` 以取得機器可讀的輸出。查看所有選項請參閱 <.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若要從程式碼驅動沙盒，請透過 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下執行相同操作，或讓代理程式透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它們。

無法互動式登入的工具（例如在 macOS 沙盒中建置的代理程式外掛程式），可以改用具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 進行驗證。它可以像帳戶成員一樣建立沙盒、在其中執行指令，以及暫停、恢復和刪除沙盒。用於支援 Amp 或 Claude 整合、分析資料與整合設定的沙盒，仍由帳戶管理員管理。

## 從編碼代理程式在 Mac 上建置 {#coding-agents}

在 Linux 上執行的編碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙盒上建置、測試並執行 Apple 平台程式碼，同時在它運行的位置繼續編輯檔案。在 Amp 中，安裝 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式（例如 Claude Code 或 Cursor）：

1. 將代理程式連接至 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的 `create_sandbox` 工具會告訴代理程式如何驅動 Mac。
2. 在代理程式運行的位置安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入不會延續到 CLI，因此請以帳戶成員身分執行 `tuist auth login`，或將 `TUIST_TOKEN` 設為具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網路存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳至 Mac，因此不需要其他網域。

代理程式會為每項任務建立一台 Mac，並在每個指令之前執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後只複製有變更的檔案。接著，代理程式會使用 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（例如螢幕截圖或已建置的 App）複製回來，並在任務完成後刪除 Mac。Mac 在最後一個指令執行後會保持運行 10 分鐘，以便下一個指令立即啟動；`tuist sandbox pause` 可以更快釋放資源。遺留的 Mac 會暫停，並在暫停 14 天後刪除。

## Linux 與 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU、4 GiB RAM（預設）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple Silicon 上運行：

- 8 vCPU、8 GiB RAM（預設）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不會共用檔案系統、記憶體或處理程序。
- 沙盒屬於帳戶，只有其管理員可以管理它們。來自整合的工作階段只能存取該整合所連接帳戶的沙盒。
- 你提供給 Tuist 用於連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請像對待 CI 工作一樣，對待代理程式從沙盒存取的內容。
