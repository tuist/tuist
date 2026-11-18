---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 和 Claude 等程式碼代理設計的持久化 Linux 與 macOS 虛擬機器。每個代理工作階段都會分配到專屬的機器，在代理閒置時暫停運作，並在恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **限邀請使用**
>
> Tuist Sandboxes（Linux 與 macOS）目前為限邀請使用，我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以申請你帳戶的存取權。當沙盒全面開放時，我們將公布定價。

沙盒是一個虛擬機器，程式碼代理在其中執行指令並編輯檔案。每個代理工作階段都會獲得專屬的沙盒，在該工作階段的生命週期內保留其檢出的程式碼、建置產物與已安裝的工具。當代理進入閒置狀態時，沙盒會暫停；下一則訊息會從上次停止的地方繼續執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行於相同的機群，並緊鄰你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理的建置可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式來使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行你的 Amp 工作區中的 orbs，或使用<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 對話提供一台 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 `claude --cloud`）。
- **[The Tuist CLI](#cli)**：從你的終端機建立沙盒並在其中執行指令，或透過 API 從你自己的工具中執行。

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

對於 Linux，省略 `--platform`。若要指定具備特定 [Xcode](#xcode) 版本的 Mac，請傳入帶有版本號的 `--xcode`（例如 `--xcode 26.1.1`）；這會隱含 `--platform macos`。若要選擇更大的[規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 一起傳入；若要更大的磁碟空間，請傳入 `--workspace-gb`。一旦沙盒開始運行，指令就會返回並列印其詳細資訊，包括其 ID。它會使用目前目錄中 Tuist 專案的帳戶；若要選擇其他帳戶，請傳入 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中使用 `bash -l` 執行，如果沙盒處於暫停狀態，會先恢復執行。`tuist` 會串流輸出內容直到指令結束，並以指令的狀態碼退出；在沙盒中按下 Ctrl-C 可取消執行。視需要傳入 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最長六小時）。

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

加上 `--json` 以取得機器可讀的輸出。查看所有選項請參閱 <.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若要從程式碼驅動沙盒，請透過 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下執行相同的操作，或讓代理透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它們。

無法進行互動式登入的工具（例如在 macOS 沙盒中建置的代理外掛程式），可以改用具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 進行驗證。它可以執行帳戶成員能做的所有事項：建立沙盒、在其中執行指令，以及暫停、恢復、封存和刪除沙盒。整合設定仍由帳戶管理員管理。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像檔並未內建 Tuist CLI，因此執行的是你專案所釘選的版本。在第一次 `tuist sandbox sync` 之後，在沙盒中的儲存庫根目錄執行 `mise install`（已安裝 `mise` 和 `brew`）。你使用 `tuist sandbox exec` 啟動的每個指令都會將 mise 的 shims（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，因此 `tuist` 和其他 mise 工具會在你的指令以及 Xcode 建置階段（例如 scheme 的 post-actions）中執行。

你使用 `tuist sandbox exec` 啟動的每個指令也會獲得與 Tuist runner 相同的環境，因此沙盒中的建置可以使用你帳戶的 <.localized_link href="/guides/features/cache">快取</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可連線的情況下（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更高版本會自動使用它登入；若使用 4.215.0 至 4.217.x 版本，請在同一指令中先執行 `tuist auth login`。

權杖是為每個指令產生的，且僅在該指令執行期間才能兌換為 Tuist 權杖，因此沙盒永遠不會持有長期有效的憑證。它授予的權限不會超過啟動該指令的人或權杖對快取所能執行的操作：對於其快取僅允許權杖寫入的帳戶成員，他們會獲得讀取權限；而帳戶權杖需要快取範圍（例如 `ci`），並搭配 `account:sandboxes:write`，沙盒才能使用快取。你透過 `--env` 傳遞的變數具有優先權。

## 從程式碼代理在 Mac 上建置 {#coding-agents}

在 Linux 上運行的程式碼代理（例如雲端代理工作階段）可以在 macOS 沙盒上建置、測試和執行 Apple 平台程式碼，同時繼續在其運行位置編輯檔案。在 Amp 中，請安裝 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理（例如 Claude Code 或 Cursor）：

1. 將代理連線至 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。其 `create_sandbox` 工具會告訴代理如何驅動 Mac。
2. 在代理運行的位置安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入狀態不會延續到 CLI，因此請以帳戶成員身分執行 `tuist auth login`，或將 `TUIST_TOKEN` 設定為具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網路存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳至 Mac，因此不需要其他網域。

代理會為每個任務建立一台 Mac，並使用專案鎖定的 [Xcode](#xcode)：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理讀取專案的鎖定版本，例如 `.xcode-version`。在執行每個指令之前，它會執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製有變更的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄執行 `mise install`，以便讓 [專案鎖定的 Tuist](#tuist-in-sandbox) 就位，並登入你帳戶的快取。接著，代理會使用 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，透過 `tuist sandbox cp` 將結果（例如螢幕截圖或建置完成的 App）複製回來，並在任務完成後刪除 Mac。Mac 會在最後一個指令執行完畢後繼續運行 10 分鐘，以便下一個指令能立即啟動；`tuist sandbox pause` 可讓其更早釋放。若 Mac 被遺留下來，它會進入暫停狀態，並在暫停 14 天後被刪除。

## Linux 與 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04：

- 2 vCPU、4 GiB RAM（預設）
- 4 vCPU、8 GiB RAM
- 8 vCPU、16 GiB RAM

**macOS** 沙盒在配備 Xcode 的 Apple Silicon 上運行：

- 8 vCPU、8 GiB RAM（預設）
- 8 vCPU、16 GiB RAM
- 8 vCPU、24 GiB RAM

### 選擇 Xcode 版本 {#xcode}

每個 macOS 沙盒會運行一個 Xcode，你可以在建立時選擇。它會啟動與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同的映像檔，因此代理會使用與你的 CI 相同的工具鏈和模擬器進行建置。在 tuist.dev 上，macOS 沙盒目前提供以下版本：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中為 `--xcode`）選擇其中一個版本，並使用確切版本號，如同 runner 設定檔的做法：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 與 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | `tuist_mac_start` 搭配 `xcode` |
| Amp orbs | Orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 與 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **若未指定版本**，Mac 將使用預設版本。
- **若請求 Tuist 未提供的版本，系統會拒絕**，並列出你可選擇的版本，讓你了解目前可用的選項。
- **Tuist 不會讀取你儲存庫中的 `.xcode-version`。** 你需要自行或由請求 Mac 的代理來選擇版本。MCP 工具與 Tuist Mac 外掛程式會指示代理比對專案鎖定的版本。
- **沙盒在其生命週期內會保留其 Xcode。** 若要使用其他 Xcode 進行建置，請建立新的沙盒。`xcodebuild -version` 會顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不會共用檔案系統、記憶體或處理程序。
- 沙盒屬於某個帳戶，該帳戶的任何成員都可以使用和管理它們，包括用於整合的沙盒。只有管理員可以連線整合。來自整合的工作階段只能存取該整合所連線帳戶的沙盒。
- 你提供給 Tuist 以連線整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請像對待 CI 工作一樣，謹慎處理代理從沙盒存取的內容。
