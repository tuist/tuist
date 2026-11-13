---
{
  "title": "身分驗證",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何從 CLI 向 Tuist 伺服器進行身分驗證。"
}
---
# 驗證 {#authentication}

要與伺服器互動，CLI 需要使用 [Bearer 驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者、帳號或 OIDC Token 進行驗證。

## 以使用者身分 {#as-a-user}

在本機使用 CLI 時，我們建議以使用者身分進行驗證。要以使用者身分驗證，請執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成網頁驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存長期有效的 Refresh Token 和短期有效的 Access Token。目錄中的每個檔案代表你驗證的網域，預設應為 `tuist.dev.json`。儲存在該目錄的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果 Access Token 已過期，CLI 將使用 Refresh Token 取得新的 Access Token。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC Token {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的密鑰。在支援的 CI 環境中執行時，CLI 會自動偵測 OIDC Token 提供者，並將 CI 提供的 Token 交換為 Tuist Access Token。

### 支援的提供者 {#supported-ci-providers}

Tuist 可識別這些 CI 提供者，並透過你的儲存庫連線將它們的 Token 對應至專案：

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) Orbs 透過你連線至 Tuist 帳號的 Amp Workspace 進行驗證，而 [Claude Code 工作階段](#claude-code-sessions) 則透過你連線至 Tuist Sandboxes 執行的 Claude Code 環境進行驗證。

任何其他發行 OpenID Connect Token 的身分提供者，都可以透過 [工作負載身分信任政策](#workload-identity-trust-policies) 進行驗證，你只需為帳號中的所有現有及未來專案設定一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

針對 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連線至 Tuist**：依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連線至 Tuist 專案。

2. **授予身分 Token**：在 GitHub Actions 上，賦予 Job `permissions: id-token: write`；在 CircleCI 和 Bitrise 上，為專案啟用 OIDC。從 Tuist 4.218.0 開始，當 CLI 未登入且未設定 `TUIST_TOKEN` 時，它會偵測 CI 環境並在第一個請求中交換身分 Token，因此不需要登入步驟。較早的版本需要先執行 `tuist auth login`，你仍可執行它以明確登入，並在交換被拒絕時及早失敗。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得特定提供者的設定範例。

### Amp Orbs {#amp-orbs}

[Amp](https://ampcode.com) Orbs 可以鑄造識別其 Amp Workspace 的 OIDC Token。只需將 Workspace 連線至你的 Tuist 帳號一次，該 Workspace 中任何 Orb 的 Tuist CLI 和 `tuist_ex` Mix 任務就會自行登入，無需儲存的 Token 或登入步驟：

1. 尋找 ID：在 Orb 中執行的 Workspace Thread 裡，執行 `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`。
2. 在你的 Tuist 帳號中，開啟 **Settings → Integrations**，在 Amp 卡片上選擇 **Connect workspace**，並貼上 Workspace ID。若只允許單一 Amp 專案的 Orbs，也請貼上其 Project ID。你需要是帳號管理員或擁有者。
3. 在 Workspace 的 Orbs 中使用 Tuist。當未登入時，CLI 或 Mix 任務會偵測 Orb，使用 `amp orb id-token --audience https://tuist.dev` 鑄造 Token，並將其交換為 Tuist 工作階段。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

如同 [Amp 的 OIDC 指南](https://ampcode.com/manual/orbs/oidc) 中的信任設定，Tuist 會驗證每個 Token 上的 Amp 簽章，僅在其 Audience 為 `https://tuist.dev`、`token_use` 為 `exchanged`、`workspace_id` 符合已連線的 Workspace，且對於限制於專案的連線，其 `project_id` 符合該專案時才接受。其 `sub` 必須指名與這些宣告相同的 Workspace，若是專案連線則指名相同的專案：`workspace:<workspace-id>:project:<project-id>:…`，這是 `amp orb id-token` 預設鑄造的格式。

連線允許的每個 Orb 都能取得帳號擁有的所有現有及未來專案的 CI 存取權限，包括快取上傳。它還獲得 `account:sandboxes:write` 範圍，因此可以像帳號成員一樣建立 <.localized_link href="/guides/features/sandboxes">Sandboxes</.localized_link> 並在其中執行指令，例如從 Linux Orb 在 macOS Sandbox 上建置。僅連線你信任其成員擁有該存取權限的 Workspace。仔細檢查 ID：Tuist 無法確認你屬於所連線的 Workspace。如果一個 Workspace 連線至多個 Tuist 帳號，Orbs 必須將 `TUIST_OIDC_ACCOUNT` 設定為要登入的帳號；在 Amp 專案的環境中設定它也能將登入鎖定在你的帳號。Workspace 外部的 Thread 沒有 Workspace 身分，無法使用連線。從 Amp 卡片斷開 Workspace 連線以停止新登入；已發出的工作階段仍有效，直到一小時後過期。工作階段不需要 Refresh Token：當即將過期時，Orb 中的 CLI 會鑄造新的 Amp Token 並再次交換，因此只要 Workspace 保持連線，長時間執行的 Orb 就能保持登入狀態。

你在連線 Workspace 之前為 Amp 發行者建立的信任政策，在設定 `TUIST_OIDC_ACCOUNT` 時仍然有效。

### Claude Code 工作階段 {#claude-code-sessions}

自託管環境中的每個 Claude Code Cloud 工作階段都攜帶由 Anthropic 簽署的身分 Token (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`)。在你 <.localized_link href="/guides/features/sandboxes/claude#claude-code">連線至 Tuist Sandboxes 執行</.localized_link> 的環境中，Tuist 會將其作為 `TUIST_OIDC_TOKEN` 傳遞給工作階段，因此 Tuist CLI 和 `tuist_ex` Mix 任務會自行登入。

Tuist 會驗證 Anthropic 的簽章，僅在 Token 為工作階段 Token（`ccr:role` 為 `session_worker`）且其 Audience 中指定的環境已連線至 Tuist 帳號並啟用時才接受。已連線環境的每個工作階段都能取得帳號擁有的所有現有及未來專案的 CI 存取權限，包括快取上傳，因此你的 Claude 組織允許使用該環境的任何人都能發布至你的快取。工作階段的 Tuist 工作階段會在一小時後或隨其身分辨識 Token 過期，以先到者為準；該 Token 是工作階段啟動時使用的 Token，預設有效期為四小時，因此較長的工作階段會失去 Tuist 存取權限，直到下一則訊息在新的 Runner 上恢復為止。斷開連線或停用環境以停止新登入。

### 工作負載身分信任政策 {#workload-identity-trust-policies}

信任政策允許來自其他身分提供者的工作負載（例如部署平台、Kubernetes 叢集或自行管理的 CI 系統）存取專案，而無需長效的 Tuist 金鑰。提供者必須：

- 可透過公開位址的 HTTPS 連線。Tuist 不會追蹤重新導向，也不會連線至私有或內部網路位址，包括來自自託管 Tuist 伺服器的連線。
- 簽發使用非對稱金鑰簽署的 JWT，例如 `RS256` 或 `ES256`。未簽署的 Token 和使用共享金鑰簽署的 Token（`HS256` 及類似演算法）會被拒絕。
- 在固定的 HTTPS URL 上以 JSON Web Key Set (JWKS) 形式發布其簽章金鑰。回應大小不得超過 64 KiB，且最多包含 20 個金鑰。
- 每個 Token 都必須包含到期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 發行者保留供上述基於儲存庫的流程使用，不能用於信任政策。

> [!NOTE]
> 對於自託管部署，請在設定工作負載身分或將工作移至它們之前，套用資料庫遷移並升級每個提供服務的 Tuist 伺服器複本。然後將 CLI 或 Elixir 整合升級至支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise 工作繼續使用基於儲存庫的授權，不需要帳號代號。在切換生產工作之前，請驗證與預期工作負載的短期 Token 交換和快取操作。若要停止新的交換，請移除政策；允許已發出的 Tuist 存取 Token 最多一小時後過期。刪除政策不會立即撤銷這些 Token。

#### 建立政策 {#create-a-trust-policy}

在 Tuist 儀表板中，開啟你帳號的 **設定** > **驗證**，並找到 **工作負載身分** 區段。你必須是帳號管理員（或是個人帳號的擁有者）。每個帳號最多可有 20 個政策。設定一次身分即可獲得帳號範圍的 CI 存取權限；無需選擇專案。

使用 **工作負載身分** 旁邊的開關來開啟政策表單。當帳號有已儲存的身分時，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身分的帳號，開關預設為關閉。該區段出現在組織的 **SCIM 佈建** 下方。隱藏表單會保留你的草稿，且不會停用工作負載驗證：已儲存身分的卡片和設定文件連結仍然可見。每張卡片顯示身分的名稱、發行者與 JWKS URL、Audience、精確的 JSON 宣告、帳號範圍和建立時間。使用卡片上的動作移除身分。

選擇 **自訂提供者** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織 Slug 以及數字的組織和應用程式 ID 產生它們。Fly 範本會在 **進階設定** 下保持產生的發行者、JWKS URL 和宣告可編輯。變更範本或輔助值會保留你手動編輯過的欄位。如果你的發行者、JWKS URL 或宣告覆蓋了範本，Tuist 會展開 **進階設定** 並顯示警告，以便你檢視即將儲存的政策。切換回 **自訂提供者** 以在不使用 Fly 輔助的情況下繼續。範本僅填寫設定，不會改變 Tuist 驗證 Token 的方式。

| 欄位 | 說明 |
| --- | --- |
| 名稱 | 用於識別政策的標籤，在帳號內必須唯一。 |
| 發行者 URL | Token 的 `iss` 宣告。必須完全相符，包括任何尾隨斜線。 |
| JWKS URL | 提供者簽章金鑰的 HTTPS URL。Tuist 直接使用此 URL，不會讀取提供者的 OpenID Connect 探索文件，因此請從提供者的文件或從 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| Audience | Token 必須針對其簽發的 Audience，預設為 `tuist`。Token 的 `aud` 必須等於它，或者當 `aud` 為列表時包含它。使用只有 Tuist 接受的值，這樣為其他服務鑄造的 Token 就無法在此重放。 |
| 宣告 | 一個包含 1 到 10 個 Token 必須包含之宣告的 JSON 物件，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、帶符號的 64 位元整數或布林值，且必須完全相符，包括其類型：`"123"` 與 `123` 不相符。不允許巢狀物件、列表以及時間或 Token 宣告，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個政策都授予對 **帳號擁有的所有現有及未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在建立第一個專案之前設定身分。這不會授予帳號管理權限或對另一個帳號的存取權限。

每個能夠取得具有相符宣告之 Token 的工作負載都可以存取所有這些專案，因此請選擇提供者保證且無人可以重複使用的宣告。優先使用穩定的數字 ID，而不是可以在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共用的身分提供者上，將政策綁定到你的組織或租戶 **以及** 預期的應用程式、專案或服務帳戶。像 `main` 這樣的分支名稱、像 `production` 這樣的環境，或單獨的通用角色都不是身分邊界：另一個租戶可能會取得具有相同值的 Token。例如，GitLab.com 政策必須包含目標專案的穩定 `project_id`，而不僅僅是 `ref`。相符的 Token 會授予帳號範圍內的 CI 存取權限，包括快取寫入，因此信任不相關工作負載的政策可能會導致快取污染。

Tuist 僅對其自身 JWKS URL 持有簽署 Token 金鑰的政策授予存取權限，並在檢查發行者、Audience、過期時間、生效前時間（允許最多 60 秒的時鐘偏差）以及每個宣告之後進行。簽發的一小時 CI Token 是帳號範圍的，而非專案 ID 的快照：它包含在簽發後建立或轉移至該帳號的專案。專案授權仍然需要當前的帳號擁有權，因此將專案轉移出去會移除其在該帳號 Token 下的存取權限。

#### 驗證工作負載 {#authenticate-a-workload}

1. 向你的提供者請求具有政策 Audience 的身分 Token。
2. 將 `TUIST_OIDC_TOKEN` 設定為該 Token，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案之 Tuist 帳號的控制代碼。每次信任政策交換都需要帳號。它僅選擇查詢位置，本身不授予任何權限。
3. 執行 Tuist。當沒有 `TUIST_TOKEN` 或有效的儲存憑證可用時，CLI 和 Elixir 整合會自動交換 Token。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

產生的 Tuist 存取 Token 僅具有 `ci` 範圍群組，並涵蓋所選帳號擁有的所有現有及未來專案。如果帳號中有超過 20 個政策與同一個 Token 相符，或者它們使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會重新整理這些工作階段。存取 Token 在一小時後過期，且沒有重新整理 Token。提供者身分 Token 通常僅有效幾分鐘，因此保留舊的 `TUIST_OIDC_TOKEN` 並不是一種續約策略：對於運行時間超過一小時的工作，請在 Tuist 工作階段過期之前請求新的身分 Token 並再次登入。移除政策會停止新的交換，但已簽發的存取 Token 在過期之前仍然有效。

Tuist 會在專用且大小受限的快取中快取提供者的簽章金鑰，成功擷取後最多保留 15 分鐘。項目可能會較早被逐出並再次擷取。失敗的擷取不會被快取。如果你的提供者輪換金鑰，它應該在使用新金鑰簽署 Token 之前至少 15 分鐘將其發布到 JWKS 中，因為使用不在快取集合中的金鑰簽署的 Token 會被拒絕，直到快取過期。沒有金鑰 ID (`kid`) 的 Token 僅在 JWKS 包含單一合格簽章金鑰時才被接受。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是一個通用的 Token 輸入，不是繞過伺服器信任的方法。它優先於 CI 提供者偵測，且伺服器仍然只接受內建提供者和具有相符信任政策的身分。不要將身分 Token 放入 `TUIST_TOKEN`，因為它預期的是 Tuist 憑證。

如果交換失敗，請檢查政策中的發行者、Audience 和每個宣告是否與 Token 完全相符，JWKS URL 是否提供簽署 Token 的金鑰，政策是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了擁有該專案的帳號。為了避免暴露哪些身分受信任，Tuist 針對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身分](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本機 `/.fly/api` Unix socket 請求短期、已簽名的身分 Token，無需 Fly API Token 或長效 Tuist 密鑰。Fly Token 識別組織和應用程式，而非原始碼儲存庫，因此請使用信任政策而不是連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部簽發的身分 Token 中取得發行者 (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。發行者為 `https://oidc.fly.io/<organization-slug>`。請使用數字 ID，而非組織或應用程式名稱。
2. 使用 **Fly.io Machines** 範本 [建立信任政策](#create-a-trust-policy)，並輸入組織 slug 和兩個數字 ID。它會填寫下方的值並將 ID 保持為字串。你也可以使用 **Custom provider** 手動輸入它們；在宣告中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | 發行者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audience | `tuist` |
   | 宣告 | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳號控制代碼（而非 Fly 組織 slug），請求具有 Audience `tuist` 的 Token，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

對於初始設定，你可以在匯出 Token 之後且取消設定之前，僅在本機檢查身分欄位。這會解碼宣告以進行設定；Tuist 會在驗證期間 separately 驗證簽章：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要列印或提交 Token 本身。授權 Fly 應用程式中的每個 Machine 都可以驗證 Tuist 帳號中的所有現有及未來專案。為每個額外的應用程式建立單獨的政策。Fly 身分 Token 在大約十分鐘後過期，因此在長時間運行的 Machine 上，請在 Tuist 一小時工作階段過期之前請求新的 Token 並再次執行 `tuist auth login`。

### OIDC Token 範圍 {#oidc-token-scopes}

OIDC Token 被授予 `ci` 範圍群組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供了對連接到儲存庫的所有專案的存取權限。對於連接的 Amp 工作區、連接的 Claude Code 環境和工作負載身分信任政策，這提供了對所選帳號擁有的所有現有及未來專案的存取權限，但不授予專案建立、專案管理、Runner 管理或帳號成員管理權限。有關 `ci` 範圍包含內容的詳細資訊，請參閱 [範圍群組](#scope-groups)。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長效 Token 更安全，因為：
> - 無需輪換或管理密鑰
> - Token 壽命短
> - 驗證與你的儲存庫身分或明確授權的工作負載身分綁定


## Gradle 外掛驗證 {#gradle-plugin-authentication}

Gradle 外掛使用 Tuist CLI 的驗證狀態，並未定義獨立的登入流程。只需透過 CLI 驗證一次，外掛就會重複使用這些憑證。

對於專案和伺服器設定（包括 `project` 和 `url`），請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

若要在本機使用，請執行：

```bash
tuist auth login
```

若要在 CI 中使用，請選擇以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 驗證</.localized_link>（建議在可用時使用）
- 透過 `TUIST_TOKEN` 進行 <.localized_link href="/guides/server/authentication#continuous-integration">帳號 Token 驗證</.localized_link>

對於自行託管的 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並執行標準登入流程。該 URL 會從外掛使用的同一個設定檔中解析。

設定好驗證後，即可正常執行你的 Gradle 快取指令和任務。

## 帳號 Token {#account-tokens}

對於不支援 OIDC 的 CI 環境，或當你需要對權限進行細粒度控制時，可以使用帳號 Token。帳號 Token 允許你精確指定 Token 可以存取的範圍和專案。

### 建立帳號 Token {#creating-an-account-token}

建立帳號 Token 最簡單的方法是透過儀表板：

1. 在 Tuist 儀表板中開啟組織。
2. 前往 **設定** > **Tokens**。
3. 選擇 **產生 Token**。
4. 選擇名稱、可選的過期時間、專案存取權限以及 Token 所需的範圍。
5. 在關閉對話框之前複製產生的 Token 值。Token 值僅顯示一次。

你也可以從 CLI 建立帳號 Token，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想讓 Token 存取之專案的帳號控制代碼。這可以是組織帳號，不一定是你的個人帳號。

該指令接受以下選項：

| 選項 | 說明 |
| --- | --- |
| `--scopes` | 必填。以空格分隔的範圍清單，用於授予 Token。 |
| `--name` | 必填。Token 的唯一識別碼（1-32 個字元，僅限字母數字、連字號和底線）。 |
| `--expires` | 可選。Token 的過期時間。使用如 `30d`（天）、`6m`（月）或 `1y`（年）等格式。若未指定，Token 永不過期。 |
| `--projects` | 將 Token 限制為特定專案控制代碼。若未指定，Token 可存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 說明 |
| --- | --- |
| `account:cache:read` | 下載帳號範圍的快取二進位檔 |
| `account:cache:write` | 上傳帳號範圍的快取二進位檔 |
| `account:members:read` | 讀取帳號成員 |
| `account:members:write` | 管理帳號成員 |
| `account:registry:read` | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發布至 Swift 套件註冊表 |
| `account:runners:read` | 讀取 Runner 工作、工作流程、設定檔和卷 |
| `account:runners:write` | 管理 Runner 設定檔並刪除 Runner 卷 |
| `account:sandboxes:write` | 建立沙盒並在其中執行指令，如同帳號成員 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要擁有所有專案存取權限的 Token |
| `project:cache:read` | 下載快取二進位檔 |
| `project:cache:write` | 上傳快取二進位檔 |
| `project:bundles:read` | 檢視套件 |
| `project:bundles:write` | 上傳套件 |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取建置分析 |
| `project:builds:write` | 上傳建置分析 |
| `project:runs:read` | 讀取指令執行 |
| `project:runs:write` | 建立和更新指令執行 |

### 範圍群組 {#scope-groups}

範圍群組提供了一種便捷的方式，可透過單一識別碼授予多個相關範圍。當你使用範圍群組時，它會自動展開以包含其所含的所有個別範圍。

| 範圍群組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立具有 `ci` 範圍群組的帳號 Token，以驗證你的 CI 工作流程。在儀表板中產生 Token 時，選擇 **CI** 預設值。

你也可以從 CLI 建立相同的 Token：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 作業（快取、預覽、套件、測試、建置和執行）所需所有範圍的 Token。將產生的 Token 作為機密儲存在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### 管理帳號 Token {#managing-account-tokens}

在帳號儀表板中開啟 **設定** > **Tokens**，以檢視帳號 Token、檢查 Token 的範圍和專案存取權限，並在輪換期間撤銷 Token。

列出帳號的所有 Token：

```bash
tuist account tokens list account-handle
```

依名稱撤銷 Token：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用帳號 Token {#using-account-tokens}

帳號 Token 應定義為環境變數 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用帳號 Token**
>
> 當你需要以下情況時，請使用帳號 Token：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對 Token 可執行的操作進行細粒度控制
> - 一個可以存取帳號內多個專案的 Token
> - 會自動過期的限時 Token
