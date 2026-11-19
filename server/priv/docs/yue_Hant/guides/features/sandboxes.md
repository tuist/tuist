---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理而設嘅持久 Linux 同 macOS 虛擬機。每個代理工作階段都會分配到獨立機器，當代理閒置時會暫停，並可喺檔案完好無損嘅情況下恢復運作。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist 沙盒（包括 Linux 和 macOS）目前在我們擴展容量期間僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開通權限。當沙盒全面開放時，我們將公佈定價。

沙盒是一個虛擬機器，編碼代理在其中執行命令並編輯檔案。每個代理會話都有自己的沙盒，在會話存續期間保留其檢出的代碼、構建產物和已安裝的工具。當代理閒置時，沙盒會暫停；下一條訊息會從上次離開的地方恢復執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行在同一機隊上，位於你團隊的<.localized_link href="/guides/features/cache">緩存</.localized_link>旁邊，因此代理的構建可以使用與你的 CI 和本地機器相同的緩存構件。

你可以通過以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上運行你的 Amp 工作區的 orbs，或使用<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>為任何 Amp 線程提供用於 Xcode 構建的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上運行 Claude Managed Agents 會話和 Claude Code 雲端會話（claude.ai、桌面和移動應用，以及`claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端創建沙盒並在其中運行命令，或通過 API 從你自己的工具中運行。

## 開始使用 CLI {#cli}

使用`tuist sandbox`從終端創建沙盒並在其中運行命令。

### 1. 登入 {#cli-log-in}

帳戶的任何成員都可以創建和管理其沙盒：

```bash
tuist auth login
```

### 2. 創建沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

對於 Linux，省略`--platform`。傳遞帶有版本的`--xcode`（例如`--xcode 26.1.1`），以獲取具有該[Xcode](#xcode)的 Mac；這意味著`--platform macos`。傳遞帶有`--memory-gb`的`--vcpus`以獲得更大的[規格](#platforms)，傳遞`--guaranteed-vcpus`以保證 Linux 沙盒擁有更多[CPU](#guaranteed-cpu)資源，並傳遞`--workspace-gb`以獲得更大的磁盤空間。一旦沙盒運行，命令就會返回並打印其詳細信息，包括其 ID。它使用當前目錄中 Tuist 專案的帳戶；傳遞`--account`以選擇其他帳戶。

### 3. 運行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該命令在沙盒中使用`bash -l`運行，如果沙盒處於暫停狀態，則會先恢復。`tuist`會流式傳輸其輸出，無論運行時間多長，並以命令的狀態退出；Ctrl-C 會在沙盒中取消它。根據需要傳遞`--cwd`、`--env NAME=VALUE`和`--timeout`（最長六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單個沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案鏡像到沙盒中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看使用情況 | `tuist sandbox analytics` |

添加`--json`以獲取機器可讀的輸出。參閱<.localized_link href="/cli/sandbox">CLI 參考</.localized_link>了解所有選項。如果要從代碼驅動沙盒，請通過`/api/accounts/{account_handle}/sandboxes`下的[Tuist API](https://tuist.dev/api/docs)使用相同的操作，或讓代理通過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它們。

無法互動登入的工具（例如在 macOS 沙盒中構建的代理插件）可以改用具有`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>進行身份驗證。它可以執行帳戶成員可以執行的操作：創建沙盒、在其中運行命令，以及暫停、恢復、歸檔和刪除沙盒。集成設置由帳戶管理員保留。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像不包含 Tuist CLI，因此運行的是你專案自己鎖定的版本。在第一次`tuist sandbox sync`之後，在沙盒上的儲存庫根目錄中運行`mise install`（已安裝`mise`和`brew`）。你使用`tuist sandbox exec`啟動的每個命令都會將 mise 的 shims（`$HOME/.local/share/mise/shims`）放在`PATH`的最前面，因此`tuist`和其他 mise 工具可以在你的命令以及 Xcode 構建階段（例如 scheme 的 post-actions）中運行。

