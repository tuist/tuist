---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理而設嘅持久化 Linux 同 macOS 虛擬機。每個代理會話都會分配獨立嘅機器，當代理閒置時會暫停，並喺恢復時保持文件完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請，因為我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯繫我們，為你的帳戶申請存取權限。當 Sandboxes 全面開放時，我們將公佈定價。

沙盒是一個虛擬機器，編碼代理在其中執行指令並編輯檔案。每個代理工作階段都有自己的沙盒，在整個工作階段期間保留其檢出內容、建構產物和已安裝的工具。當代理閒置時，沙盒會暫停；下一則訊息會從上次停止的地方恢復。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>在同一機隊上運行，位於你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>旁邊，因此代理的建構可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上運行你的 Amp 工作區的 orbs，或使用<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 執行緒提供一台 Mac 以進行 Xcode 建構。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上運行 Claude Managed Agents 工作階段和 Claude Code 雲端工作階段（claude.ai、桌面和流動應用程式，以及 `claude --cloud`）。
- **[The Tuist CLI](#cli)**：從終端機或透過 API 從你自己的工具建立沙盒並在其中執行指令。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從終端機建立沙盒並在其中執行指令。

### 1. 登入 {#cli-log-in}

帳戶的任何成員都可以建立和管理其沙盒：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux 請省略 `--platform`。傳遞帶有版本的 `--xcode`（例如 `--xcode 26.1.1`），以取得具有該 [Xcode](#xcode) 的 Mac；這意味著 `--platform macos`。傳遞 `--vcpus` 搭配 `--memory-gb` 以獲得更大的[規格](#platforms)，並使用 `--workspace-gb` 獲得更大的磁碟空間。一旦沙盒運行，指令就會返回並列印其詳細資訊，包括其 ID。它使用當前目錄中 Tuist 專案的帳戶；傳遞 `--account` 以選擇其他帳戶。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中使用 `bash -l` 運行，如果已暫停則會先恢復。`tuist` 會串流其輸出，無論運行多久，並以指令的狀態退出；Ctrl-C 會在沙盒中取消它。視需要傳遞 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最長六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示一個 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案鏡像到其中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以獲取機器可讀取的輸出。參閱<.localized_link href="/cli/sandbox">CLI 參考</.localized_link>了解所有選項。若要改為從程式碼驅動沙盒，請透過[Tuist API](https://tuist.dev/api/docs)在 `/api/accounts/{account_handle}/sandboxes` 下使用相同的操作，或讓代理透過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它們。

無法互動式登入的工具（例如在 macOS 沙盒中建構的代理外掛程式），可以改用具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>進行身份驗證。它可以執行帳戶成員可以執行的操作：建立沙盒、在其中執行指令，以及暫停、恢復、封存和刪除它們。整合設定由帳戶管理員保留。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像不包含 Tuist CLI，因此運行的是你專案自己固定的版本。在第一次 `tuist sandbox sync` 之後，在沙盒上的儲存庫根目錄中運行 `mise install`（已安裝 `mise` 和 `brew`）。你使用 `tuist sandbox exec` 啟動的每個指令都會將 mise 的 shims（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，因此 `tuist` 和其他 mise 工具可以在你的指令和 Xcode 建構階段（例如 scheme 的 post-actions）中運行。

你使用 `tuist sandbox exec` 啟動的每個指令也會獲得 Tuist runner 所獲得的內容，因此沙盒中的建構可以使用你帳戶的<.localized_link href="/guides/features/cache">快取</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以到達的位置（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 至 4.217.x 版本，請先在相同指令中運行 `tuist auth login`。

權杖是為每個指令鑄造的，只能在該指令運行期間交換為 Tuist 權杖，因此沙盒永遠不會持有長期憑證。它授予的權限不會超過啟動指令的人或權杖對快取可以執行的操作：帳戶成員如果其快取只有寫入權杖，則獲得讀取權限，並且帳戶權杖需要快取範圍（例如 `ci`）以及 `account:sandboxes:write`，沙盒才能使用快取。你使用 `--env` 傳遞的變數具有優先權。

## 從編碼代理在 Mac 上建構 {#coding-agents}

在 Linux 上運行的編碼代理（例如雲端代理工作階段）可以在 macOS 沙盒上建構、測試和運行 Apple 平台代碼，同時繼續在其運行的位置編輯檔案。在 Amp 中，安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理（例如 Claude Code 或 Cursor）：

1. 將代理連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的 `create_sandbox` 工具告訴代理如何驅動 Mac。
2. 在代理運行的地方安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 對 CLI 進行身份驗證。MCP 伺服器的登入不會延續到它，因此要么以帳戶成員身份運行 `tuist auth login`，要么將 `TUIST_TOKEN` 設定為具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網絡存取，請允許 `tuist.dev`。CLI 透過它將檔案上傳到 Mac，因此不需要其他網域。

代理會為每個任務建立一台 Mac，並使用項目鎖定的 [Xcode](#xcode)：`create_sandbox` 列出可供選擇的 Xcode 版本，並指示代理讀取項目的鎖定版本，例如 `.xcode-version`。在執行每個指令之前，它會運行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後只複製已變更的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄運行 `mise install`，以便 [項目鎖定的 Tuist](#tuist-in-sandbox) 就位，並登入你帳戶的快取。然後，代理使用 `tuist sandbox exec` 運行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（如截圖或建構好的應用程式）複製回來，並在任務完成後刪除 Mac。Mac 會在最後一個指令執行後保持運行 10 分鐘，以便下一個指令立即開始；`tuist sandbox pause` 可以更快釋放資源。閒置的 Mac 會暫停，並在暫停 14 天後被刪除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（預設）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple 晶片上運行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 選擇 Xcode {#xcode}

每個 macOS 沙盒運行一個 Xcode，你在建立時選擇。它啟動的映像與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理使用與你的 CI 相同的工具鏈和模擬器進行建構。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中為 `--xcode`）選擇一個，使用確切版本，如同 runner 設定檔所做的那樣：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | `tuist_mac_start` 搭配 `xcode` |
| Amp orbs | orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果不指定版本**，Mac 將使用預設值。
- **如果請求 Tuist 未提供的版本會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你知道當前可用的選項。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 你或請求 Mac 的代理需要選擇版本。MCP 工具和 Tuist Mac 外掛程式會指示代理匹配項目鎖定的版本。
- **沙盒在其生命週期內保留其 Xcode。** 若要使用另一個 Xcode 進行建構，請建立新的沙盒。`xcodebuild -version` 顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間或與 CI 作業之間不共享檔案系統、記憶體或進程。
- 沙盒屬於一個帳戶，其任何成員都可以使用和管理它們，包括服務於整合的沙盒。只有管理員可以連接整合。來自整合的工作階段只能存取該整合所連接帳戶的沙盒。
- 你提供給 Tuist 以連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會加密儲存，且不會再次顯示。
- 沙盒可以存取互聯網。請像對待 CI 作業一樣對待代理從中可以存取的內容。
