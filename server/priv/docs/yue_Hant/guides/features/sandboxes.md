---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒係專為 Amp 同 Claude 等編碼代理設計嘅持久 Linux 同 macOS 虛擬機器。每個代理工作階段都會分配獨立機器，當代理閒置時會暫停運作，恢復時檔案保持完整。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist 沙盒（包括 Linux 和 macOS）目前僅限邀請，因為我們正在擴展容量。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，為你的帳戶申請存取權限。當沙盒全面開放時，我們會公佈定價。

沙盒是一個虛擬機器，讓編碼代理程式在其中執行指令並編輯檔案。每個代理程式工作階段都會獲得專屬的沙盒，在該工作階段期間保留其檢出內容、建置產物和已安裝的工具。當代理程式閒置時，沙盒會暫停；下一個訊息會從上次停止的地方恢復。

沙盒與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>在同一機群上運行，並緊鄰你團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式來使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行你的 Amp 工作空間 orbs，或透過<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 執行緒提供用於 Xcode 建置的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段和 Claude Code 雲端工作階段（claude.ai、桌面和流動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙盒並在其中執行指令，或透過 API 從你自己的工具中執行。

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

Linux 請省略 `--platform`。若要指定具有特定 [Xcode](#xcode) 版本的 Mac，請傳遞 `--xcode` 並附上版本號（例如 `--xcode 26.1.1`）；這意味著 `--platform macos`。若要使用更大的[規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 一起傳遞；若要保證 Linux 沙盒擁有更多 [CPU](#guaranteed-cpu)，請傳遞 `--guaranteed-vcpus`；若要使用更大的磁碟，請傳遞 `--workspace-gb`。沙盒從建立之時起運行兩小時，每次恢復後亦重新計算兩小時；若需設定介乎 5 分鐘至一天之間的壽命，請傳遞 `--lifetime-minutes`。當壽命結束時，正在執行的指令會被取消，沙盒會暫停並封存，同時保留其檔案，這樣被遺忘的沙盒就不會繼續佔用你帳戶的容量。當沙盒開始運行時，指令會返回並列印其詳細資料，包括其 ID。當所有主機都忙碌時（例如當 CI 工作佔用了共享的 Mac），伺服器會等待 25 秒以獲取一台主機，否則建立會因 `fleet_busy` 而失敗；請傳遞 `--wait-timeout 5m` 以持續嘗試最多 5 分鐘（最多一小時），錯誤原因會大約每分鐘在 stderr 上重複一次。它使用目前目錄中 Tuist 專案的帳戶；若要選擇其他帳戶，請傳遞 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

該指令在沙盒中使用 `bash -l` 執行，如果沙盒處於暫停狀態，會先恢復。`tuist` 會串流輸出直至指令執行完畢，並以指令的狀態碼退出；在沙盒中按 Ctrl-C 可取消它。視需要傳遞 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最長六小時）。

該指令與 `tuist` 分離運行，因此即使連線中斷也能繼續執行。若要將長時間的建置納入具有時間限制的工具呼叫（例如代理程式的呼叫）中，請傳遞 `--wait <seconds>`：當時間先到達時，`tuist` 會讓指令繼續運行，以狀態碼 75 退出，並列印 `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` 指令，該指令會從停止之處繼續輸出，並以指令的狀態碼退出。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 顯示單一沙盒 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 延長運行時間超過到期日 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| 將本地 Git 工作樹的檔案鏡像到沙盒中 | `tuist sandbox sync <id>` |
| 複製檔案進出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以獲得機器可讀取的輸出。參閱<.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>了解所有選項。若要改為從程式碼驅動沙盒，請透過 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下使用相同的操作，或讓代理程式透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它們。

無法進行互動式登入的工具（例如在 macOS 沙盒中建置的代理程式外掛程式）可以改用具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>進行驗證。它可以執行帳戶成員能做的所有事情：建立沙盒、在其中執行指令，以及暫停、恢復、封存和刪除沙盒。整合設定以及在服務整合的沙盒中執行指令的權限，仍保留給帳戶管理員。

### 沙盒內的 Tuist {#tuist-in-sandbox}

macOS 沙盒內建 Tuist CLI。當你的專案透過 mise（`mise.toml` 或 `.tool-versions`）固定 Tuist 版本時，`tuist` 會執行該版本，並在首次有指令需要時安裝。你使用 `tuist sandbox exec` 啟動的每個指令，都會將 mise 的 shim（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，並將映像中的 Tuist 放在最後，因此 `tuist` 和你其他的 mise 工具可以在你的指令以及 Xcode 建置階段（例如 scheme 的 post-actions）中運行。每台 Mac 還在 `/opt/tuist/agent-guide.md` 處載有一份供編碼代理程式使用的指南，該指南由其映像生成：包含其 Xcode 和模擬器、儲存庫的位置，以及就緒快照所包含的內容。在 Mac 上運行的 Claude Code、Codex 和 Amp 會從其指令檔案中找到它。

你使用 `tuist sandbox exec` 啟動的每個指令也會獲得 Tuist runner 所擁有的資源，因此沙盒中的建置可以使用你帳戶的<.localized_link href="/guides/features/cache">快取</.localized_link>，而無需你傳遞憑證：

- `TUIST_URL`，以及在沙盒主機可以存取的情況下（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，一個用於該指令的短期身分權杖。Tuist CLI 4.218.0 及更高版本會自動使用它登入；對於 4.215.0 至 4.217.x 版本，請先在相同指令中執行 `tuist auth login`。

權杖是為每個指令鑄造的，並且只能在該指令運行期間兌換為 Tuist 權杖，因此沙盒永遠不會持有長期有效的憑證。它授予的權限永遠不會超過啟動指令的人或權杖對快取所能執行的操作：如果帳戶的快取僅允許權杖寫入，則成員會獲得讀取權限；而帳戶權杖除了需要 `account:sandboxes:write` 來使用沙盒外，還需要快取範圍（例如 `ci`）才能讓沙盒使用快取。你透過 `--env` 傳遞的變數具有優先權。

## 從編碼代理程式在 Mac 上建置 {#coding-agents}

在 Linux 上運行的編碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙盒上建置、測試和運行 Apple 平台代碼，同時繼續在其運行位置編輯檔案。在 Amp 中，安裝<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式，例如 Claude Code 或 Cursor：

1. 將代理程式連接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。它的 `create_sandbox` 工具會告訴代理程式如何驅動 Mac。
2. 在代理程式運行的環境中安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入狀態不會延續到 CLI，因此你要么以帳戶成員身分執行 `tuist auth login`，要么將 `TUIST_TOKEN` 設為具有 `account:sandboxes:write` 範圍的<.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。
4. 如果環境限制網絡存取，請允許 `tuist.dev`。CLI 透過它將檔案上傳到 Mac，因此不需要其他網域。
5. 可選地，讓代理程式無需每次都詢問即可建立和刪除 Mac。代理程式在呼叫 `create_sandbox` 之前會詢問，因為 Mac 會計入你帳戶的限制；在執行 `delete_sandbox` 之前也會詢問，因為該操作無法撤銷。在 Claude Code 中，在 `.claude/settings.json` 中允許這兩項操作，使用你註冊 MCP 伺服器時的名稱（此處為 `tuist`）：

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

要讓代理程式執行設定，請給予它以下提示：

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

代理程式會為每個任務建立一台 Mac，並使用專案鎖定的 [Xcode](#xcode) 版本：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理程式讀取專案的鎖定版本，例如 `.xcode-version`。在執行每個指令之前，它會運行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則只複製已變更的檔案。Mac 已經安裝了 [Tuist](#tuist-in-sandbox)（如果專案有鎖定版本，則為該版本），並已登入你帳戶的快取，代理程式會閱讀一次 Mac 的指南。然後，代理程式使用 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（如截圖或建置好的應用程式）複製回來，並在任務完成後刪除 Mac。Mac 在最後一個指令結束後會繼續運行 10 分鐘，以便下一個指令立即開始；`tuist sandbox pause` 可以更快地釋放它。遺留的 Mac 會暫停，在其兩小時的生命週期結束時被歸檔，並在 14 天後刪除；代理程式會在長時間建置前延長生命週期。

## Linux 和 macOS {#platforms}

**Linux** 沙盒運行 Ubuntu 24.04。每個 Linux 沙盒都有 16 個 vCPU，並能突發使用其運行機器的空閒核心，因此其規格決定了記憶體大小：

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`，預設）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** 沙盒在配備 Xcode 的 Apple silicon 上運行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 保證 CPU {#guaranteed-cpu}

Linux 沙盒保證每 GiB 記憶體獲得四分之一個 vCPU，例如 8 GiB 對應 2 個 vCPU，並能使用機器上空閒的更多核心，最多達 16 個 vCPU。這適合代理程式，因為它們大部分時間在等待，然後突發式建置。當建置即使在繁忙的機器上也需要更穩定的 CPU 時，請在建立沙盒時保證 1、2、4 或 8 個 vCPU；它將獲得該保證值與記憶體保證值中較大者：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 和 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保證是下限，而非上限。** 擁有 4 個保證 vCPU 的沙盒在核心空閒時仍會突發至 16 個。在資源競爭情況下，每個沙盒根據其保證比例獲得 CPU。
- **按最低保證計費。** 運行中的沙盒按其使用的 CPU 計費，但絕不會低於其保證值。
- **沙盒在其生命週期內保持其保證。** 若要更改，請建立新的沙盒。
- **macOS 沙盒始終擁有其完整規格**，因此不接受保證。

### 選擇 Xcode {#xcode}

每個 macOS 沙盒運行一個 Xcode，你在建立時選擇。它啟動的映像與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理程式使用與你的 CI 相同的工具鏈和模擬器進行建置。在 tuist.dev 上，macOS 沙盒目前提供：

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
| Amp 的 Tuist Mac 外掛程式 | 使用 `xcode` 的 `tuist_mac_start` |
| Amp orbs | Orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果沒有指定版本**，Mac 會使用預設值。
- **Tuist 不提供的版本會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你知道目前有哪些可用。
- **Tuist 不會讀取你儲存庫的 `.xcode-version`。** 由你或要求 Mac 的代理程式選擇版本。MCP 工具和 Tuist Mac 外掛程式會指示代理程式匹配專案鎖定的版本。
- **沙盒在其生命週期內保持其 Xcode。** 若要使用另一個 Xcode 進行建置，請建立新的沙盒。`xcodebuild -version` 顯示 Mac 運行的 Xcode 版本。

## 安全性 {#security}

- 每個沙盒都是獨立的虛擬機器。沙盒之間以及與 CI 工作之間不共享檔案系統、記憶體或行程。
- 沙盒屬於一個帳戶，其任何成員都可以使用和管理它們。為整合服務的沙盒（例如 Amp orb 或 Claude Code 工作階段）會保留該工作階段的工作和憑證：成員可以查看、暫停、恢復、歸檔和刪除它們，但只有管理員可以在其中運行命令或向其上傳檔案。只有管理員可以連接整合。來自整合的工作階段只能訪問該整合所連接帳戶的沙盒。
- 你提供給 Tuist 以連接整合的憑證（例如 Amp 提供者權杖或 Claude 環境金鑰）會以加密方式儲存，且不再顯示。
- 沙盒可以訪問網際網路。請像對待 CI 工作一樣對待代理程式從中可以訪問的內容。