你使用`tuist sandbox exec`啟動的每個命令也會獲得 Tuist runner 所擁有的資源，因此沙盒中的構建可以使用你帳戶的<.localized_link href="/guides/features/cache">緩存</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以訪問的位置（例如在 macOS 上），同一機架中緩存的`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，一個用於該命令的短壽命身份令牌。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 到 4.217.x 版本，請在同一命令中先運行`tuist auth login`。

令牌是為每個命令生成的，並且只能在該命令運行期間交換為 Tuist 令牌，因此沙盒永遠不會持有長期有效的憑證。它授予的權限不會超過啟動命令的人或令牌對緩存所能執行的操作：帳戶成員如果其緩存僅令牌可以寫入，則獲得讀取權限，而帳戶令牌需要緩存範圍（例如`ci`）以及`account:sandboxes:write`，沙盒才能使用緩存。你通過`--env`傳遞的變量具有優先權。

## 從編碼代理在 Mac 上構建 {#coding-agents}

在 Linux 上運行的編碼代理（例如雲端代理會話）可以在 macOS 沙盒上構建、測試和運行 Apple 平台代碼，同時繼續在它運行的地方編輯檔案。在 Amp 中，安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>。對於其他代理，例如 Claude Code 或 Cursor：

1. 將代理連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的`create_sandbox`工具會告訴代理如何驅動 Mac。
2. 在代理運行的地方安裝 Tuist CLI，例如在環境的设置腳本中：`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用`tuist-linux-aarch64`）。
3. 對 CLI 進行身份驗證。MCP 伺服器的登入不會延續到 CLI，因此要么作為帳戶成員運行`tuist auth login`，要么將`TUIST_TOKEN`設置為具有`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。
4. 如果環境限制網絡訪問，請允許 `tuist.dev`。CLI 通過它將檔案上傳到 Mac，因此不需要其他網域。

代理為每個任務創建一台 Mac，並使用項目鎖定的 [Xcode](#xcode)：`create_sandbox` 列出可供選擇的 Xcode 版本，並指示代理讀取項目的鎖定版本，例如 `.xcode-version`。在執行每個命令之前，它會運行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後只複製已更改的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄運行 `mise install`，以便 [項目鎖定的 Tuist](#tuist-in-sandbox) 就位，並登入到你帳戶的緩存。然後，代理使用 `tuist sandbox exec` 運行如 `xcodebuild` 等命令，使用 `tuist sandbox cp` 將截圖或構建好的應用等結果複製回來，並在任務完成後刪除 Mac。Mac 在最後一個命令執行完畢後會保持運行 10 分鐘，以便下一個命令立即開始；`tuist sandbox pause` 可以更早地釋放它。被遺留的 Mac 隨後會暫停，並在暫停 14 天後被刪除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04。每個 Linux 沙盒擁有 16 個 vCPU，並能突發使用其運行機器的空閒核心，因此其規格決定了記憶體大小：

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`，預設)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** 沙盒在配備 Xcode 的 Apple silicon 上運行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 保證 CPU {#guaranteed-cpu}

Linux 沙盒保證每 GiB 記憶體獲得四分之一個 vCPU，例如 8 GiB 對應 2 個 vCPU，並能使用機器上空閒的更多核心，最多達 16 個 vCPU。這適合主要處於等待狀態然後突發構建的代理。當構建即使在繁忙的機器上也需要更穩定的 CPU 時，請在創建沙盒時保證 1、2、4 或 8 個 vCPU；它將獲得該值與記憶體保證值中較大者：

| 位置 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 和 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保證是下限，而非上限。** 擁有 4 個保證 vCPU 的沙盒在核心空閒時仍可突發至 16 個。在資源競爭情況下，每個沙盒按其保證比例獲得 CPU。
- **按最低保證計費。** 運行中的沙盒按其使用的 CPU 計費，但不會低於其保證值。
- **沙盒終身保留其保證。** 若要更改，請創建新沙盒。
- **macOS 沙盒始終擁有完整規格**，因此不接受保證設置。

### 選擇 Xcode {#xcode}

每個 macOS 沙盒運行一個 Xcode，你在創建時選擇。它啟動的鏡像與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 配置文件相同，因此代理使用與你的 CI 相同的工具鏈和模擬器進行構建。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中的 `--xcode`）選擇一個，使用精確版本，如同 runner 配置文件所做：

| 位置 | 方法 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 插件 | 使用 `xcode` 的 `tuist_mac_start` |
| Amp orbs | orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 會話（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果不指定版本**，Mac 將獲得預設版本。
- **Tuist 不提供的版本會被拒絕**，錯誤信息會列出你可選擇的版本，讓你知道當前可用的內容。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 由你或請求 Mac 的代理選擇版本。MCP 工具和 Tuist Mac 插件會指示代理匹配項目鎖定的版本。
- **沙盒終身保留其 Xcode。** 若要用另一個 Xcode 構建，請創建新沙盒。`xcodebuild -version` 顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機。沙盒之間以及與 CI 作業之間不共享文件系統、記憶體或進程。
- 沙盒屬於一個帳戶，其任何成員都可以使用和管理它們，包括用於集成的沙盒。只有管理員可以連接集成。來自集成的會話只能訪問該集成所連接帳戶的沙盒。
- 你提供給 Tuist 以連接集成的憑證（例如 Amp 提供者令牌或 Claude 環境密鑰）會加密存儲，且不會再次顯示。
- 沙盒可以訪問互聯網。請像對待 CI 作業一樣對待代理從中訪問的內容。
