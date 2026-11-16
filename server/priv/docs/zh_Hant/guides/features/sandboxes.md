---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 和 Claude 等程式碼代理設計的持久性 Linux 與 macOS 虛擬機器。每個代理工作階段都會獲得專屬的機器，在代理閒置時暫停，並在恢復時保持檔案完整無缺。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前在我們擴充容量期間僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以請求存取您的帳戶。當 Sandboxes 全面開放時，我們將公佈定價。

沙盒是一個虛擬機器，程式碼代理在其中執行指令並編輯檔案。每個代理工作階段都會獲得專屬的沙盒，在該工作階段的生命週期內保留其檢出的程式碼、建置產物及已安裝的工具。當代理閒置時，沙盒會暫停；下一則訊息會從上次停止的地方繼續執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行在同一機群上，緊鄰您團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理的建置可以使用與您的 CI 和本機機器相同的快取構件。

您可以透過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行 Amp 工作區的 orbs，或透過<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 執行緒提供用於 Xcode 建置的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段和 Claude Code 雲端工作階段（claude.ai、桌面和行動應用程式，以及`claude --cloud`）。
- **[The Tuist CLI](#cli)**：從終端機建立沙盒並在其中執行指令，或透過 API 從您自己的工具中執行。

## 開始使用 CLI {#cli}

使用`tuist sandbox`從終端機建立沙盒並在其中執行指令。

### 1. 登入 {#cli-log-in}

管理沙盒需要帳戶管理員：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux 請省略`--platform`。傳遞`--vcpus`與`--memory-gb`以獲得更大的[規格](#platforms)，並傳遞`--workspace-gb`以獲得更大的磁碟空間。一旦沙盒開始運行，指令就會返回並列印其詳細資訊，包括其 ID。它使用目前目錄中 Tuist 專案的帳戶；傳遞`--account`以選擇其他帳戶。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中使用`bash -l`執行，如果沙盒處於暫停狀態，會先恢復執行。`tuist`會串流輸出內容直到指令執行完畢，並以指令的狀態結束；在沙盒中按 Ctrl-C 可取消執行。視需要傳遞`--cwd`、`--env NAME=VALUE`和`--timeout`（最長六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本機 Git 工作樹的檔案鏡像到沙盒中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看使用情況 | `tuist sandbox analytics` |

添加`--json`以獲得機器可讀取的輸出。參閱<.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>以了解所有選項。若要改為從程式碼驅動沙盒，請透過[Tuist API](https://tuist.dev/api/docs)下的`/api/accounts/{account_handle}/sandboxes`使用相同的操作，或讓代理透過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它們。

無法互動式登入的工具（例如在 macOS 沙盒中建置的代理外掛程式），可以改用具有`account:sandboxes:write`權限範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>進行驗證。它可以像帳戶成員一樣建立沙盒、在其中執行指令，以及暫停、恢復和刪除沙盒。服務於 Amp 或 Claude 整合、分析資料和整合設定的沙盒仍由帳戶管理員管理。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像檔未包含 Tuist CLI，因此執行的是您專案中固定的版本。在第一次`tuist sandbox sync`之後，在沙盒的儲存庫根目錄中執行`mise install`（已安裝`mise`和`brew`），然後透過 mise 執行`tuist`，例如將`$HOME/.local/share/mise/shims`加入`PATH`。

您使用`tuist sandbox exec`啟動的每個指令也會獲得 Tuist runner 所具備的功能，因此沙盒中的建置可以使用您帳戶的<.localized_link href="/guides/features/cache">快取</.localized_link>，而無需您傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以存取的情況下（例如在 macOS 上），同一機架中快取的`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 至 4.217.x 版本，請先在相同指令中執行`tuist auth login`。

權杖是為每個指令產生的，並且只能在該指令執行期間交換為 Tuist 權杖，因此沙盒永遠不會持有長期有效的憑證。它授予的權限不會超過啟動指令的人或權杖對快取所能執行的操作：帳戶成員若其快取僅允許權杖寫入，則獲得讀取權限；而帳戶權杖需要快取權限範圍（例如`ci`），以及`account:sandboxes:write`，沙盒才能使用快取。您透過`--env`傳遞的變數具有優先權。

## 從程式碼代理在 Mac 上建置 {#coding-agents}

在 Linux 上運行的程式碼代理（例如雲端代理工作階段）可以在 macOS 沙盒上建置、測試和執行 Apple 平台程式碼，同時繼續在其運行位置編輯檔案。在 Amp 中，安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理（例如 Claude Code 或 Cursor）：

1. 將代理連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。其`create_sandbox`工具會告訴代理如何驅動 Mac。
2. 在代理運行的位置安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用`tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入不會延續到 CLI，因此請以帳戶成員身份執行`tuist auth login`，或將`TUIST_TOKEN`設定為具有`account:sandboxes:write`權限範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網路存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳到 Mac，因此不需要其他網域。

代理會為每個任務建立一台 Mac，並在執行每個指令前執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製變更過的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄中執行 `mise install`，以便放置 [專案中固定的 Tuist](#tuist-in-sandbox) 並登入您帳戶的快取。接著，代理會使用 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，透過 `tuist sandbox cp` 將結果（例如螢幕截圖或建置完成的應用程式）複製回來，並在任務完成後刪除 Mac。Mac 在最後一個指令執行完畢後會繼續運行 10 分鐘，以便下一個指令立即啟動；`tuist sandbox pause` 可讓其更快釋放。遺留的 Mac 會暫停，並在暫停 14 天後刪除。

## Linux 與 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU、4 GiB RAM（預設）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** 沙盒在搭載 Xcode 的 Apple silicon 上運行：

- 8 vCPU、8 GiB RAM（預設）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不共用檔案系統、記憶體或處理程序。
- 沙盒屬於某個帳戶，只有該帳戶的管理員可以管理它們。來自整合的工作階段只能存取該整合所連接帳戶的沙盒。
- 您提供給 Tuist 以連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請以對待 CI 工作的方式來處理代理從沙盒所能存取的內容。
