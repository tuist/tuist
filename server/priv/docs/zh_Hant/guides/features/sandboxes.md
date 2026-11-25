---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是專為 Amp 和 Claude 等程式碼代理設計的持久性 Linux 與 macOS 虛擬機器。每個代理工作階段都會獲得專屬的機器，在代理閒置時暫停，並在恢復時保持檔案完整無缺。"
}
---
# 沙箱 {#sandboxes}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist 沙箱（Linux 與 macOS）目前因容量擴充中而採邀請制。請[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)上留言，以申請帳號存取權限。待沙箱全面開放時，將公布定價方案。

沙箱是虛擬機器，讓程式碼代理程式在其中執行指令並編輯檔案。每個代理程式工作階段都會獲得專屬沙箱，在該工作階段存續期間保留其檢出的程式碼、建置產物及已安裝的工具。當代理程式閒置時，沙箱會暫停；收到下一則訊息時，會從上次停止處繼續執行。

沙箱與<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>運行於相同的機群，並鄰近團隊的<.localized_link href="/guides/features/cache">快取</.localized_link>，因此代理程式的建置可以使用與你的 CI 和本地機器相同的快取產物。

你可以透過以下方式運用沙箱：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上執行 Amp 工作區的 orbs，或透過<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>為任何 Amp 對話提供一台 Mac 以進行 Xcode 建置。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：從終端機建立沙箱並在其中執行指令，或透過 API 由你自己的工具驅動。

## 使用 CLI 快速入門 {#cli}

使用 `tuist sandbox` 從終端機建立沙箱並在其中執行指令。

### 1. 登入 {#cli-log-in}

帳號的任何成員都可以建立及管理其沙箱：

```bash
tuist auth login
```

### 2. 建立沙箱 {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux 省略 `--platform`。若要指定具備特定 [Xcode](#xcode) 版本的 Mac，請傳入 `--xcode` 並附上版本號，例如 `--xcode 26.1.1`；這會隱含 `--platform macos`。若要選擇更大的[規格](#platforms)，請將 `--vcpus` 與 `--memory-gb` 搭配使用；若要為 Linux 沙箱保證更多 [CPU](#guaranteed-cpu)資源，請使用 `--guaranteed-vcpus`；若要取得更大磁碟空間，請使用 `--workspace-gb`。沙箱自建立起可運行兩小時，每次恢復後也會重新計算兩小時；若要設定介於 5 分鐘至一天之間的存活時間，請使用 `--lifetime-minutes`。當存活時間結束時，執行中的指令會被取消，沙箱則會暫停並封存，同時保留其檔案，因此被遺忘的沙箱不會持續佔用你帳號的容量。指令會在沙箱開始運行後返回，並列印其詳細資訊（包含 ID）。當所有主機皆忙碌時（例如 CI 工作佔用了共用的 Mac），伺服器會等待 25 秒以取得可用主機，若仍無可用資源則建立失敗並回傳 `fleet_busy`；若要持續重試最多 5 分鐘（上限一小時），請傳入 `--wait-timeout 5m`，此時錯誤原因會大約每分鐘在 stderr 重複輸出一次。此操作會使用目前目錄中 Tuist 專案所屬的帳號；若要選擇其他帳號，請傳入 `--account`。

### 3. 執行指令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

指令會在沙箱中以 `bash -l` 執行，若沙箱處於暫停狀態則會先恢復。`tuist` 會串流輸出直至指令執行完畢，並以該指令的狀態碼結束；在沙箱中按下 Ctrl-C 可取消指令。視需要傳入 `--cwd`、`--env NAME=VALUE` 與 `--timeout`（最長六小時）。

指令會與 `tuist` 分離執行，因此即使連線中斷仍能持續運作。若要將長時間建置納入具時限的工具呼叫（例如代理程式的呼叫）中，請傳入 `--wait <seconds>`：當時限先到達時，`tuist` 會讓指令繼續在背景執行，並以狀態碼 75 結束，同時列印 `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` 指令，該指令可從先前停止處繼續輸出，並最終以該指令的狀態碼結束。

### 常見任務 {#cli-tasks}

| 任務 | 指令 |
| --- | --- |
| 列出沙箱 | `tuist sandbox list` |
| 顯示單一沙箱 | `tuist sandbox show <id>` |
| 暫停或恢復 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 延長存活時間以避免過期 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| 將本地 Git 工作樹的檔案同步至沙箱 | `tuist sandbox sync <id>` |
| 複製檔案進出沙箱 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 刪除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

