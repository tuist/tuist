---
{
  "title": "身分驗證",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何從 CLI 向 Tuist 伺服器進行身分驗證。"
}
---
# 驗證 {#authentication}

若要與伺服器互動，CLI 需要使用 [Bearer 驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者身分、以帳戶身分，或使用 OIDC 權杖進行驗證。

## 以使用者身分 {#as-a-user}

在本機使用 CLI 時，我們建議以使用者身分進行驗證。若要以使用者身分驗證，請執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成網頁式驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存長期有效的更新權杖和短期有效的存取權杖。目錄中的每個檔案代表你驗證的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果存取權杖已過期，CLI 將使用更新權杖取得新的存取權杖。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC 權杖 {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的密鑰。在受支援的 CI 環境中執行時，CLI 會自動偵測 OIDC 權杖提供者，並將 CI 提供的權杖交換為 Tuist 存取權杖。

### 受支援的提供者 {#supported-ci-providers}

Tuist 可識別以下 CI 提供者，並透過你的儲存庫連線將其權杖對應至專案：

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) orbs 透過你連線至 Tuist 帳戶的 Amp 工作區進行驗證，而 [Claude Code 工作階段](#claude-code-sessions) 則透過你連線至 Tuist Sandboxes 執行的 Claude Code 環境進行驗證。

任何其他發行 OpenID Connect 權杖的身分提供者，都可以透過 [工作負載身分信任政策](#workload-identity-trust-policies) 進行驗證；你只需為帳戶中的所有現有和未來專案設定一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

適用於 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連線至 Tuist**：依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連線至你的 Tuist 專案。

2. **授予身分權杖**：在 GitHub Actions 上，賦予作業 `permissions: id-token: write` 權限；在 CircleCI 和 Bitrise 上，為專案啟用 OIDC。從 Tuist 4.218.0 開始，當 CLI 未登入且未設定 `TUIST_TOKEN` 時，它會偵測 CI 環境並在第一個請求中交換身分權杖，因此不需要登入步驟。較早的版本需要先執行 `tuist auth login`，你仍然可以執行它以明確登入，並在交換被拒絕時及早失敗。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得特定提供者的設定範例。

### Amp orbs {#amp-orbs}

[Amp](https://ampcode.com) orbs 可以鑄造識別其 Amp 工作區的 OIDC 權杖。只需將工作區連線至你的 Tuist 帳戶一次，該工作區中任何 orb 的 Tuist CLI 和 `tuist_ex` Mix 任務都會自行登入，無需儲存的權杖或登入步驟：

1. 尋找 ID：在 orb 中執行的工作區執行緒中，執行 `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`。
2. 在你的 Tuist 帳戶中，開啟 **設定 → 整合**，在 Amp 卡片上選擇 **連線工作區**，並貼上工作區 ID。若只允許單一 Amp 專案的 orbs，請同時貼上其專案 ID。你需要是帳戶管理員或擁有者。
3. 在工作區的 orbs 中使用 Tuist。當未登入時，CLI 或 Mix 任務會偵測 orb，使用 `amp orb id-token --audience https://tuist.dev` 鑄造權杖，並將其交換為 Tuist 工作階段。`tuist auth login` 和 `mix tuist.login` 會明確執行相同的交換。

如同 [Amp 的 OIDC 指南](https://ampcode.com/manual/orbs/oidc) 中的信任設定，Tuist 會驗證每個權杖上的 Amp 簽章，僅在其受眾為 `https://tuist.dev`、其 `token_use` 為 `exchanged`、其 `workspace_id` 符合已連線的工作區，以及對於限制於專案的連線，其 `project_id` 符合該專案時才接受。其 `sub` 必須命名與這些宣告相同的工作區，對於專案連線則為相同的專案：`workspace:<workspace-id>:project:<project-id>:…`，這是 `amp orb id-token` 預設鑄造的格式。

連線所允許的每個 orb 都能獲得對帳戶擁有的所有現有和未來專案的 CI 存取權限，包括快取上傳。它還獲得 `account:sandboxes:write` 範圍，因此可以像帳戶成員一樣建立 <.localized_link href="/guides/features/sandboxes">sandboxes</.localized_link> 並在其中執行指令，例如從 Linux orb 在 macOS sandbox 上進行建置。僅連線你信任其成員擁有該存取權限的工作區。請仔細檢查 ID：Tuist 無法確認你屬於所連線的工作區。如果工作區連線到多個 Tuist 帳戶，orbs 必須將 `TUIST_OIDC_ACCOUNT` 設定為要登入的帳戶；在 Amp 專案的環境中設定它也能將登入固定在你的帳戶。工作區之外的執行緒沒有工作區身分，無法使用連線。從 Amp 卡片斷開工作區以停止新登入；已發出的工作階段在一個小時後過期前仍然有效。工作階段不需要更新權杖：當即將過期時，orb 中的 CLI 會鑄造新的 Amp 權杖並再次交換，因此只要工作區保持連線，長時間執行的 orbs 就能保持登入狀態。

你在連線工作區之前為 Amp 發行者建立的信任政策，在設定 `TUIST_OIDC_ACCOUNT` 時仍會繼續運作。

### Claude Code 工作階段 {#claude-code-sessions}

自託管環境中的每個 Claude Code 雲端工作階段都攜帶由 Anthropic 簽署的身分權杖 (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`)。在你 <.localized_link href="/guides/features/sandboxes/claude#claude-code">連線至 Tuist Sandboxes 執行</.localized_link> 的環境中，Tuist 會將其作為 `TUIST_OIDC_TOKEN` 傳遞給工作階段，因此 Tuist CLI 和 `tuist_ex` Mix 任務會自行登入。

Tuist 會驗證 Anthropic 的簽章，僅在權杖為工作階段權杖（`ccr:role` 為 `session_worker`）且其受眾中命名的環境已連線至 Tuist 帳戶並啟用時才接受。已連線環境的每個工作階段都能獲得對帳戶擁有的所有現有和未來專案的 CI 存取權限，包括快取上傳，並能像帳戶成員一樣建立和使用帳戶的 sandboxes。因此，任何獲你的 Claude 組織允許使用該環境的人都能發布到你的快取並啟動 sandboxes，例如用於建置的 Mac。工作階段的 Tuist 工作階段會在一個小時後或隨其身分辨識權杖過期（以較早者為準）；該權杖是工作階段開始時使用的權杖，預設有效期為四小時，因此較長的工作階段會失去 Tuist 存取權限，直到下一則訊息在新執行器上恢復為止。斷開連線或停用環境以停止新登入。

### 工作負載身分信任政策 {#workload-identity-trust-policies}

信任政策允許來自其他身分提供者（例如部署平台、Kubernetes 叢集或自行管理的 CI 系統）的工作負載，無需長期有效的 Tuist 密鑰即可存取專案。提供者必須：

- 可透過公開位址的 HTTPS 連線。Tuist 不會追蹤重新導向，也不會連線至私人或內部網路位址，包括來自自託管 Tuist 伺服器的連線。
- 簽發使用非對稱金鑰簽署的 JWT，例如 `RS256` 或 `ES256`。未簽署的權杖以及使用共用密鑰簽署的權杖（`HS256` 及類似演算法）會被拒絕。
- 在固定的 HTTPS URL 上將其簽章金鑰發布為 JSON Web Key Set (JWKS)。回應大小不得超過 64 KiB，且最多包含 20 個金鑰。
- 在每個權杖中包含到期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 發行者保留供上述基於儲存庫的流程使用，不能用於信任政策。

> [!NOTE]
> 對於自託管部署，請在設定工作負載身分或將作業移至它們之前，套用資料庫遷移並升級每個提供服務的 Tuist 伺服器複本。然後將 CLI 或 Elixir 整合升級至支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise 作業會繼續使用基於儲存庫的授權，不需要帳戶代號。在切換生產作業之前，請驗證與預期工作負載的短期權杖交換和快取操作。若要停止新的交換，請移除政策；允許已發出的 Tuist 存取權杖最多一小時後過期。刪除政策不會立即撤銷這些權杖。

#### 建立政策 {#create-a-trust-policy}

在 Tuist 儀表板中，開啟你帳戶的 **Settings** > **Authentication**，並找到 **Workload identities** 區段。你必須是帳戶管理員（或是個人帳戶的擁有者）。每個帳戶最多可有 20 個政策。設定一次身分即可獲得帳戶範圍的 CI 存取權限；無需選擇專案。

使用 **Workload identities** 旁邊的開關來開啟政策表單。當帳戶有已儲存的身分時，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身分的帳戶，開關預設為關閉。該區段出現在組織的 **SCIM provisioning** 下方。隱藏表單會保留你的草稿，且不會停用工作負載驗證：已儲存身分的卡片和設定文件連結仍會顯示。每張卡片顯示身分的名稱、發行者和 JWKS URL、受眾、精確的 JSON 宣告、帳戶範圍和建立時間。使用卡片上的動作移除身分。

選擇 **Custom provider** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織縮寫以及數字的組織和應用程式 ID 產生它們。Fly 範本會讓產生的發行者、JWKS URL 和宣告在 **Advanced configuration** 下保持可編輯。變更範本或輔助值會保留你手動編輯過的欄位。如果你的發行者、JWKS URL 或宣告覆蓋了範本，Tuist 會展開 **Advanced configuration** 並顯示警告，以便你檢視即將儲存的政策。切換回 **Custom provider** 以在不使用 Fly 輔助工具的情況下繼續。範本僅填寫設定，不會改變 Tuist 驗證權杖的方式。

| 欄位 | 說明 |
| --- | --- |
| 名稱 | 用於識別政策的標籤，在帳戶內必須唯一。 |
| 發行者 URL | 權杖的 `iss` 宣告。必須完全相符，包括任何尾隨斜線。 |
| JWKS URL | 提供者簽章金鑰的 HTTPS URL。Tuist 直接使用此 URL，不會讀取提供者的 OpenID Connect 探索文件，因此請從提供者的文件或從 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| 受眾 | 權杖必須針對其發行的受眾，預設為 `tuist`。權杖的 `aud` 必須等於它，或者當 `aud` 為清單時包含它。使用僅 Tuist 接受的值，這樣為其他服務鑄造的權杖就無法在此重放。 |
| 宣告 | 一個包含 1 到 10 個權杖必須包含之宣告的 JSON 物件，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、帶符號的 64 位元整數或布林值，且必須完全相符，包括其類型：`"123"` 與 `123` 不相符。不允許巢狀物件、清單以及時間或權杖宣告，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個政策授予對 **帳戶擁有的所有現有和未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在建立第一個專案之前設定身分。這不會授予帳戶管理權限或對另一個帳戶的存取權限。

每個能夠取得具有相符宣告之權杖的工作負載都能存取所有這些專案，因此請選擇提供者保證且無人能重複使用的宣告。優先使用穩定的數字 ID，而非可能在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共用的身分提供者上，將政策綁定至你的組織或租戶 **以及** 預期的應用程式、專案或服務帳戶。僅使用分支名稱（例如 `main`）、環境（例如 `production`）或通用角色並不足以構成身分邊界：其他租戶可能取得具有相同值的權杖。例如，GitLab.com 政策必須包含目標專案的穩定 `project_id`，而不僅僅是 `ref`。相符的權杖會授予帳戶範圍內的 CI 存取權限，包括快取寫入，因此信任無關工作負載的政策可能會導致快取污染。

Tuist 僅對其自有 JWKS URL 持有簽署該權杖之金鑰的政策授予存取權限，並在檢查發行者、受眾、過期時間、生效前時間（允許最多 60 秒的時鐘偏差）以及每個宣告後進行驗證。所發行的一小時 CI 權杖適用於整個帳戶，而非專案 ID 的快照：它包含在發行後建立或轉移至該帳戶的專案。專案授權仍需要當前的帳戶擁有權，因此將專案轉移出去會移除其在該帳戶權杖下的存取權限。

#### 驗證工作負載 {#authenticate-a-workload}

1. 向你的提供者請求具有政策受眾的身分權杖。
2. 將 `TUIST_OIDC_TOKEN` 設定為該權杖，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案之 Tuist 帳戶的控制代碼。每個信任政策交換都需要帳戶。它僅選擇查詢位置，本身不授予任何權限。
3. 執行 Tuist。當沒有 `TUIST_TOKEN` 或有效的已儲存憑證時，CLI 和 Elixir 整合會自動交換權杖。`tuist auth login` 和 `mix tuist.login` 也會明確執行相同的交換。

產生的 Tuist 存取權杖僅具有 `ci` 範圍群組，並涵蓋所選帳戶擁有的所有現有和未來專案。如果帳戶中有超過 20 個政策與同一權杖相符，或使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會重新整理這些工作階段。存取權杖在一小時後過期，且沒有重新整理權杖。提供者身分權杖通常僅有效幾分鐘，因此保留舊的 `TUIST_OIDC_TOKEN` 並非續訂策略：對於運行時間超過一小時的工作，請在 Tuist 工作階段過期前請求新的身分權杖並再次登入。移除政策會停止新的交換，但已發行的存取權杖在過期前仍然有效。

Tuist 會在專用的大小限制快取中，將提供者的簽章金鑰快取最多 15 分鐘（自成功擷取後）。項目可能會較早被驅逐並再次擷取。失敗的擷取不會被快取。如果你的提供者輪換金鑰，應在使用新金鑰簽署權杖前至少 15 分鐘將其發布到 JWKS 中，因為使用不在快取集合中的金鑰簽署的權杖會被拒絕，直到快取過期。沒有金鑰 ID (`kid`) 的權杖僅在 JWKS 包含單一符合條件的簽章金鑰時才會被接受。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用的權杖輸入，並非繞過伺服器信任的方式。它優先於 CI 提供者偵測，且伺服器仍僅接受內建提供者和具有相符信任政策的身分。請勿將身分權杖放入 `TUIST_TOKEN`，因為它預期的是 Tuist 憑證。

如果交換失敗，請檢查政策中的發行者、受眾和每個宣告是否與權杖完全相符，JWKS URL 是否提供簽署該權杖的金鑰，政策是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否指名擁有該專案的帳戶。為了避免揭露哪些身分受到信任，Tuist 在所有這些情況下都會傳回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身分](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本機 `/.fly/api` Unix 通訊端請求短暫的已簽名身分權杖，無需 Fly API 權杖或長效 Tuist 秘密。Fly 權杖識別組織和應用程式，而非原始碼儲存庫，因此請使用信任政策，而非連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部發行的身分權杖中取得發行者 (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。發行者為 `https://oidc.fly.io/<organization-slug>`。請使用數字 ID，而非組織或應用程式名稱。
2. 使用 **Fly.io Machines** 範本 [建立信任政策](#create-a-trust-policy)，並輸入組織 slug 和兩個數字 ID。它會填入下方的值並將 ID 保持為字串。你也可以使用 **自訂提供者** 手動輸入它們；請在宣告中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | 發行者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 受眾 | `tuist` |
   | 宣告 | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶控制代碼（而非 Fly 組織 slug），請求受眾為 `tuist` 的權杖，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

對於初始設定，你可以在匯出權杖後且取消設定之前，僅在本機檢查身分欄位。這會解碼宣告以供設定使用；Tuist 會在驗證期間 separately 驗證簽章：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

請勿列印或提交權杖本身。已授權 Fly 應用程式中的每個 Machine 都可以驗證 Tuist 帳戶中的所有現有和未來專案。為每個額外的應用程式建立個別的政策。Fly 身分權杖在大約十分鐘後過期，因此在長時間運行的 Machine 上，請在單小時 Tuist 工作階段過期前請求新的權杖並再次執行 `tuist auth login`。

### OIDC 權杖範圍 {#oidc-token-scopes}

OIDC 權杖被授予 `ci` 範圍群組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供對連接到儲存庫的所有專案的存取權限。對於連接的 Amp 工作區、連接的 Claude Code 環境和工作負載身分信任政策，這提供對所選帳戶擁有的所有現有和未來專案的存取權限，但不授予專案建立、專案管理、執行者管理或帳戶成員管理權限。有關 `ci` 範圍包含內容的詳細資訊，請參閱 [範圍群組](#scope-groups)。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長效權杖更安全，因為：
> - 無需輪換或管理秘密
> - 權杖壽命短暫
> - 驗證與你的儲存庫身分或明確授權的工作負載身分綁定


## Gradle 外掛程式驗證 {#gradle-plugin-authentication}

Gradle 外掛程式使用 Tuist CLI 的驗證狀態，並未定義獨立的登入流程。只需透過 CLI 驗證一次，外掛程式就會重複使用這些憑證。

對於專案和伺服器設定（包括 `project` 和 `url`），請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

本機使用時，請執行：

```bash
tuist auth login
```

持續整合 (CI) 環境中，請使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 驗證</.localized_link>（建議在可用時使用）
- 透過 `TUIST_TOKEN` 進行 <.localized_link href="/guides/server/authentication#continuous-integration">帳戶權杖驗證</.localized_link>

對於自託管的 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並執行標準登入流程。URL 會從外掛程式使用的同一個設定檔案中解析。

設定好驗證後，即可正常執行 Gradle 快取指令和任務。

## 帳戶權杖 {#account-tokens}

對於不支援 OIDC 的 CI 環境，或當你需要對權限進行細粒度控制時，可以使用帳戶權杖。帳戶權杖允許你精確指定權杖可以存取的範圍和專案。

### 建立帳戶權杖 {#creating-an-account-token}

最簡單的建立帳戶權杖方式是透過儀表板：

1. 在 Tuist 儀表板中開啟組織。
2. 前往 **設定** > **權杖**。
3. 選擇 **產生權杖**。
4. 選擇名稱、選用到期時間、專案存取權限，以及權杖所需的範圍。
5. 在關閉對話框之前複製產生的權杖值。權杖值僅顯示一次。

你也可以從 CLI 建立帳戶權杖，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想讓權杖存取之專案的帳戶控制代碼。這可以是組織帳戶，不一定是你的個人帳戶。

該指令接受以下選項：

| 選項 | 說明 |
| --- | --- |
| `--scopes` | 必填。以空格分隔的範圍清單，用於授予權杖。 |
| `--name` | 必填。權杖的唯一識別碼（1-32 個字元，僅限英數字元、連字號和下底線）。 |
| `--expires` | 選填。權杖應過期的時間。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。若未指定，權杖永不過期。 |
| `--projects` | 將權杖限制為特定專案控制代碼。若未指定，權杖可存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 說明 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進位檔 |
| `account:cache:write` | 上傳帳戶範圍的快取二進位檔 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:pulse:write` | 從 Sentry SDK 將錯誤發送至帳戶的 Pulse，使用權杖作為 DSN 金鑰 |
| `account:registry:read` | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發布至 Swift 套件註冊表 |
| `account:runners:read` | 讀取執行者工作、工作流程、設定檔和磁碟區 |
| `account:runners:write` | 管理執行者設定檔並刪除執行者磁碟區 |
| `account:sandboxes:write` | 建立沙箱並在其中執行指令，如同帳戶成員一般 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要具有存取所有專案權限的權杖 |
| `project:cache:read` | 下載快取二進位檔 |
| `project:cache:write` | 上傳快取二進位檔 |
| `project:bundles:read` | 檢視套件 |
| `project:bundles:write` | 上傳套件 |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取建置分析 |
| `project:builds:write` | 上傳建置分析 |
| `project:runs:read` | 讀取指令執行紀錄 |
| `project:runs:write` | 建立和更新指令執行紀錄 |

### 範圍群組 {#scope-groups}

範圍群組提供了一種便捷的方式，可透過單一識別碼授予多個相關範圍。當你使用範圍群組時，它會自動展開以包含其中的所有個別範圍。

| 範圍群組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立具有 `ci` 範圍群組的帳戶權杖，以驗證你的 CI 工作流程。在儀表板中產生權杖時，選擇 **CI** 預設值。

你也可以從 CLI 建立相同的權杖：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 作業所需所有範圍（快取、預覽、套件、測試、建置和執行）的權杖。將產生的權杖作為機密儲存在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### 管理帳戶權杖 {#managing-account-tokens}

在帳戶儀表板中開啟 **設定** > **權杖**，以檢視帳戶權杖、檢查權杖的範圍和專案存取權限，並在輪換期間撤銷權杖。

列出帳戶的所有權杖：

```bash
tuist account tokens list account-handle
```

依名稱撤銷權杖：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用帳戶權杖 {#using-account-tokens}

帳戶權杖應定義為環境變數 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用帳戶權杖**
>
> 在以下情況下使用帳戶權杖：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對權杖可執行的操作進行細粒度控制
> - 可存取帳戶內多個專案的權杖
> - 會自動過期的時間限制權杖
