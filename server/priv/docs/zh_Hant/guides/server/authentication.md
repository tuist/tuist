---
{
  "title": "驗證",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何從 CLI 向 Tuist 伺服器進行驗證。"
}
---
# 驗證 {#authentication}

若要與伺服器互動，CLI 需要使用 [Bearer 驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者身分、帳戶身分或使用 OIDC 權杖進行驗證。

## 以使用者身分 {#as-a-user}

在本機使用 CLI 時，我們建議以使用者身分進行驗證。若要以使用者身分驗證，請執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成網頁驗證流程。驗證成功後，CLI 會將長期有效的重新整理權杖和短期有效的存取權杖儲存在 `~/.config/tuist/credentials` 下。目錄中的每個檔案代表你驗證的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查詢憑證。如果存取權杖已過期，CLI 會使用重新整理權杖來取得新的存取權杖。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC 權杖 {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的密鑰。在受支援的 CI 環境中執行時，CLI 會自動偵測 OIDC 權杖提供者，並將 CI 提供的權杖交換為 Tuist 存取權杖。

### 受支援的提供者 {#supported-ci-providers}

Tuist 會識別這些 CI 提供者，並透過你的儲存庫連線將其權杖對應至專案：

- GitHub Actions
- CircleCI
- Bitrise

任何其他發行 OpenID Connect 權杖的身分提供者，都可以透過 [工作負載身分信任政策](#workload-identity-trust-policies) 進行驗證，你可以為帳戶中的所有現有和未來專案設定一次，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

針對 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連線到 Tuist**：依照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連線到你的 Tuist 專案。

2. **執行 `tuist auth login`**：在你的 CI 工作流程中，在任何需要驗證的指令之前執行 `tuist auth login`。CLI 會自動偵測 CI 環境並使用 OIDC 進行驗證。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得特定提供者的設定範例。

### 工作負載身分信任政策 {#workload-identity-trust-policies}

信任政策允許來自其他身分提供者（例如部署平台、Kubernetes 叢集或自行管理的 CI 系統）的工作負載，在無需長期有效 Tuist 密鑰的情況下存取專案。提供者必須：

- 可透過 HTTPS 在公開位址存取。Tuist 不會追蹤重新導向，也不會連線到私有或內部網路位址，包括來自自行託管的 Tuist 伺服器。
- 發行使用非對稱金鑰簽署的 JWT，例如 `RS256` 或 `ES256`。未簽署的權杖和使用共用密鑰簽署的權杖（`HS256` 及類似者）會被拒絕。
- 在固定的 HTTPS URL 上以 JSON Web Key Set (JWKS) 形式發布其簽署金鑰。回應大小不得超過 64 KiB，且最多包含 20 個金鑰。
- 在每個權杖中包含到期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 發行者僅保留給上述基於儲存庫的流程，不能用於信任政策。

> [!NOTE]
> 對於自行託管的部署，請先套用資料庫遷移並升級每個提供服務的 Tuist 伺服器複本，然後再設定工作負載身分或將作業移至它們。接著將 CLI 或 Elixir 整合升級至支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise 作業會繼續使用基於儲存庫的授權，不需要帳戶代號。在切換生產作業之前，請驗證與預期工作負載的短期權杖交換和快取操作。若要停止新的交換，請移除政策；讓已發行的 Tuist 存取權杖有最多一小時的時間過期。刪除政策不會立即撤銷這些權杖。

#### 建立政策 {#create-a-trust-policy}

在 Tuist 儀表板中，開啟你帳戶的 **設定** > **驗證**，並找到 **工作負載身分** 區段。你必須是帳戶管理員（或个人帳戶的擁有者）。每個帳戶最多可以有 20 個政策。為帳戶範圍的 CI 存取設定一次身分；不需要選擇專案。

使用 **工作負載身分** 旁的開關來開啟政策表單。當帳戶有已儲存的身分时，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身分的帳戶，開關預設為關閉。該區段出現在組織的 **SCIM 佈建** 下方。隱藏表單會保留你的草稿，且不會停用工作負載驗證：已儲存身分的卡片和設定文件連結仍可見。每張卡片顯示身分的名稱、發行者與 JWKS URL、受眾、精確的 JSON 聲明、帳戶範圍的範圍和建立時間。使用卡片上的動作來移除身分。

選擇 **自訂提供者** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織代號以及數字的組織和應用程式 ID 產生它們。Fly 範本會在 **進階設定** 下保持產生的發行者、JWKS URL 和聲明可編輯。變更範本或輔助值會保留你手動編輯的欄位。如果你的發行者、JWKS URL 或聲明覆蓋了範本，Tuist 會展開 **進階設定** 並顯示警告，以便你檢視將要儲存的政策。切換回 **自訂提供者** 以在不使用 Fly 輔助工具的情況下繼續。範本僅填寫設定，不會改變 Tuist 驗證權杖的方式。

| 欄位 | 說明 |
| --- | --- |
| 名稱 | 用於識別政策的標籤，在帳戶內必須唯一。 |
| 發行者 URL | 權杖的 `iss` 聲明。它必須完全相符，包括任何尾隨斜線。 |
| JWKS URL | 提供者的簽署金鑰之 HTTPS URL。Tuist 會直接使用此 URL，而不會讀取提供者的 OpenID Connect 探索文件，因此請從提供者的文件或 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| 受眾 | 權杖必須針對的受眾，預設為 `tuist`。權杖的 `aud` 必須等於它，或者當 `aud` 為清單時包含它。使用僅 Tuist 接受的值，以免為其他服務發行的權杖在此被重放。 |
| 聲明 | 一個包含 1 到 10 個聲明的 JSON 物件，權杖必須包含這些聲明，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、帶符號的 64 位整數或布林值，且必須完全相符，包括其類型：`"123"` 與 `123` 不相符。不允許巢狀物件、清單以及時間或權杖聲明，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個政策授予對 **帳戶擁有的所有目前及未來專案** 的 CI 存取權，無需選擇個別專案。你可以在建立第一個專案之前設定身分。這不會授予帳戶管理權限或對其他帳戶的存取權。

每個能夠取得具有相符聲明之權杖的工作負載都可以存取所有这些專案，因此請選擇提供者保證且無人可以重複使用的聲明。優先使用穩定的數字 ID，而非可能在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共用的身分提供者上，將政策綁定到你的組織或租戶 **以及** 預期的應用程式、專案或服務帳戶。分支名稱（例如 `main`）、環境（例如 `production`）或通用角色本身並非身分邊界：另一個租戶可能會取得具有相同值的權杖。例如，GitLab.com 政策必須包含預期專案的穩定 `project_id`，而不僅是 `ref`。相符的權杖會授予帳戶範圍的 CI 存取權，包括快取寫入，因此信任不相關工作負載的政策可能會導致快取污染。

Tuist 僅在檢查發行者、受眾、過期時間、生效前時間（允許最多 60 秒的時鐘偏差）以及每個聲明後，才對其自身 JWKS URL 持有簽署權杖金鑰的政策授予存取權。發行的一小時 CI 權杖適用於整個帳戶，而非專案 ID 的快照：它包含在發行後建立或轉移到帳戶中的專案。專案授權仍需要目前的帳戶擁有權，因此將專案轉移出去會移除其在該帳戶權杖下的存取權。

#### 驗證工作負載 {#authenticate-a-workload}

1. 向你的提供者請求具有政策受眾的身分權杖。
2. 將 `TUIST_OIDC_TOKEN` 設定為該權杖，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶代號。每個信任政策交換都需要帳戶。它僅選擇查詢位置，本身不授予任何權限。
3. 執行 `tuist auth login`。對於 Elixir 專案，你可以改用 `mix tuist.login`，或者在沒有 `TUIST_TOKEN` 或有效儲存的憑證時，讓 Elixir 整合自動交換權杖。

產生的 Tuist 存取權杖僅具有 `ci` 範圍群組，並涵蓋所選帳戶擁有的所有目前及未來專案。如果帳戶中超過 20 個政策與同一權杖相符，或使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會刷新這些工作階段。存取權杖在一小時後過期，且沒有刷新權杖。提供者身分權杖通常僅有效幾分鐘，因此保留舊的 `TUIST_OIDC_TOKEN` 並非續訂策略：對於運行時間超過一小時的工作，請在 Tuist 工作階段過期前請求新的身分權杖並再次登入。移除政策會停止新的交換，但已發行的存取權杖在過期前仍然有效。

Tuist 會在專用的大小限制快取中快取提供者的簽署金鑰，成功擷取後最多保留 15 分鐘。項目可能會更早被驅逐並再次擷取。失敗的擷取不會被快取。如果你的提供者輪換金鑰，應在使用新金鑰簽署權杖前至少 15 分鐘將其發布到 JWKS 中，因為使用不在快取集合中的金鑰簽署的權杖會被拒絕，直到快取過期。沒有金鑰 ID (`kid`) 的權杖僅在 JWKS 包含單一合格簽署金鑰時才被接受。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用的權杖輸入，並非繞過伺服器信任的方法。它優先於 CI 提供者偵測，且伺服器仍僅接受內建提供者和具有相符信任政策的身分。請勿將身分權杖放入 `TUIST_TOKEN`，因為它預期的是 Tuist 憑證。

如果交換失敗，請檢查政策中的發行者、受眾和每個聲明是否與權杖完全相符，JWKS URL 是否提供簽署權杖的金鑰，政策是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否指名擁有該專案的帳戶。為了避免暴露哪些身分受信任，Tuist 對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身分](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本機 `/.fly/api` Unix socket 請求短期、已簽署的身分權杖，無需 Fly API 權杖或長效 Tuist 秘密。Fly 權杖識別組織和應用程式，而非原始碼儲存庫，因此請使用信任政策而非連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部發行的身分權杖中取得發行者 (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。發行者為 `https://oidc.fly.io/<organization-slug>`。使用數字 ID，而非組織或應用程式名稱。
2. 使用 **Fly.io Machines** 範本 [建立信任政策](#create-a-trust-policy)，並輸入組織代號和兩個數字 ID。它會填寫下方的值並將 ID 保持為字串。你也可以使用 **自訂提供者** 手動輸入它們；在聲明中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | 發行者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 受眾 | `tuist` |
   | 聲明 | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶代號（而非 Fly 組織代號），請求受眾為 `tuist` 的權杖，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

在初始設定階段，你可以在匯出權杖後、取消設定前，僅在本機檢查身分欄位。這會解碼聲明以供設定使用；Tuist 會在驗證期間 separately 驗證簽章：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

請勿列印或提交權杖本身。已授權 Fly 應用程式中的每個 Machine 都可以向 Tuist 帳戶中的所有現有和未來專案進行驗證。為每個額外的應用程式建立獨立的政策。Fly 身分權杖約十分鐘後過期，因此在長期運行的 Machine 上，請在 Tuist 一小時工作階段過期前請求新的權杖並再次執行 `tuist auth login`。

### OIDC 權杖範圍 {#oidc-token-scopes}

OIDC 權杖被授予 `ci` 範圍群組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供對所有與儲存庫連接的專案的存取權。對於工作負載身分信任政策，這提供對所選帳戶擁有的所有現有和未來專案的存取權，但不授予專案建立、專案管理、執行者管理或帳戶成員管理權限。請參閱 [範圍群組](#scope-groups) 以了解 `ci` 範圍包含的內容。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長效權杖更安全，因為：
> - 無需輪換或管理秘密
> - 權杖為短期有效
> - 驗證綁定至你的儲存庫身分或明確授權的工作負載身分


## Gradle 外掛程式驗證 {#gradle-plugin-authentication}

Gradle 外掛程式使用 Tuist CLI 驗證狀態，並未定義獨立的登入流程。使用 CLI 驗證一次，外掛程式將重複使用這些憑證。

對於專案和伺服器設定（包括 `project` 和 `url`），請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

本機使用時，請執行：

```bash
tuist auth login
```

對於 CI，請使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 驗證</.localized_link>（建議在可用時使用）
- <.localized_link href="/guides/server/authentication#continuous-integration">帳戶權杖驗證</.localized_link> 透過 `TUIST_TOKEN`

對於自託管的 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並執行標準登入流程。URL 從外掛程式使用的同一個設定檔案解析。

設定驗證後，正常執行你的 Gradle 快取命令和任務。

## 帳戶權杖 {#account-tokens}

對於不支援 OIDC 的 CI 環境，或當你需要細粒度控制權限時，你可以使用帳戶權杖。帳戶權杖允許你精確指定權杖可以存取的範圍和專案。

### 建立帳戶權杖 {#creating-an-account-token}

建立帳戶權杖最簡單的方法是透過儀表板：

1. 在 Tuist 儀表板中開啟組織。
2. 前往 **設定** > **權杖**。
3. 選擇 **產生權杖**。
4. 選擇名稱、可選的到期時間、專案存取權以及權杖所需的範圍。
5. 在關閉對話框之前複製產生的權杖值。權杖值僅顯示一次。

你也可以從 CLI 建立帳戶權杖，這對腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想讓權杖存取之專案的帳戶代號。這可以是組織帳戶，不一定是你的個人帳戶。

該命令接受以下選項：

| 選項 | 說明 |
| --- | --- |
| `--scopes` | 必填。以逗號分隔的範圍清單，用於授予權杖。 |
| `--name` | 必填。權杖的唯一識別碼（1-32 個字元，僅限字母數字、連字號和下劃線）。 |
| `--expires` | 可選。權杖應到期的時間。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。若未指定，權杖永不過期。 |
| `--projects` | 將權杖限制為特定專案代號。若未指定，權杖可存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 說明 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進位檔 |
| `account:cache:write` | 上傳帳戶範圍的快取二進位檔 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:registry:read` | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發布至 Swift 套件註冊表 |
| `account:runners:read` | 讀取執行器工作、工作流程、設定檔和磁碟區 |
| `account:runners:write` | 管理執行器設定檔並清除執行器磁碟區 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要具有所有專案存取權的權杖 |
| `project:cache:read` | 下載快取二進位檔 |
| `project:cache:write` | 上傳快取二進位檔 |
| `project:bundles:read` | 檢視套件 |
| `project:bundles:write` | 上傳套件 |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取建置分析 |
| `project:builds:write` | 上傳建置分析 |
| `project:runs:read` | 讀取命令執行 |
| `project:runs:write` | 建立和更新命令執行 |

### 範圍群組 {#scope-groups}

範圍群組提供一種便捷的方式，可透過單一識別碼授予多個相關範圍。當你使用範圍群組時，它會自動展開以包含其所含的所有個別範圍。

| 範圍群組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立具有 `ci` 範圍群組的帳戶權杖，以驗證你的 CI 工作流程。在儀表板中產生權杖時，請選擇 **CI** 預設值。

你也可以從 CLI 建立相同的權杖：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 操作所需所有範圍（快取、預覽、套件、測試、建置和執行）的權杖。將產生的權杖作為機密儲存在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### 管理帳戶權杖 {#managing-account-tokens}

在帳戶儀表板中開啟 **設定** > **權杖**，以檢視帳戶權杖、檢查權杖的範圍和專案存取權，並在輪換期間撤銷權杖。

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
> 當你需要以下內容時，請使用帳戶權杖：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對權杖可執行的操作進行細粒度控制
> - 一個可以存取帳戶內多個專案的權杖
> - 具有自動到期時間限制的權杖
