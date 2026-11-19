---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 和 Claude 等程式碼代理設計的持久化 Linux 與 macOS 虛擬機器。每個代理工作階段都擁有專屬機器，當代理閒置時會暫停運作，並在恢復時保持檔案完整無損。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist 沙盒（Linux 與 macOS）目前因容量擴充中，僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)上留言，為你的帳號申請存取權限。待沙盒全面開放時，將公布定價方案。

沙盒是虛擬機器，供編碼代理程式執行指令並編輯檔案。每個代理程式工作階段都有專屬沙盒，在該工作階段期間保留其檢出的程式碼、建置產物及已安裝的工具。當代理程式閒置時，沙盒會暫停；收到下一則訊息時，會從上次停止處繼續執行。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行於相同的機群，並鄰近你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式運用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行 Amp 工作區的 orbs，或透過<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 對話提供 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及`claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙盒並在當中執行指令，或透過 API 由你自己的工具驅動。

## 使用 CLI 快速入門 {#cli}

使用`tuist sandbox`從終端機建立沙盒並在其中執行指令。

### 1. 登入 {#cli-log-in}

帳號的任何成員皆可建立並管理其沙盒：

```bash
tuist auth login
```

### 2. 建立沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

若為 Linux，請省略`--platform`。若要指定具備特定[Xcode](#xcode)版本的 Mac，請傳入`--xcode`並附上版本號碼（例如`--xcode 26.1.1`）；這也隱含`--platform macos`。若要選擇更大的[規格](#platforms)，請將`--vcpus`與`--memory-gb`一起傳入；若要確保 Linux 沙盒擁有更多[CPU](#guaranteed-cpu)資源，請使用`--guaranteed-vcpus`；若要取得更大的磁碟空間，請使用`--workspace-gb`。命令會在沙盒啟動後返回，並列印其詳細資訊（包含 ID）。它會使用目前目錄中 Tuist 專案所屬的帳號；若要選擇其他帳號，請傳入`--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中以`bash -l`執行；若沙盒處於暫停狀態，會先恢復執行。`tuist`會串流輸出內容直至指令結束，並以該指令的狀態碼退出；在沙盒中按下 Ctrl-C 可取消執行。視需要傳入`--cwd`、`--env NAME=VALUE`與`--timeout`（最長六小時）。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 將本地 Git 工作樹的檔案同步至沙盒 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加上`--json`以取得機器可讀取的輸出。查看所有選項請參閱<.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若想從程式碼驅動沙盒，可透過[Tuist API](https://tuist.dev/api/docs)在`/api/accounts/{account_handle}/sandboxes`下執行相同操作，或讓代理程式透過<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用這些功能。

無法進行互動式登入的工具（例如在 macOS 沙盒中建置的代理程式外掛程式），可以改用具備`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳號權杖</.localized_link>進行驗證。它能執行帳號成員可做的所有操作：建立沙盒、在其中執行指令，以及暫停、恢復、封存與刪除沙盒。整合設定仍由帳號管理員管理。

### 沙盒內的 Tuist {#tuist-in-sandbox}

沙盒映像檔未內建 Tuist CLI，因此執行的是你專案所固定的版本。首次執行`tuist sandbox sync`後，請在沙盒中的儲存庫根目錄執行`mise install`（已安裝`mise`與`brew`）。你以`tuist sandbox exec`啟動的每個指令，都會將 mise 的 shim（`$HOME/.local/share/mise/shims`）置於`PATH`的最前方，因此`tuist`與其他 mise 工具能在你的指令以及 Xcode 建置階段（例如方案的 post-actions）中執行。

你以`tuist sandbox exec`啟動的每個指令也會獲得與 Tuist runner 相同的環境，因此沙盒中的建置可以使用你帳號的<.localized_link href="/guides/features/cache">快取</.localized_link>，無需手動傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可達的情況下（例如在 macOS 上），同一機架中快取的`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更新版本會自動使用它登入；若使用 4.215.0 至 4.217.x 版本，請在同一指令中先執行`tuist auth login`。

權杖會為每個指令單獨簽發，且僅在該指令執行期間可兌換為 Tuist 權杖，因此沙盒不會持有長期有效的憑證。它授予的權限不會超過啟動該指令的人或權杖對快取所能執行的操作：若帳號的快取僅允許寫入權杖，則成員僅能獲得讀取權限；而帳號權杖除了需要`account:sandboxes:write`之外，還需要快取範圍（例如`ci`），沙盒才能使用快取。你透過`--env`傳入的變數具有較高優先順序。

## 從編碼代理程式在 Mac 上建置 {#coding-agents}

在 Linux 上執行的編碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙盒上建置、測試並執行 Apple 平台程式碼，同時繼續在其運行位置編輯檔案。在 Amp 中，請安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式（例如 Claude Code 或 Cursor）：

1. 將代理程式連接至 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。其`create_sandbox`工具會告訴代理程式如何驅動 Mac。
2. 在代理程式運行的環境中安裝 Tuist CLI，例如在環境設定腳本中：`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 架構上使用`tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入狀態不會延續至 CLI，因此請以帳號成員身分執行`tuist auth login`，或將`TUIST_TOKEN`設為具備`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳號權杖</.localized_link>。
4. 若環境限制網路存取，請允許 `tuist.dev`。CLI 會透過它將檔案上傳至 Mac，因此不需要其他網域。

代理程式會為每個任務建立一台 Mac，並使用專案鎖定的 [Xcode](#xcode)：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理程式讀取專案的鎖定設定（例如 `.xcode-version`）。在執行每個指令之前，它會執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製變更過的檔案。首次同步後，它會在 Mac 上的儲存庫根目錄執行 `mise install`，以便安裝[專案鎖定的 Tuist](#tuist-in-sandbox) 並登入你帳號的快取。接著，代理程式會透過 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（例如螢幕截圖或建置完成的 App）複製回來，並在任務完成後刪除 Mac。Mac 會在最後一個指令執行完畢後繼續運行 10 分鐘，以便下一個指令立即啟動；`tuist sandbox pause` 可讓其更早釋放。閒置的 Mac 會進入暫停狀態，並在暫停 14 天後刪除。

## Linux 與 macOS {#platforms}

**Linux** 沙盒執行 Ubuntu 24.04。每個 Linux 沙盒擁有 16 個 vCPU，並能突發使用其所運行機器的閒置核心，因此其規格決定了記憶體大小：

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`，預設值）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** 沙盒在搭載 Xcode 的 Apple Silicon 上運行：

- 8 vCPU，8 GiB RAM（預設值）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 保證 CPU {#guaranteed-cpu}

Linux 沙盒保證每 GiB 記憶體獲得四分之一個 vCPU（例如 8 GiB 對應 2 vCPU），並能使用機器上多達 16 個 vCPU 的閒置核心。這適合主要處於等待狀態、偶爾突發建置的代理程式。當建置即使在繁忙機器上也需要更穩定的 CPU 時，請在建立沙盒時保證分配 1、2、4 或 8 個 vCPU；它將獲得該數值與記憶體保證數值中較大者：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 與 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保證是下限，而非上限。** 擁有 4 個保證 vCPU 的沙盒在核心閒置時仍可突發至 16 個。在資源競爭情況下，每個沙盒會按其保證比例獲得 CPU。
- **計費以保證值為最低標準。** 運行中的沙盒會按其使用的 CPU 計費，但不會低於其保證值。
- **沙盒會終身保留其保證配置。** 若要變更，請建立新的沙盒。
- **macOS 沙盒始終擁有其完整規格**，因此不採用保證配置。

### 選擇 Xcode 版本 {#xcode}

每個 macOS 沙盒運行單一版本的 Xcode，你在建立時選擇該版本。它啟動的映像檔與該 Xcode 版本的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理程式會使用與你的 CI 相同的工具鏈和模擬器進行建置。在 tuist.dev 上，macOS 沙盒目前提供以下版本：

- `26.6`（預設值）
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
- **Tuist 未提供的版本會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你了解目前可用的選項。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 由你或請求 Mac 的代理程式選擇版本。MCP 工具與 Tuist Mac 外掛程式會指示代理程式比對專案鎖定的版本。
- **沙盒會終身保留其 Xcode 版本。** 若要使用其他 Xcode 進行建置，請建立新的沙盒。`xcodebuild -version` 可顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不共用檔案系統、記憶體或處理序。
- 沙盒隸屬於帳號，其任何成員皆可使用與管理沙盒，包括用於整合的沙盒。僅管理員可連接整合。來自整合的工作階段僅能存取該整合所連接帳號的沙盒。
- 你提供給 Tuist 以連接整合的憑證（例如 Amp provider token 或 Claude environment key）會以加密方式儲存，且不會再次顯示。
- 沙盒可以存取網際網路。請以對待 CI 工作的方式，處理代理程式從沙盒存取的內容。
