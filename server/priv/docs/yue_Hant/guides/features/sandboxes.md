---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理設計嘅持久 Linux 同 macOS 虛擬機。每個代理會話都有獨立嘅機器，當代理閒置時會暫停，並喺恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用，因為我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯絡我們，以請求為你的帳戶開通權限。當 Sandboxes 全面開放時，我們會公佈定價。

沙盒是一個虛擬機器，編碼代理人在其中執行命令並編輯檔案。每個代理人會話都有專屬的沙盒，在會話期間保留其檢出的程式碼、建置產物和已安裝的工具。當代理人閒置時，沙盒會暫停；下一則訊息會從上次停下的地方繼續。

沙盒與 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 在同一機隊上運行，並位於你團隊的 <.localized_link href="/guides/features/cache">快取</.localized_link> 旁邊，因此代理人的建置可以使用與你的 CI 和本地機器相同的快取構件。

你可以透過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上運行你的 Amp 工作區的 orbs，或透過 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link> 為任何 Amp 執行緒提供一台 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上運行 Claude Managed Agents 會話和 Claude Code 雲端會話（claude.ai、桌面和流動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙盒並在其中執行命令，或透過 API 從你自己的工具執行。

## 開始使用 CLI {#cli}

使用 `tuist sandbox` 從終端機建立沙盒並在其中執行命令。

### 1. 登入 {#cli-log-in}

帳戶的任何成員都可以建立和管理其沙盒：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

對於 Linux，省略 `--platform`。傳遞 `--xcode` 並指定版本（例如 `--xcode 26.1.1`），以獲取具有該 [Xcode](#xcode) 的 Mac；這意味著 `--platform macos`。傳遞 `--vcpus` 和 `--memory-gb` 以獲得更大的 [規格](#platforms)，並傳遞 `--workspace-gb` 以獲得更大的磁碟空間。一旦沙盒開始運行，命令就會返回並列印其詳細資訊，包括其 ID。它使用目前目錄中 Tuist 專案的帳戶；傳遞 `--account` 以選擇其他帳戶。

### 3. 執行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該命令在沙盒中使用 `bash -l` 運行，如果沙盒已暫停，則會先恢復。`tuist` 會串流其輸出直到運行結束，並以命令的狀態退出；在沙盒中按 Ctrl-C 可取消它。根據需要傳遞 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最長六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示一個 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案鏡像到其中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以獲取機器可讀取的輸出。參閱 <.localized_link href="/cli/sandbox">CLI 參考</.localized_link> 了解所有選項。若要改為從程式碼驅動沙盒，請透過 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下使用相同的操作，或讓代理人透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它們。

無法互動式登入的工具（例如在 macOS 沙盒中建置的代理人外掛程式），可以改用具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 進行驗證。它可以執行帳戶成員能做的所有事情：建立沙盒、在其中執行命令，以及暫停、恢復、封存和刪除它們。整合設定由帳戶管理員保留。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像不包含 Tuist CLI，因此運行的是你專案自身固定的版本。在第一次 `tuist sandbox sync` 之後，在沙盒上的儲存庫根目錄運行 `mise install`（已安裝 `mise` 和 `brew`），然後透過 mise 運行 `tuist`，例如將 `$HOME/.local/share/mise/shims` 加入 `PATH`。

你使用 `tuist sandbox exec` 啟動的每個命令也會獲得 Tuist runner 所擁有的內容，因此沙盒中的建置可以使用你帳戶的 <.localized_link href="/guides/features/cache">快取</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以訪問的位置（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，一個用於該命令的短期身分權杖。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 至 4.217.x 版本，請先在相同命令中運行 `tuist auth login`。

權杖是為每個命令鑄造的，並且只能在該命令運行期間交換為 Tuist 權杖，因此沙盒永遠不會持有長期憑證。它授予的權限不會超過啟動命令的人或權杖對快取所能執行的操作：如果帳戶的快取僅允許權杖寫入，則成員獲得讀取權限，並且帳戶權杖需要快取範圍（例如 `ci`）以及 `account:sandboxes:write`，沙盒才能使用快取。你透過 `--env` 傳遞的變數具有優先權。

## 從編碼代理人在 Mac 上建置 {#coding-agents}

在 Linux 上運行的編碼代理人（例如雲端代理人會話）可以在 macOS 沙盒上建置、測試和運行 Apple 平台程式碼，同時在它運行的地方繼續編輯檔案。在 Amp 中，安裝 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理人（例如 Claude Code 或 Cursor）：

1. 將代理人連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的 `create_sandbox` 工具會告訴代理人如何驅動 Mac。
2. 在代理人運行的地方安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（在 ARM 上使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入不會延續到 CLI，因此要么以帳戶成員身份運行 `tuist auth login`，要么將 `TUIST_TOKEN` 設定為具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網絡訪問，請允許 `tuist.dev`。CLI 透過它將檔案上傳到 Mac，因此不需要其他網域。

代理人為每個任務建立一台 Mac，並使用專案固定的 [Xcode](#xcode)：`create_sandbox` 列出它可以選擇的 Xcode 版本，並指示代理人讀取專案的固定版本，例如 `.xcode-version`。在執行每個命令之前，它會運行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後只複製已更改的檔案。第一次同步後，它會在 Mac 上的儲存庫根目錄運行 `mise install`，以便 [專案固定的 Tuist](#tuist-in-sandbox) 就位，並登入到你帳戶的快取。然後，代理人使用 `tuist sandbox exec` 運行如 `xcodebuild` 等命令，使用 `tuist sandbox cp` 將截圖或建置好的應用程式等結果複製回來，並在任務完成後刪除 Mac。Mac 在最後一個命令執行完畢後會繼續運行 10 分鐘，以便下一個命令立即開始；`tuist sandbox pause` 可以更早地將其釋放。被遺留的 Mac 隨後會暫停，並在暫停 14 天後被刪除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（預設）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple Silicon 上運行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 選擇 Xcode {#xcode}

每個 macOS 沙盒運行一個 Xcode，你在建立時選擇它。它啟動的映像與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理人使用的工具鏈和模擬器與你的 CI 相同。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中的 `--xcode`）選擇一個，使用精確版本，如同 runner 設定檔所做的那樣：

| 位置 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | 使用 `xcode` 的 `tuist_mac_start` |
| Amp orbs | orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 會話（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果沒有指定版本**，Mac 將獲得預設版本。
- **如果請求 Tuist 不提供的版本會被拒絕**，錯誤訊息會列出你可以選擇的版本，讓你知道當前可用的內容。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 你或請求 Mac 的代理人選擇版本。MCP 工具和 Tuist Mac 外掛程式會告訴代理人匹配專案固定的版本。
- **沙盒在其生命週期內保留其 Xcode。** 若要使用另一個 Xcode 進行建置，請建立新的沙盒。`xcodebuild -version` 顯示 Mac 運行的是哪個 Xcode。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間或與 CI 作業之間不共享檔案系統、記憶體或進程。
- 沙盒屬於一個帳戶，其任何成員都可以使用和管理它們，包括服務於整合的沙盒。只有管理員可以連接整合。來自整合的會話只能訪問該整合所連接帳戶的沙盒。
- 你提供給 Tuist 以連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會加密儲存，且不再顯示。
- 沙盒可以訪問互聯網。請像對待 CI 作業一樣對待代理人從中可以訪問的內容。
