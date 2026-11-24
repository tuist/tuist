---
{
  "title": "身份驗證",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何從 CLI 向 Tuist 伺服器進行身份驗證。"
}
---
# 驗證 {#authentication}

要與伺服器互動，CLI 需要使用 [Bearer 驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者、帳戶或 OIDC token 進行驗證。

## 以使用者身份 {#as-a-user}

當你在本機使用 CLI 時，我們建議以使用者身份進行驗證。要以使用者身份驗證，你需要執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成基於網頁的驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存一個長期有效的 refresh token 和一個短期有效的 access token。目錄中的每個檔案代表你驗證過的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果 access token 已過期，CLI 將使用 refresh token 獲取新的 access token。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC tokens {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的密鑰。在支援的 CI 環境中運行時，CLI 會自動檢測 OIDC token 提供者，並將 CI 提供的 token 交換為 Tuist access token。

### 支援的提供者 {#supported-ci-providers}

Tuist 識別這些 CI 提供者，並透過你的儲存庫連接將它們的 token 映射到專案：

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) orbs 透過你連接到 Tuist 帳戶的 Amp workspace 進行驗證，而 [Claude Code sessions](#claude-code-sessions) 則透過你連接以在 Tuist Sandboxes 上運行的 Claude Code 環境進行驗證。

任何其他發行 OpenID Connect tokens 的身份提供者都可以透過 [工作負載身份信任策略](#workload-identity-trust-policies) 進行驗證，你只需為帳戶中的所有現有和未來專案配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

對於 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連接到你的 Tuist 專案。

2. **授予身份 token**：在 GitHub Actions 上，給予 job `permissions: id-token: write`；在 CircleCI 和 Bitrise 上，為專案啟用 OIDC。從 Tuist 4.218.0 開始，當 CLI 未登入且未設定 `TUIST_TOKEN` 時，它會檢測 CI 環境並在第一個請求中交換身份 token，因此無需登入步驟。較早的版本需要先執行 `tuist auth login`，你仍然可以執行它以明確登入，並在交換被拒絕時及早失敗。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取特定於提供者的配置範例。

### Amp orbs {#amp-orbs}

[Amp](https://ampcode.com) orbs 可以鑄造識別其 Amp workspace 的 OIDC tokens。將 workspace 連接到你的 Tuist 帳戶一次，該 workspace 中任何 orb 的 Tuist CLI 和 `tuist_ex` Mix tasks 都會自行登入，無需儲存的 token 或登入步驟：

1. 查找 IDs：在運行於 orb 中的 workspace thread 中，執行 `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`。
2. 在你的 Tuist 帳戶中，開啟 **Settings → Integrations**，在 Amp 卡片上選擇 **Connect workspace**，並貼上 workspace ID。若只允許單一 Amp 專案的 orbs，也請貼上其 project ID。你需要是帳戶管理員或擁有者。
3. 在 workspace 的 orbs 中使用 Tuist。當未登入時，CLI 或 Mix task 會檢測 orb，使用 `amp orb id-token --audience https://tuist.dev` 鑄造 token，並將其交換為 Tuist session。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

如同 [Amp 的 OIDC 指南](https://ampcode.com/manual/orbs/oidc) 中的信任配置，Tuist 會驗證每個 token 上 Amp 的簽名，僅當其 audience 為 `https://tuist.dev`、其 `token_use` 為 `exchanged`、其 `workspace_id` 與連接的 workspace 匹配，並且對於限制為專案的連接，其 `project_id` 與該專案匹配時才接受。其 `sub` 必須命名與這些 claims 相同的 workspace，對於專案連接則為相同的專案：`workspace:<workspace-id>:project:<project-id>:…`，這是 `amp orb id-token` 預設鑄造的。

連接允許的每個 orb 都會獲得對帳戶擁有的所有現有和未來專案的 CI 存取權限，包括快取上傳。它還獲得 `account:sandboxes:write` 範圍，因此它可以像帳戶成員一樣建立 <.localized_link href="/guides/features/sandboxes">sandboxes</.localized_link> 並在其中執行指令，例如從 Linux orb 在 macOS sandbox 上進行建置。僅連接你信任其成員擁有該存取權限的 workspaces。仔細檢查 ID：Tuist 無法確認你屬於所連接的 workspace。如果一個 workspace 連接到多個 Tuist 帳戶，orbs 必須將 `TUIST_OIDC_ACCOUNT` 設定為要登入的帳戶；在 Amp 專案的環境中設定它也可以將登入鎖定到你的帳戶。workspace 外部的 threads 沒有 workspace 身份，無法使用連接。從 Amp 卡片斷開 workspace 以停止新登入；已發出的 session 保持有效，直到一小時後過期。Sessions 不需要 refresh token：當一個即將過期時，orb 中的 CLI 會鑄造一個新的 Amp token 並再次交換，因此只要 workspace 處於連接狀態，長時間運行的 orbs 就會保持登入。

你在連接 workspace 之前為 Amp issuer 建立的信任策略，在設定 `TUIST_OIDC_ACCOUNT` 時仍然有效。

### Claude Code sessions {#claude-code-sessions}

自託管環境中的每個 Claude Code cloud session 都攜帶一個由 Anthropic 簽署的身份 token (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`)。在你 <.localized_link href="/guides/features/sandboxes/claude#claude-code">連接以在 Tuist Sandboxes 上運行</.localized_link> 的環境中，Tuist 將其作為 `TUIST_OIDC_TOKEN` 傳遞給 session，因此 Tuist CLI 和 `tuist_ex` Mix tasks 會自行登入。

Tuist 會驗證 Anthropic 的簽名，僅當 token 為 session token（`ccr:role` 為 `session_worker`）且其 audience 中命名的環境已連接至 Tuist 帳戶並啟用時，才接受該 token。每個已連接環境的 session 都會獲得對帳戶擁有的所有現有和未來專案的 CI 存取權限，包括快取上傳，並能像帳戶成員一樣建立和使用帳戶的 sandboxes。因此，任何獲你 Claude 組織允許使用該環境的人都可以發布到你的快取並啟動 sandboxes，例如用於建置的 Mac。Session 的 Tuist sessions 會在一小時後或隨其身份 token 過期，以較早者為準；該 token 是 session 啟動時使用的 token，預設持續四小時，因此較長的 session 會失去 Tuist 存取權限，直到其下一則訊息在新的 runner 上恢復為止。斷開連接或停用環境以停止新登入。

### Workload identity trust policies {#workload-identity-trust-policies}

信任策略允許來自另一個身份提供者（例如部署平台、Kubernetes 叢集或自管 CI 系統）的工作負載，在無需長期有效的 Tuist 密鑰的情況下存取專案。提供者必須：

- 可透過公開地址經 HTTPS 連線。Tuist 不會追蹤重新導向，也不會連接至私人或內部網路地址，包括來自自託管 Tuist 伺服器的連線。
- 簽發使用非對稱金鑰簽署的 JWT，例如 `RS256` 或 `ES256`。未簽署的 token 以及使用共享密鑰簽署的 token（`HS256` 及類似方式）會被拒絕。
- 在固定的 HTTPS URL 上將其簽章金鑰發布為 JSON Web Key Set (JWKS)。回應大小不得超過 64 KiB，且最多包含 20 個金鑰。
- 每個 token 都必須包含到期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise issuers 保留供上述基於儲存庫的流程使用，不能用於信任策略。

> [!NOTE]
> 對於自託管部署，請在設定工作負載身份或將作業移至它們之前，套用資料庫遷移並升級每個提供服務的 Tuist server replica。然後將 CLI 或 Elixir 整合升級至支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise 作業會繼續使用基於儲存庫的授權，不需要帳戶 handle。在切換生產作業之前，請驗證與預期工作負載的短期 token 交換和快取操作。要停止新交換，請移除策略；允許已發出的 Tuist access tokens 最多一小時後過期。刪除策略不會立即撤銷這些 token。

#### 建立策略 {#create-a-trust-policy}

在 Tuist dashboard 中，開啟你帳戶的 **Settings** > **Authentication**，並找到 **Workload identities** 區段。你必須是帳戶管理員（或个人帳戶的擁有者）。每個帳戶最多可以有 20 個策略。為帳戶範圍的 CI 存取權限設定一次身份；無需選擇專案。

使用 **Workload identities** 旁邊的開關來開啟策略表單。當帳戶有已儲存的身份時，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身份的帳戶，開關預設為關閉。該區段出現在組織的 **SCIM provisioning** 下方。隱藏表單會保留你的草稿，並且不會停用工作負載驗證：已儲存身份的卡片和設定文件連結仍然可見。每張卡片顯示身份的名稱、issuer 和 JWKS URLs、audience、精確的 JSON claims、帳戶範圍和建立時間。使用卡片上的操作移除身份。

選擇 **Custom provider** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織 slug 以及數字的組織和應用程式 ID 產生它們。Fly 範本會在 **Advanced configuration** 下保持產生的 issuer、JWKS URL 和 claims 可編輯。更改範本或輔助值會保留你手動編輯的欄位。如果你的 issuer、JWKS URL 或 claims 覆蓋了範本，Tuist 會展開 **Advanced configuration** 並顯示警告，以便你檢視將要儲存的策略。切換回 **Custom provider** 以在不使用 Fly 輔助工具的情況下繼續。範本僅填寫配置，不會改變 Tuist 驗證 token 的方式。

| 欄位 | 描述 |
| --- | --- |
| 名稱 | 用於識別策略的標籤，在帳戶內必須唯一。 |
| Issuer URL | Token 的 `iss` claim。必須完全匹配，包括任何尾隨斜線。 |
| JWKS URL | 提供者簽章金鑰的 HTTPS URL。Tuist 直接使用此 URL，不會讀取提供者的 OpenID Connect discovery document，因此請從提供者的文件或從 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| Audience | Token 必須針對其簽發的 audience，預設為 `tuist`。Token 的 `aud` 必須等於它，或者當 `aud` 為列表時包含它。使用只有 Tuist 接受的值，這樣為其他服務鑄造的 token 就不能在此重放。 |
| Claims | 一個包含 1 到 10 個 token 必須包含的 claims 的 JSON 物件，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、帶符號的 64 位整數或布林值，並且必須完全匹配，包括其類型：`"123"` 不匹配 `123`。不允許嵌套物件、列表以及時間或 token claims，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個策略授予對 **帳戶擁有的所有現有和未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在建立第一個專案之前設定身份。這不會授予帳戶管理權限或對另一個帳戶的存取權限。

每個能夠獲取具有匹配 claims 的 token 的工作負載都可以存取所有這些專案，因此請選擇提供者保證且無人可以重用的 claims。優先選擇穩定的數字 ID，而不是可以在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共用的身份提供者上，將策略綁定到你的組織或租戶 **以及** 目標應用程式、專案或服務帳戶。分支名稱如 `main`、環境如 `production` 或通用角色本身並非身份邊界：其他租戶可能會取得具有相同值的 token。例如，GitLab.com 策略必須包含目標專案的穩定 `project_id`，而不僅是 `ref`。匹配的 token 會授予整個帳戶的 CI 存取權限，包括快取寫入，因此信任不相關工作負載的策略可能會導致快取污染。

Tuist 僅對其自身 JWKS URL 持有簽署 token 金鑰的策略授予存取權限，並在檢查 issuer、audience、過期時間、not-before 時間（允許最多 60 秒的時鐘偏差）以及每個 claim 之後進行。簽發的一小時 CI token 適用於整個帳戶，而非專案 ID 的快照：它包含簽發後建立或轉移到該帳戶的專案。專案授權仍需要當前的帳戶所有權，因此將專案轉移出去會移除其在該帳戶 token 下的存取權限。

#### 驗證工作負載 {#authenticate-a-workload}

1. 向你的提供者請求具有策略 audience 的身份 token。
2. 將 `TUIST_OIDC_TOKEN` 設定為該 token，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶 handle。每個信任策略交換都需要帳戶。它僅選擇查找位置，本身不授予任何權限。
3. 執行 Tuist。當沒有 `TUIST_TOKEN` 或有效的儲存憑證可用時，CLI 和 Elixir 整合會自動交換 token。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

產生的 Tuist 存取 token 僅具有 `ci` 範圍組，並涵蓋所選帳戶擁有的所有現有和未來專案。如果帳戶中超過 20 個策略匹配同一個 token，或者它們使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會刷新這些工作階段。存取 token 在一小時後過期，且沒有刷新 token。提供者身份 token 通常僅有效幾分鐘，因此保留舊的 `TUIST_OIDC_TOKEN` 並非續期策略：對於運行時間超過一小時的工作，請在 Tuist 工作階段過期前請求新的身份 token 並再次登入。移除策略會停止新的交換，但已簽發的存取 token 在過期前仍然有效。

Tuist 會在專用且大小受限的快取中快取提供者的簽章金鑰，成功獲取後最多保留 15 分鐘。條目可能會更早被驅逐並再次獲取。失敗的獲取不會被快取。如果你的提供者輪換金鑰，它應在使用新金鑰簽署 token 之前至少 15 分鐘將其發佈到其 JWKS 中，因為使用不在快取集合中的金鑰簽署的 token 會被拒絕，直到快取過期。只有當 JWKS 包含單個符合條件的簽章金鑰時，才接受沒有金鑰 ID (`kid`) 的 token。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用 token 輸入，並非繞過伺服器信任的方法。它優先於 CI 提供者檢測，且伺服器仍然僅接受內建提供者和具有匹配信任策略的身份。不要將身份 token 放入 `TUIST_TOKEN`，因為它期望的是 Tuist 憑證。

如果交換失敗，請檢查策略中的 issuer、audience 和每個 claim 是否與 token 完全匹配，JWKS URL 是否提供簽署 token 的金鑰，策略是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了擁有該專案的帳戶。為了避免暴露哪些身份受信任，Tuist 對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身份](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本地 `/.fly/api` Unix socket 請求短期簽名的身份 token，無需 Fly API token 或長期有效的 Tuist 秘密。Fly token 識別組織和應用程式，而非原始碼倉庫，因此請使用信任策略而不是連接 GitHub 倉庫：

1. 從在你的 Fly Machine 內部簽發的身份 token 中獲取 issuer (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。Issuer 為 `https://oidc.fly.io/<organization-slug>`。請使用數字 ID，而非組織或應用程式名稱。
2. 使用 **Fly.io Machines** 範本 [建立信任策略](#create-a-trust-policy)，並輸入組織 slug 和兩個數字 ID。它會填寫下面的值並將 ID 保持為字串。你也可以使用 **Custom provider** 手動輸入它們；在 claims 中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | Issuer URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audience | `tuist` |
   | Claims | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶 handle（而非 Fly 組織 slug），請求 audience 為 `tuist` 的 token，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

對於初始設定，你可以在匯出 token 之後且取消設定之前，僅在本地檢查身份欄位。這會解碼 claims 以進行配置；Tuist 會在驗證期間單獨驗證簽名：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要列印或提交 token 本身。授權 Fly 應用程式中的每個 Machine 都可以驗證 Tuist 帳戶中的所有現有和未來專案。為每個額外的應用程式建立單獨的策略。Fly 身份 token 在大約十分鐘後過期，因此在長時間運行的 Machine 上，請在 one-hour Tuist 工作階段過期前請求新的 token 並再次執行 `tuist auth login`。

### OIDC token 範圍 {#oidc-token-scopes}

OIDC token 被授予 `ci` 範圍組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供了對連接到倉庫的所有專案的存取權限。對於連接的 Amp 工作區、連接的 Claude Code 環境和工作負載身份信任策略，這提供了對所選帳戶擁有的所有現有和未來專案的存取權限，而不授予專案建立、專案管理、runner 管理或帳戶成員管理權限。有關 `ci` 範圍包含內容的詳細資訊，請參閱 [範圍組](#scope-groups)。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長期有效的 token 更安全，因為：
> - 無需輪換或管理秘密
> - Token 有效期短
> - 驗證與你的倉庫身份或明確授權的工作負載身份綁定


## Gradle 外掛程式驗證 {#gradle-plugin-authentication}

Gradle 外掛程式使用 Tuist CLI 的驗證狀態，並未定義獨立的登入流程。只需透過 CLI 驗證一次，外掛程式便會重複使用這些憑證。

對於專案和伺服器配置（包括 `project` 和 `url`），請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

本機使用時，請執行：

```bash
tuist auth login
```

CI 環境中，請選擇以下其中一種方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 驗證</.localized_link>（建議在可用時使用）
- 透過 `TUIST_TOKEN` 進行 <.localized_link href="/guides/server/authentication#continuous-integration">帳戶 token 驗證</.localized_link>

對於自託管的 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並執行標準登入流程。URL 會從外掛程式使用的同一個配置檔案中解析。

配置好驗證後，即可正常執行 Gradle 快取指令和任務。

## 帳戶 token {#account-tokens}

對於不支援 OIDC 的 CI 環境，或當你需要對權限進行細粒度控制時，可以使用帳戶 token。帳戶 token 允許你精確指定 token 可以存取的範圍和專案。

### 建立帳戶 token {#creating-an-account-token}

最簡單的建立帳戶 token 方式是透過儀表板：

1. 在 Tuist 儀表板中開啟組織。
2. 前往 **設定** > **Tokens**。
3. 選擇 **產生 token**。
4. 選擇名稱、可選的過期時間、專案存取權限以及 token 所需的範圍。
5. 在關閉對話框之前複製產生的 token 值。Token 值僅顯示一次。

你也可以從 CLI 建立帳戶 token，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想要 token 存取之專案的帳戶 handle。這可以是組織帳戶，不一定是你的個人帳戶。

該指令接受以下選項：

| 選項 | 說明 |
| --- | --- |
| `--scopes` | 必填。以空格分隔的範圍清單，用於授予 token。 |
| `--name` | 必填。Token 的唯一識別碼（1-32 個字元，僅限字母數字、連字號和下劃線）。 |
| `--expires` | 可選。Token 的過期時間。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。如果未指定，token 永不過期。 |
| `--projects` | 將 token 限制為特定的專案 handle。如果未指定，token 可以存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 說明 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進位檔案 |
| `account:cache:write` | 上傳帳戶範圍的快取二進位檔案 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:pulse:write` | 使用 token 作為 DSN 金鑰，從 Sentry SDK 將錯誤發送到帳戶的 Pulse |
| `account:registry:read` | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發布到 Swift 套件註冊表 |
| `account:runners:read` | 讀取 runner 作業、工作流程、設定檔和磁碟區 |
| `account:runners:write` | 管理 runner 設定檔並刪除 runner 磁碟區 |
| `account:sandboxes:write` | 建立沙盒並在其中執行指令，如同帳戶成員 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要具有所有專案存取權限的 token |
| `project:cache:read` | 下載快取二進位檔案 |
| `project:cache:write` | 上傳快取二進位檔案 |
| `project:bundles:read` | 檢視套件 |
| `project:bundles:write` | 上傳套件 |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取建構分析 |
| `project:builds:write` | 上傳建構分析 |
| `project:runs:read` | 讀取指令執行 |
| `project:runs:write` | 建立和更新指令執行 |

### 範圍群組 {#scope-groups}

範圍群組提供了一種方便的方式，透過單一識別碼授予多個相關範圍。當你使用範圍群組時，它會自動展開以包含其包含的所有個別範圍。

| 範圍群組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立具有 `ci` 範圍群組的帳戶 token 以驗證你的 CI 工作流程。在儀表板中，產生 token 時選擇 **CI** 預設值。

你也可以從 CLI 建立相同的 token：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 操作所需所有範圍（快取、預覽、套件、測試、建構和執行）的 token。將產生的 token 作為秘密儲存在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### 管理帳戶 token {#managing-account-tokens}

在帳戶儀表板中開啟 **設定** > **Tokens** 以檢視帳戶 token、檢查 token 的範圍和專案存取權限，以及在輪換期間撤銷 token。

列出帳戶的所有 token：

```bash
tuist account tokens list account-handle
```

按名稱撤銷 token：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用帳戶 token {#using-account-tokens}

帳戶 token 應定義為環境變數 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用帳戶 token**
>
> 當你需要以下情況時，請使用帳戶 token：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對 token 可執行的操作進行細粒度控制
> - 可以存取帳戶內多個專案的 token
> - 會自動過期的時間限制 token