加入 `--json` 以取得機器可讀取的輸出。所有選項請參閱 <.localized_link href="/cli/sandbox">CLI 參考文件</.localized_link>。若想從程式碼驅動沙箱，請透過 `/api/accounts/{account_handle}/sandboxes` 下的 [Tuist API](https://tuist.dev/api/docs) 執行相同操作，或讓代理程式透過 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用這些功能。

無法進行互動式登入的工具（例如在 macOS 沙箱中建置的代理程式外掛程式），可以改用具備 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳號權杖</.localized_link> 進行驗證。它可以執行帳號成員能做的所有操作：建立沙箱、在其中執行指令，以及暫停、恢復、封存與刪除沙箱。整合設定以及在服務整合的沙箱中執行指令的權限，僅限帳號管理員持有。

### 沙箱內的 Tuist {#tuist-in-sandbox}

macOS 沙箱內建 Tuist CLI。當你的專案透過 mise 鎖定 Tuist 版本（`mise.toml` 或 `.tool-versions`）時，`tuist` 會改為執行該版本，並在首次有指令需要時安裝。你使用 `tuist sandbox exec` 啟動的每個指令，都會將 mise 的 shim（`$HOME/.local/share/mise/shims`）放在 `PATH` 的最前面，並將映像檔中的 Tuist 放在最後，因此 `tuist` 與其他 mise 工具能在你的指令以及 Xcode 建置階段（例如 scheme 的 post-actions）中執行。每台 Mac 還在 `/opt/tuist/agent-guide.md` 提供一份供程式碼代理程式使用的指南，該指南由映像檔產生，內容包含其 Xcode 與模擬器、存放庫位置，以及就緒快照所含的項目。在 Mac 上執行的 Claude Code、Codex 與 Amp 會從其指示檔案中找到這份指南。

你使用 `tuist sandbox exec` 啟動的每個指令也會獲得 Tuist runner 享有的資源，因此沙箱中的建置可以使用你帳號的 <.localized_link href="/guides/features/cache">快取</.localized_link>，無需你提供憑證：

- `TUIST_URL`，以及在沙箱主機可存取的情況下（例如在 macOS 上），同一機架中快取的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，這是該指令的短期身分權杖。Tuist CLI 4.218.0 及更新版本會自動使用它登入；若使用 4.215.0 至 4.217.x 版本，請在同一指令中先執行 `tuist auth login`。

權杖會為每個指令個別簽發，且僅在該指令執行期間可兌換為 Tuist 權杖，因此沙箱永遠不會持有長期有效的憑證。它授予的權限不會超過啟動該指令的人员或權杖對快取所能執行的操作：若帳號的快取僅允許權杖寫入，則其成員僅獲得讀取權限；而帳號權杖除了需要 `account:sandboxes:write` 以操作沙箱外，還需要快取範圍（例如 `ci`）才能使用快取。你透過 `--env` 傳入的變數具有較高優先順序。

## 從程式碼代理程式在 Mac 上建置 {#coding-agents}

在 Linux 上執行的程式碼代理程式（例如雲端代理程式工作階段）可以在 macOS 沙箱上建置、測試並執行 Apple 平台程式碼，同時繼續在其原本執行的環境中編輯檔案。在 Amp 中，請安裝 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 外掛程式</.localized_link>。對於其他代理程式（例如 Claude Code 或 Cursor）：

1. 將代理程式連接至 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>。其 `create_sandbox` 工具會告訴代理程式如何驅動 Mac。
2. 在代理程式執行的環境中安裝 Tuist CLI，例如在環境的設定腳本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 架構上使用 `tuist-linux-aarch64`）。
3. 驗證 CLI。MCP 伺服器的登入狀態不會延續至 CLI，因此請以帳號成員身分執行 `tuist auth login`，或將 `TUIST_TOKEN` 設為具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">帳號權杖</.localized_link>。
4. 若環境限制網路存取，請允許 `tuist.dev`。CLI 會透過該網域將檔案上傳至 Mac，因此不需要其他網域。
5. 可選擇讓代理程式無需每次詢問即可建立和刪除 Mac。代理程式在呼叫 `create_sandbox` 前會先詢問，因為 Mac 會計入你帳號的限制；而在執行 `delete_sandbox` 前也會詢問，因為此操作無法復原。在 Claude Code 中，請在 `.claude/settings.json` 中允許這兩項操作，並使用你註冊 MCP 伺服器時的名稱（此處為 `tuist`）：

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

若要讓代理程式執行設定，請提供以下提示：

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

代理程式會為每個任務建立一台 Mac，並使用專案指定的 [Xcode](#xcode)：`create_sandbox` 會列出可供選擇的 Xcode 版本，並指示代理程式讀取專案的指定版本，例如 `.xcode-version`。在執行每個指令前，它會執行 `tuist sandbox sync`。它會複製 Git 未忽略的檔案（無論是否已提交），之後則僅複製有變更的檔案。Mac 已預先安裝 [Tuist](#tuist-in-sandbox)（若專案有指定版本，則為該版本），並已登入你帳號的快取，代理程式會讀取一次 Mac 的指南。接著，代理程式會透過 `tuist sandbox exec` 執行如 `xcodebuild` 等指令，使用 `tuist sandbox cp` 將結果（例如螢幕截圖或建置完成的 App）複製回來，並在任務完成後刪除 Mac。Mac 會在最後一個指令執行完畢後繼續運行 10 分鐘，以便下一個指令立即啟動；使用 `tuist sandbox pause` 可更快釋放資源。遺留的 Mac 會暫停，在其兩小時的生命週期結束時歸檔，並在 14 天後刪除；代理程式會在長時間建置前延長生命週期。

## Linux 與 macOS {#platforms}

**Linux** 沙箱執行 Ubuntu 24.04。每個 Linux 沙箱擁有 16 個 vCPU，並可突發使用其所執行機器的閒置核心，因此其規格決定了記憶體大小：

- 2 GiB RAM（`--vcpus 1 --memory-gb 2`）
- 4 GiB RAM（`--vcpus 2 --memory-gb 4`，預設）
- 8 GiB RAM（`--vcpus 4 --memory-gb 8`）
- 16 GiB RAM（`--vcpus 8 --memory-gb 16`）
- 32 GiB RAM（`--vcpus 16 --memory-gb 32`）
- 44 GiB RAM（`--vcpus 16 --memory-gb 44`）

**macOS** 沙箱在搭載 Xcode 的 Apple Silicon 上執行：

- 8 vCPU，8 GiB RAM（預設）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 保證 CPU {#guaranteed-cpu}

Linux 沙箱保證每 GiB 記憶體獲得四分之一個 vCPU，例如 8 GiB 對應 2 vCPU，並可使用機器上最多達 16 vCPU 的閒置資源。這適合主要處於等待狀態、然後突發進行建置的代理程式。當建置即使在繁忙的機器上也需要更穩定的 CPU 時，請在建立沙箱時保證其獲得 1、2、4 或 8 個 vCPU；它將獲得該保證值與記憶體保證值中較大者：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 與 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保證是下限，而非上限。** 擁有 4 個保證 vCPU 的沙箱在核心閒置時仍可突發至 16 個。在資源競爭情況下，每個沙箱按其保證比例獲得 CPU。
- **計費以保證值為最低標準。** 運行中的沙箱按其使用的 CPU 計費，但不會低於其保證值。
- **沙箱在其生命週期內保持其保證值。** 若要變更，請建立新的沙箱。
- **macOS 沙箱始終擁有其完整規格**，因此不接受保證值。

### 選擇 Xcode {#xcode}

每個 macOS 沙箱執行一個 Xcode，你在建立時選擇。它啟動的映像檔與該 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 設定檔相同，因此代理程式使用的工具鏈和模擬器與你的 CI 一致。在 tuist.dev 上，macOS 沙箱目前提供：

- `26.6`（預設）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中為 `--xcode`）選擇一個，使用精確版本，如同 runner 設定檔所示：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 與 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 外掛程式 | `tuist_mac_start` 搭配 `xcode` |
| Amp orbs | orb 類型 `macos-xcode-26-1-1`（參見 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 與 Claude Managed Agents | 環境上的 `xcode_version`，或每個 Managed Agents 工作階段（參見 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **若未指定版本**，Mac 將使用預設值。
- **Tuist 不提供的版本會被拒絕**，錯誤訊息會列出你可選擇的版本，讓你了解目前可用的選項。
- **Tuist 不會讀取你專案庫的 `.xcode-version`。** 由你或請求 Mac 的代理程式選擇版本。MCP 工具與 Tuist Mac 外掛程式會指示代理程式比對專案鎖定的版本。
- **沙箱在其生命週期內保持其 Xcode。** 若要使用其他 Xcode 進行建置，請建立新的沙箱。`xcodebuild -version` 顯示 Mac 執行的 Xcode 版本。

## 安全性 {#security}

- 每個沙箱都是獨立的虛擬機器。沙箱之間以及與 CI 工作之間不共用檔案系統、記憶體或處理程序。
- 沙箱屬於某個帳號，該帳號的任何成員都可以使用和管理它們。服務於整合功能（例如 Amp orb 或 Claude Code 工作階段）的沙箱會保留該工作階段的作業內容與憑證：成員可以查看、暫停、恢復、封存和刪除它們，但只有管理員可以在其中執行命令或上傳檔案。只有管理員可以連接整合功能。來自整合功能的工作階段只能存取該整合功能所連接帳號的沙箱。
- 你提供給 Tuist 以連接整合功能的憑證（例如 Amp provider token 或 Claude environment key）會以加密方式儲存，且不會再次顯示。
- 沙箱可以存取網際網路。請以對待 CI 工作的方式，處理代理程式從沙箱存取的內容。
