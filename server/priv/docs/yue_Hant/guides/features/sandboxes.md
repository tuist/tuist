---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理而設嘅持久 Linux 同 macOS 虛擬機。每個代理會話都會分配到獨立機器，當代理閒置時會暫停，並喺恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前正處於擴容階段，僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯絡我們，為你的帳戶申請存取權限。當 Sandboxes 全面開放時，將會公佈定價。

沙盒是一個虛擬機器，編碼代理程式會在這裡執行指令並編輯檔案。每個代理程式工作階段都會擁有自己的沙盒，在整個工作階段期間保留其檢出內容、建構產物和已安裝的工具。當代理程式閒置時，沙盒會暫停；下一則訊息會從上次停止的地方恢復執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>在同一個機群上運行，並緊鄰你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建構可以使用與你的 CI 和本地機器相同的快取構件。

你可以透過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行你的 Amp 工作區的 orbs，或使用<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 對話提供一台 Mac 以進行 Xcode 建構。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段和 Claude Code 雲端工作階段（claude.ai、桌面和移動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從你的終端機或透過 API 從你自己的工具建立沙盒並在其中執行指令。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從你的終端機建立沙盒並在其中執行指令。

### 1. 登入 {#cli-log-in}

帳戶的任何成員都可以建立和管理其沙盒：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux 請省略 `--platform`。對於具有該 [Xcode](#xcode) 版本的 Mac，請傳遞帶有版本號的 `--xcode`，例如 `--xcode 26.1.1`；這意味著 `--platform macos`。若要獲得更大的[規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 一起傳遞；若要獲得更大的磁碟空間，請傳遞 `--workspace-gb`。一旦沙盒開始運行，指令就會返回並列印其詳細資訊，包括其 ID。它使用當前目錄中 Tuist 專案的帳戶；若要選擇其他帳戶，請傳遞 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中使用 `bash -l` 運行，如果沙盒已暫停，則會先恢復。`tuist` 會串流輸出，無論運行多久，並以指令的狀態退出；Ctrl-C 會在沙盒中取消它。根據需要傳遞 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最多六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案鏡像到沙盒中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以獲得機器可讀取的輸出。參閱<.localized_link href="/cli/sandbox">CLI 參考</.localized_link>以了解所有選項。若要改為從程式碼驅動沙盒，請透過[Tuist API](https://tuist.dev/api/docs)在 `/api/accounts/{account_handle}/sandboxes` 下使用相同的操作，或讓代理程式透過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它們。

無法互動式登入的工具（例如在 macOS 沙盒中建構的代理程式外掛程式），可以改用具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>進行身份驗證。它可以執行帳戶成員可以執行的操作：建立沙盒、在其中執行指令，以及暫停、恢復、封存和刪除它們。整合設定由帳戶管理員保留。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像不包含 Tuist CLI，因此運行的是你專案自己鎖定的版本。在第一次 `tuist sandbox sync` 之後，在沙盒中的儲存庫根目錄運行 `mise install`（已安裝 `mise` 和 `brew`）。你使用 `tuist sandbox exec` 啟動的每個指令都將 mise 的 shims（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，因此 `tuist` 和其他 mise 工具可以在你的指令和 Xcode 建構階段（例如 scheme 的 post-actions）中運行。

你使用 `tuist sandbox exec` 啟動的每個指令也會獲得 Tuist runner 所擁有的內容，因此沙盒中的建構可以使用你帳戶的<.localized_link href="/guides/features/cache">快取</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以存取的位置（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，一個用於該指令的短期身份令牌。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 到 4.217.x 版本，請先在相同指令中運行 `tuist auth login`。

令牌是為每個指令鑄造的，只能在該指令運行期間交換為 Tuist 令牌，因此沙盒永遠不會持有長期憑證。它授予的權限不會超過啟動指令的人或令牌對快取所能執行的操作：帳戶成員如果其快取令牌只能寫入，則獲得讀取權限，並且帳戶令牌需要快取範圍（例如 `ci`），以及 `account:sandboxes:write`，沙盒才能使用快取。你使用 `--env` 傳遞的變數具有優先權。

## 從編碼代理程式在 Mac 上建構 {#coding-agents}

在 Linux 上運行的編碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙盒上建構、測試和運行 Apple 平台代碼，同時繼續在其運行位置編輯檔案。在 Amp 中，安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式，例如 Claude Code 或 Cursor：

1. 將代理程式連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的 `create_sandbox` 工具會告訴代理程式如何驅動 Mac。
2. 在代理程式運行的地方安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 對 CLI 進行身份驗證。MCP 伺服器的登入不會延續到 CLI，因此要么以帳戶成員身份運行 `tuist auth login`，要么將 `TUIST_TOKEN` 設定為具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。
4. 如果環境限制網絡存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳到 Mac，因此不需要其他網域。

代理程式會為每個任務建立一台 Mac，並使用專案鎖定的 [Xcode](#xcode)：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理程式讀取專案的鎖定版本，例如 `.xcode-version`。在執行每個指令之前，它會運行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則只複製已變更的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄運行 `mise install`，以便[專案鎖定的 Tuist](#tuist-in-sandbox) 就位，並登入你帳戶的快取。接著，代理程式會使用 `tuist sandbox exec` 運行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（例如螢幕截圖或建構好的應用程式）複製回來，並在任務完成後刪除 Mac。Mac 會在最後一個指令結束後繼續運行 10 分鐘，以便下一個指令立即啟動；`tuist sandbox pause` 可以更快釋放資源。閒置的 Mac 會進入暫停狀態，並在暫停 14 天後被刪除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（預設）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple silicon 上運行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 選擇 Xcode {#xcode}

每個 macOS 沙盒運行一個 Xcode，你在建立時選擇。它啟動的映像與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理程式使用的工具鏈和模擬器與你的 CI 相同。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中的 `--xcode`）選擇一個，使用確切版本，如同 runner 設定檔所做的那樣：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | 使用 `xcode` 的 `tuist_mac_start` |
| Amp orbs | orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果沒有指定版本**，Mac 會使用預設值。
- **如果請求 Tuist 未提供的版本會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你知道目前有哪些可用。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 你或請求 Mac 的代理程式需選擇版本。MCP 工具和 Tuist Mac 外掛程式會告訴代理程式匹配專案鎖定的版本。
- **沙盒會終身保留其 Xcode。** 若要使用另一個 Xcode 進行建構，請建立新的沙盒。`xcodebuild -version` 會顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不共享檔案系統、記憶體或行程。
- 沙盒屬於一個帳戶，其任何成員都可以使用和管理它們，包括服務於整合的沙盒。只有管理員可以連接整合。來自整合的工作階段只能存取該整合所連接帳戶的沙盒。
- 你提供給 Tuist 以連接整合的憑證（例如 Amp 提供者令牌或 Claude 環境金鑰）會加密儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請像對待 CI 工作一樣對待代理程式從中存取的內容。
