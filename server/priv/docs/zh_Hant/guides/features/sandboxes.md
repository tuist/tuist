---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 與 Claude 等程式碼代理設計的持久性 Linux 與 macOS 虛擬機器。每個代理工作階段都會獲得專屬機器，在代理閒置時暫停，並在恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前因擴充容量而僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開啟存取權。當 Sandboxes 全面開放時，我們將公布定價。

沙盒是一台虛擬機器，讓編碼代理程式在其中執行指令並編輯檔案。每個代理程式工作階段都會獲得專屬的沙盒，並在該工作階段期間保留其檢出的程式碼、建置產物與已安裝的工具。當代理程式閒置時，沙盒會暫停；下一則訊息會從上次停止的位置繼續執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行於相同的機群，並緊鄰你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本地機器相同的快取構件。

你可以透過以下方式運用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行你的 Amp 工作區 orbs，或透過<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 對話提供一台 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙盒並在其中執行指令，或透過 API 從你自己的工具中操作。

## 從 CLI 開始使用 {#cli}

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

若為 Linux，請省略 `--platform`。若要指定具備特定 [Xcode](#xcode) 版本的 Mac，請傳入 `--xcode` 並附上版本號，例如 `--xcode 26.1.1`；這也隱含了 `--platform macos`。若要選擇更大的[規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 搭配使用；若要更大的磁碟空間，請使用 `--workspace-gb`。命令會在沙盒啟動後返回，並列印其詳細資訊（包含 ID）。它會使用目前目錄中 Tuist 專案所屬的帳戶；若要選擇其他帳戶，請傳入 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中以 `bash -l` 執行，若沙盒處於暫停狀態，會先恢復執行。`tuist` 會串流輸出內容直至指令結束，並以該指令的狀態碼退出；在沙盒中按下 Ctrl-C 可取消執行。視需要傳入 `--cwd`、`--env NAME=VALUE` 與 `--timeout`（最長六小時）。

### 常見工作 {#cli-tasks}

| 工作 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案同步至沙盒 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加入 `--json` 以取得機器可讀的輸出。所有選項請參閱<.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若想從程式碼驅動沙盒，可透過[Tuist API](https://tuist.dev/api/docs)在 `/api/accounts/{account_handle}/sandboxes` 下執行相同操作，或讓代理程式透過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用這些功能。

無法互動式登入的工具（例如在 macOS 沙盒中建置的代理程式外掛），可以改用具備 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>進行驗證。它能執行帳戶成員所能做的事：建立沙盒、在其中執行指令，以及暫停、恢復、封存與刪除沙盒。整合設定仍由帳戶管理員管理。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像檔並未內建 Tuist CLI，因此執行的是你專案所釘選的版本。首次執行 `tuist sandbox sync` 後，請在沙盒中的儲存庫根目錄執行 `mise install`（已安裝 `mise` 與 `brew`）。你以 `tuist sandbox exec` 啟動的每個指令都會將 mise 的 shim（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，因此 `tuist` 與其他 mise 工具能在你的指令以及 Xcode 建置階段（例如 scheme 的 post-actions）中執行。

你以 `tuist sandbox exec` 啟動的每個指令也會獲得 Tuist runner 所具備的環境變數，因此沙盒中的建置可以使用你帳戶的<.localized_link href="/guides/features/cache">快取</.localized_link>，無需你自行提供憑證：

- `TUIST_URL`，以及在沙盒主機可連線的情況下（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更新版本會自動使用它登入；若使用 4.215.0 至 4.217.x 版本，請在同一指令中先執行 `tuist auth login`。

權杖會為每個指令產生，且僅在該指令執行期間才能兌換為 Tuist 權杖，因此沙盒絕不會持有長期有效的憑證。它授予的權限不會超過啟動該指令的人或權杖對快取所能執行的操作：若帳戶的快取僅允許寫入權杖，則成員會獲得讀取權限；而帳戶權杖除了需要 `account:sandboxes:write` 以使用沙盒外，還需要快取範圍（例如 `ci`）才能使用快取。你透過 `--env` 傳入的變數具有較高優先順序。

## 從編碼代理程式在 Mac 上建置 {#coding-agents}

在 Linux 上執行的編碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙盒上建置、測試並執行 Apple 平台程式碼，同時持續在其運行位置編輯檔案。在 Amp 中，請安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式（例如 Claude Code 或 Cursor）：

1. 將代理程式連線至 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。其 `create_sandbox` 工具會告訴代理程式如何驅動 Mac。
2. 在代理程式運行的環境中安裝 Tuist CLI，例如在環境設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 架構使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入狀態不會延續至 CLI，因此請以帳戶成員身分執行 `tuist auth login`，或將 `TUIST_TOKEN` 設為具備 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 若環境限制網路存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳至 Mac，因此不需要其他網域。

代理程式會為每個任務建立一台 Mac，並使用專案指定的 [Xcode](#xcode)：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理程式讀取專案的指定版本（例如 `.xcode-version`）。在執行每個指令前，它會先執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製有變更的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄執行 `mise install`，以便安裝[專案指定的 Tuist](#tuist-in-sandbox) 並登入你帳戶的快取。接著，代理程式會透過 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（例如螢幕截圖或建置完成的 App）複製回來，並在任務完成後刪除該 Mac。Mac 會在最後一個指令執行完畢後繼續運行 10 分鐘，以便下一個指令能立即啟動；`tuist sandbox pause` 可讓其更早釋放資源。閒置的 Mac 會進入暫停狀態，並在暫停 14 天後被刪除。

## Linux 與 macOS {#platforms}

**Linux** 沙盒執行 Ubuntu 24.04：

- 2 vCPU、4 GiB RAM（預設）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple Silicon 上執行：

- 8 vCPU、8 GiB RAM（預設）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 選擇 Xcode 版本 {#xcode}

每個 macOS 沙盒都會執行一個 Xcode，你在建立沙盒時進行選擇。它啟動的映像檔與該 Xcode 版本的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理程式使用的工具鏈和模擬器會與你的 CI 一致。在 tuist.dev 上，macOS 沙盒目前提供以下版本：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中為 `--xcode`）選擇其中一個版本，需使用精確版本號，如同 runner 設定檔的做法：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 與 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | `tuist_mac_start` 搭配 `xcode` |
| Amp orbs | Orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 與 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **若未指定版本**，Mac 將使用預設值。
- **若指定 Tuist 未提供的版本，請求會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你了解目前可用的選項。
- **Tuist 不會讀取你儲存庫中的 `.xcode-version`。** 你需要自行或由請求 Mac 的代理程式選擇版本。MCP 工具與 Tuist Mac 外掛程式會指示代理程式比對專案指定的版本。
- **沙盒在其生命週期內會保留其 Xcode 版本。** 若要使用其他 Xcode 版本建置，請建立新的沙盒。`xcodebuild -version` 會顯示 Mac 執行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不共用檔案系統、記憶體或處理程序。
- 沙盒屬於某個帳戶，該帳戶的任何成員都可以使用和管理它們，包括用於整合服務的沙盒。只有管理員可以連接整合服務。來自整合服務的工作階段只能存取該整合服務所連接帳戶的沙盒。
- 你提供給 Tuist 以連接整合服務的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請以對待 CI 工作的方式，謹慎處理代理程式從沙盒存取的內容。
