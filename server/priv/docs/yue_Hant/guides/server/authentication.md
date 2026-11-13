---
{
  "title": "驗證",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何從 CLI 向 Tuist 伺服器進行驗證。"
}
---
# 驗證 {#authentication}

要與伺服器互動，CLI 需要使用 [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者身份、帳戶身份或使用 OIDC token 進行驗證。

## 以使用者身份 {#as-a-user}

當你在本機使用 CLI 時，我們建議以使用者身份進行驗證。要以使用者身份驗證，你需要執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成網頁驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存一個長期有效的 refresh token 和一個短期有效的 access token。目錄中的每個檔案代表你驗證過的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果 access token 已過期，CLI 將使用 refresh token 獲取新的 access token。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC tokens {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的 secret。在支援的 CI 環境中運行時，CLI 會自動檢測 OIDC token 提供者，並將 CI 提供的 token 交換為 Tuist access token。

### 支援的提供者 {#supported-ci-providers}

Tuist 識別這些 CI 提供者，並透過你的儲存庫連接將它們的 token 映射到專案：

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) orbs 透過你連接到 Tuist 帳戶的 Amp workspaces 進行驗證，而 [Claude Code sessions](#claude-code-sessions) 則透過你連接以在 Tuist Sandboxes 上運行的 Claude Code environments 進行驗證。

任何其他發出 OpenID Connect tokens 的身份提供者，都可以透過 [workload identity trust policy](#workload-identity-trust-policies) 進行驗證，你只需為帳戶中的所有當前和未來專案配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

對於 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連接到你的 Tuist 專案。

2. **授予 identity token**：在 GitHub Actions 上，賦予 job `permissions: id-token: write`；在 CircleCI 和 Bitrise 上，為專案啟用 OIDC。從 Tuist 4.218.0 開始，當 CLI 未登入且未設定 `TUIST_TOKEN` 時，它會檢測 CI 環境並在第一個請求中交換 identity token，因此無需登入步驟。較早的版本需要先執行 `tuist auth login`，你仍然可以執行它以明確登入，並在交換被拒絕時及早失敗。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取特定於提供者的配置範例。

### Amp orbs {#amp-orbs}

[Amp](https://ampcode.com) orbs 可以鑄造識別其 Amp workspace 的 OIDC tokens。將 workspace 連接到你的 Tuist 帳戶一次，該 workspace 中任何 orb 的 Tuist CLI 和 `tuist_ex` Mix tasks 都會自行登入，無需儲存的 token 或登入步驟：

1. 尋找 IDs：在運行於 orb 中的 workspace thread 中，執行 `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`。
2. 在你的 Tuist 帳戶中，開啟 **Settings → Integrations**，在 Amp card 上選擇 **Connect workspace**，並貼上 workspace ID。若只允許來自一個 Amp project 的 orbs，也請貼上其 project ID。你需要是帳戶管理員或擁有者。
3. 在 workspace 的 orbs 中使用 Tuist。當未登入時，CLI 或 Mix task 會檢測 orb，使用 `amp orb id-token --audience https://tuist.dev` 鑄造 token，並將其交換為 Tuist session。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

如同 [Amp's OIDC guide](https://ampcode.com/manual/orbs/oidc) 中的信任配置，Tuist 會驗證每個 token 上的 Amp 簽名，僅在其 audience 為 `https://tuist.dev`、其 `token_use` 為 `exchanged`、其 `workspace_id` 與連接的 workspace 匹配，以及對於限制為專案的連接，其 `project_id` 與該專案匹配時才接受。其 `sub` 必須命名與這些 claims 相同的 workspace，對於專案連接則為相同的專案：`workspace:<workspace-id>:project:<project-id>:…`，這是 `amp orb id-token` 預設鑄造的。

連接所允許的每個 orb 都會獲得對帳戶擁有的所有當前和未來專案的 CI 存取權限，包括 cache uploads。它還獲得 `account:sandboxes:write` scope，因此它可以像帳戶成員一樣建立 <.localized_link href="/guides/features/sandboxes">sandboxes</.localized_link> 並在其中執行指令，例如從 Linux orb 在 macOS sandbox 上建置。僅連接你信任其成員擁有該存取權限的 workspaces。仔細檢查 ID：Tuist 無法確認你屬於你連接的 workspace。如果一個 workspace 連接到多個 Tuist 帳戶，orbs 必須將 `TUIST_OIDC_ACCOUNT` 設定為要登入的帳戶；在 Amp project 的環境中設定它也可以將登入鎖定到你的帳戶。workspace 外部的 threads 沒有 workspace identity，無法使用連接。從 Amp card 斷開 workspace 以停止新登入；已發出的 session 在一小時後過期前保持有效。Sessions 不需要 refresh token：當一個即將過期時，orb 中的 CLI 會鑄造一個新的 Amp token 並再次交換，因此只要 workspace 保持連接，長時間運行的 orbs 就會保持登入狀態。

你在連接 workspace 之前為 Amp issuer 建立的信任政策，在設定 `TUIST_OIDC_ACCOUNT` 時仍然有效。

### Claude Code sessions {#claude-code-sessions}

自託管環境中的每個 Claude Code cloud session 都攜帶一個由 Anthropic 簽名的 identity token (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`)。在你 <.localized_link href="/guides/features/sandboxes/claude#claude-code">連接以在 Tuist Sandboxes 上運行</.localized_link> 的環境中，Tuist 將其作為 `TUIST_OIDC_TOKEN` 傳遞給 session，因此 Tuist CLI 和 `tuist_ex` Mix tasks 會自行登入。

Tuist 會驗證 Anthropic 的簽名，僅當 token 為 session token（`ccr:role` 為 `session_worker`）且其 audience 中命名的環境已連接到 Tuist 帳戶並啟用時，才接受該 token。連接環境的每個 session 都會獲得對帳戶擁有的所有當前和未來專案的 CI 存取權限，包括 cache uploads，因此你的 Claude organization 允許使用該環境的任何人都可以發佈到你的 cache。Session 的 Tuist sessions 會在一小時後或隨其 identity token 過期，以較早者為準；該 token 是 session 啟動時使用的 token，預設持續四小時，因此較長的 session 會失去 Tuist 存取權限，直到其下一則訊息在新的 runner 上恢復為止。斷開或停用環境以停止新登入。

### Workload identity trust policies {#workload-identity-trust-policies}

信任政策允許來自另一個身份提供者（例如部署平台、Kubernetes cluster 或自管 CI 系統）的工作負載，在無需長期有效的 Tuist secret 的情況下存取專案。提供者必須：

- 在公共地址上透過 HTTPS 可達。Tuist 不會跟隨重定向，也不會連接到私人或內部網絡地址，包括來自自託管 Tuist 伺服器的連接。
- 簽發使用非對稱金鑰簽名的 JWTs，例如 `RS256` 或 `ES256`。未簽名的 token 和使用共享 secret 簽名的 token（`HS256` 及類似）會被拒絕。
- 在固定的 HTTPS URL 上將其簽名金鑰發佈為 JSON Web Key Set (JWKS)。回應最多為 64 KiB，且最多包含 20 個金鑰。
- 在每個 token 中包含到期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise issuers 保留用於上述基於 repository 的流程，不能用於信任政策。

> [!NOTE]
> 對於自託管部署，在配置 workload identities 或將 jobs 移動到它們之前，請應用數據庫遷移並升級每個提供服務的 Tuist server replica。然後將 CLI 或 Elixir integration 升級到支持 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise jobs 繼續使用基於 repository 的授權，不需要帳戶 handle。在切換生產 jobs 之前，驗證與預期工作負載的短期 token 交換和 cache 操作。要停止新交換，請刪除政策；允許已發出的 Tuist access tokens 最多一小時後過期。刪除政策不會立即撤銷這些 token。

#### Create a policy {#create-a-trust-policy}

在 Tuist dashboard 中，打開你帳戶的 **Settings** > **Authentication** 並找到 **Workload identities** 部分。你必須是帳戶管理員（或個人帳戶的所有者）。每個帳戶最多可以有 20 個政策。配置一次身份以獲得帳戶範圍的 CI 存取權限；無需選擇專案。

使用 **Workload identities** 旁邊的開關打開政策表單。當帳戶有保存的身份時，開關初始為開啟狀態，並在保存後保持開啟。對於沒有身份的帳戶，開關初始為關閉。該部分出現在組織的 **SCIM provisioning** 下方。隱藏表單會保留你的草稿，並且不會停用工作負載認證：保存的身份卡片和設置文檔鏈接保持可見。每張卡片顯示身份的名稱、issuer 和 JWKS URLs、audience、精確的 JSON claims、帳戶範圍的 scope 和創建時間。使用卡片上的操作刪除身份。

選擇 **Custom provider** 以輸入以下字段，或選擇 **Fly.io Machines** 以從你的 organization slug 和數字 organization 及 application IDs 生成它們。Fly 模板保持在 **Advanced configuration** 下可編輯生成的 issuer、JWKS URL 和 claims。更改模板或輔助值會保留你手動編輯的字段。如果你的 issuer、JWKS URL 或 claims 覆蓋了模板，Tuist 會展開 **Advanced configuration** 並顯示警告，以便你審查將要保存的政策。切換回 **Custom provider** 以在沒有 Fly 輔助的情況下繼續。模板僅填充配置，不會改變 Tuist 驗證 token 的方式。

| Field | Description |
| --- | --- |
| Name | 用於識別政策的標籤，在帳戶內唯一。 |
| Issuer URL | Token 的 `iss` claim。必須完全匹配，包括任何尾隨斜杠。 |
| JWKS URL | 提供者簽名金鑰的 HTTPS URL。Tuist 直接使用此 URL，不會讀取提供者的 OpenID Connect discovery document，因此請從提供者的文檔或從 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| Audience | Token 必須為其簽發的 audience，預設為 `tuist`。Token 的 `aud` 必須等於它，或者當 `aud` 是列表時包含它。使用只有 Tuist 接受的值，這樣為其他服務鑄造的 token 就不能在此重放。 |
| Claims | 一個包含 1 到 10 個 claims 的 JSON 對象，token 必須包含這些 claims，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字符串、有符號 64 位整數或布爾值，並且必須完全匹配，包括其類型：`"123"` 不匹配 `123`。不允許嵌套對象、列表以及時間或 token claims，如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個政策授予對 **帳戶擁有的所有當前和未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在創建第一個專案之前配置身份。這不會授予帳戶管理權限或對另一個帳戶的存取權限。

每個能夠獲得具有匹配 claims 的 token 的工作負載都可以存取所有這些專案，因此請選擇提供者保證且無人可以重用的 claims。優先選擇穩定的數字 ID，而不是可以在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共用身份提供者上，將政策綁定到你的組織或租戶 **和** 目標應用程式、專案或服務帳戶。像 `main` 這樣的分支名稱、像 `production` 這樣的環境，或僅通用的角色本身並不是身份邊界：另一個租戶可能會獲得具有相同值的 token。例如，GitLab.com 政策必須包含目標專案的穩定 `project_id`，而不僅僅是 `ref`。匹配的 token 授予帳戶範圍的 CI 存取權限，包括快取寫入，因此信任不相關工作負載的政策可能會導致快取投毒。

Tuist 僅對其自身 JWKS URL 持有簽署 token 金鑰的政策授予存取權限，並在檢查 issuer、audience、過期時間、not-before 時間（允許最多 60 秒的時鐘偏差）以及每個 claim 之後進行。簽發的一小時 CI token 是帳戶範圍的，而不是專案 ID 的快照：它包括簽發後創建或轉移到帳戶中的專案。專案授權仍然需要當前的帳戶所有權，因此將專案轉移出去會移除其在該帳戶 token 下的存取權限。

#### 驗證工作負載 {#authenticate-a-workload}

1. 從你的提供者請求具有政策 audience 的身份 token。
2. 將 `TUIST_OIDC_TOKEN` 設置為該 token，並將 `TUIST_OIDC_ACCOUNT` 設置為擁有該專案的 Tuist 帳戶句柄。每個信任策略交換都需要帳戶。它僅選擇查找位置，本身不授予任何權限。
3. 運行 Tuist。當沒有 `TUIST_TOKEN` 或有效的存儲憑據可用時，CLI 和 Elixir 集成會自動交換 token。`tuist auth login` 和 `mix tuist.login` 顯式執行相同的交換。

生成的 Tuist 訪問 token 僅具有 `ci` 範圍組，並涵蓋所選帳戶擁有的所有當前和未來專案。如果帳戶中有超過 20 個政策匹配同一個 token，或者它們使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會刷新這些會話。訪問 token 在一小時後過期，且沒有刷新 token。提供者身份 token 通常僅在幾分鐘內有效，因此保留舊的 `TUIST_OIDC_TOKEN` 不是續訂策略：對於運行時間超過一小時的作業，請在 Tuist 會話過期之前請求新的身份 token 並再次登錄。刪除政策會阻止新的交換，但已簽發的訪問 token 在過期前仍然有效。

Tuist 在專用且大小受限的快取中快取提供者的簽名金鑰，成功獲取後最多保留 15 分鐘。條目可能會更早被驅逐並再次獲取。失敗的獲取不會被快取。如果你的提供者輪換金鑰，它應在使用新金鑰簽署 token 之前至少 15 分鐘將其發布在其 JWKS 中，因為使用不在快取集中的金鑰簽署的 token 會被拒絕，直到快取過期。只有在 JWKS 包含單個符合條件的簽名金鑰時，才接受沒有金鑰 ID (`kid`) 的 token。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 字節的字符串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用 token 輸入，不是繞過伺服器信任的方法。它優先於 CI 提供者檢測，伺服器仍然僅接受內建提供者和具有匹配信任策略的身份。不要將身份 token 放入 `TUIST_TOKEN`，它預期的是 Tuist 憑據。

如果交換失敗，請檢查政策中的 issuer、audience 和每個 claim 是否與 token 完全匹配，JWKS URL 是否提供簽署 token 的金鑰，政策是否未被刪除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了擁有該專案的帳戶。為了避免暴露哪些身份受信任，Tuist 對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身份](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本地 `/.fly/api` Unix socket 請求短生命週期的簽名身份 token，無需 Fly API token 或長效 Tuist 秘密。Fly token 標識組織和應用程式，而不是源代碼庫，因此請使用信任策略而不是連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部簽發的身份 token 中獲取 issuer (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。Issuer 是 `https://oidc.fly.io/<organization-slug>`。使用數字 ID，而不是組織或應用程式名稱。
2. 使用 **Fly.io Machines** 模板 [創建信任策略](#create-a-trust-policy)，並輸入組織 slug 和兩個數字 ID。它會填寫下面的值並將 ID 保持為字符串。你也可以使用 **Custom provider** 手動輸入它們；在 claims 中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | Issuer URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audience | `tuist` |
   | Claims | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設置為擁有該專案的 Tuist 帳戶句柄（不是 Fly 組織 slug），請求 audience 為 `tuist` 的 token，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

對於初始設置，你可以在匯出 token 後且取消設置之前，僅在本地檢查身份欄位。這會解碼 claims 以進行配置；Tuist 在認證期間單獨驗證簽名：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要列印或提交 token 本身。授權 Fly 應用程式中的每個 Machine 都可以對 Tuist 帳戶中的所有當前和未來專案進行認證。為每個額外的應用程式創建單獨的政策。Fly 身份 token 在大約十分鐘後過期，因此在長時間運行的 Machine 上，請在一個小時的 Tuist 會話過期之前請求新的 token 並再次運行 `tuist auth login`。

### OIDC token 範圍 {#oidc-token-scopes}

OIDC token 被授予 `ci` 範圍組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供了對連接到儲存庫的所有專案的存取權限。對於連接的 Amp 工作區、連接的 Claude Code 環境和工作負載身份信任策略，這提供了對所選帳戶擁有的所有當前和未來專案的存取權限，而不授予專案創建、專案管理、runner 管理或帳戶成員管理權限。有關 `ci` 範圍包含內容的詳細資訊，請參閱 [Scope groups](#scope-groups)。

> [!TIP]
> **安全優勢**
>
> OIDC 認證比長效 token 更安全，因為：
> - 無需輪換或管理秘密
> - Token 生命週期短
> - 認證與你的儲存庫身份或明確授權的工作負載身份綁定


## Gradle 插件認證 {#gradle-plugin-authentication}

Gradle 插件使用 Tuist CLI 的認證狀態，不會定義獨立的登入流程。只需透過 CLI 認證一次，插件就會重複使用這些憑證。

對於專案和伺服器配置，包括 `project` 和 `url`，請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

本地使用時，請運行：

```bash
tuist auth login
```

對於 CI，請使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 認證</.localized_link>（建議在可用時使用）
- 透過 `TUIST_TOKEN` 進行 <.localized_link href="/guides/server/authentication#continuous-integration">帳戶 Token 認證</.localized_link>

對於自託管的 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並運行標準登入流程。URL 會從插件使用的同一個配置文件中解析。

配置好認證後，正常運行你的 Gradle 快取命令和任務。

## 帳戶 Token {#account-tokens}

對於不支援 OIDC 的 CI 環境，或者當你需要對權限進行細粒度控制時，你可以使用帳戶 Token。帳戶 Token 允許你精確指定 Token 可以存取的範圍和專案。

### 創建帳戶 Token {#creating-an-account-token}

創建帳戶 Token 最簡單的方法是從儀表板進行：

1. 在 Tuist 儀表板中打開組織。
2. 前往 **Settings** > **Tokens**。
3. 選擇 **Generate token**。
4. 選擇名稱、可選的過期時間、專案存取權限以及 Token 所需的範圍。
5. 在關閉對話框之前複製生成的 Token 值。Token 值僅顯示一次。

你也可以從 CLI 創建帳戶 Token，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想要 Token 存取的專案的帳戶句柄。這可以是組織帳戶，不一定是你的個人帳戶。

該命令接受以下選項：

| 選項 | 描述 |
| --- | --- |
| `--scopes` | 必填。要授予 Token 的範圍列表，以空格分隔。 |
| `--name` | 必填。Token 的唯一標識符（1-32 個字符，僅限字母數字、連字號和下劃線）。 |
| `--expires` | 可選。Token 應何時過期。使用如 `30d`（天）、`6m`（月）或 `1y`（年）等格式。如果未指定，Token 永不過期。 |
| `--projects` | 將 Token 限制為特定的專案句柄。如果未指定，Token 可以存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 描述 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進制文件 |
| `account:cache:write` | 上傳帳戶範圍的快取二進制文件 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:registry:read` | 從 Swift 包註冊表讀取 |
| `account:registry:write` | 發布到 Swift 包註冊表 |
| `account:runners:read` | 讀取 runner 作業、工作流、配置文件和卷 |
| `account:runners:write` | 管理 runner 配置文件並刪除 runner 卷 |
| `account:sandboxes:write` | 創建沙盒並在其中運行命令，就像帳戶成員一樣 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 創建、更新和刪除專案。創建專案需要具有存取所有專案權限的 Token |
| `project:cache:read` | 下載快取二進制文件 |
| `project:cache:write` | 上傳快取二進制文件 |
| `project:bundles:read` | 查看 Bundle |
| `project:bundles:write` | 上傳 Bundle |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取構建分析 |
| `project:builds:write` | 上傳構建分析 |
| `project:runs:read` | 讀取命令運行 |
| `project:runs:write` | 創建和更新命令運行 |

### 範圍組 {#scope-groups}

範圍組提供了一種便捷的方式，透過單一標識符授予多個相關範圍。當你使用範圍組時，它會自動擴展以包含其包含的所有單獨範圍。

| 範圍組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請創建一個帶有 `ci` 範圍組的帳戶 Token 以驗證你的 CI 工作流。在儀表板中，生成 Token 時選擇 **CI** 預設值。

你也可以從 CLI 創建相同的 Token：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這將創建一個具有典型 CI 操作所需所有範圍（快取、預覽、Bundle、測試、構建和運行）的 Token。將生成的 Token 作為密鑰存儲在你的 CI 環境中，並將其設置為 `TUIST_TOKEN` 環境變量。

### 管理帳戶 Token {#managing-account-tokens}

在帳戶儀表板中打開 **Settings** > **Tokens** 以查看帳戶 Token、檢查 Token 的範圍和專案存取權限，以及在輪換期間撤銷 Token。

列出帳戶的所有 Token：

```bash
tuist account tokens list account-handle
```

按名稱撤銷 Token：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用帳戶 Token {#using-account-tokens}

帳戶 Token 應定義為環境變量 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用帳戶 Token**
>
> 在以下情況下使用帳戶 Token：
> - 在不支援 OIDC 的 CI 環境中進行身份驗證
> - 對 Token 可以執行的操作進行細粒度控制
> - 可以存取帳戶內多個專案的 Token
> - 自動過期的限時 Token
