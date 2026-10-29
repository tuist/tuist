---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 驗證 {#authentication}

要與伺服器互動，CLI 需要使用 [Bearer 驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/) 來驗證請求。CLI 支援以使用者身份、帳戶身份或使用 OIDC Token 進行驗證。

## 以使用者身份 {#as-a-user}

當你在本機上使用 CLI 時，我們建議以使用者身份進行驗證。要以使用者身份驗證，你需要執行以下指令：

```bash
tuist auth login
```

該指令會引導你完成基於網頁的驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存一個長期有效的刷新 Token 和一個短期有效的存取 Token。目錄中的每個檔案代表你驗證過的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果存取 Token 已過期，CLI 將使用刷新 Token 來獲取新的存取 Token。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電子郵件地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link> 中找到提供者。

## OIDC Token {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的密鑰。在受支援的 CI 環境中運行時，CLI 會自動檢測 OIDC Token 提供者，並將 CI 提供的 Token 交換為 Tuist 存取 Token。

### 支援的提供者 {#supported-ci-providers}

Tuist 識別這些 CI 提供者，並透過你的儲存庫連線將它們的 Token 對應到專案：

- GitHub Actions
- CircleCI
- Bitrise

任何其他發行 OpenID Connect Token 的身份提供者都可以透過 [工作負載身份信任政策](#workload-identity-trust-policies) 進行驗證，你只需為帳戶中的所有現有和未來專案配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

對於 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連接到你的 Tuist 專案。

2. **執行 `tuist auth login`**：在你的 CI 工作流程中，在任何需要驗證的指令之前執行 `tuist auth login`。CLI 會自動檢測 CI 環境並使用 OIDC 進行驗證。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取特定於提供者的配置範例。

### 工作負載身份信任政策 {#workload-identity-trust-policies}

信任政策允許來自另一個身份提供者（例如部署平台、Kubernetes 叢集或自行管理的 CI 系統）的工作負載存取專案，而無需長期有效的 Tuist 密鑰。提供者必須：

- 透過 HTTPS 在公共位址上可存取。Tuist 不會追蹤重新導向，也不會連接到私人或內部網路位址，包括來自自行託管的 Tuist 伺服器。
- 簽發使用非對稱金鑰簽署的 JWT，例如 `RS256` 或 `ES256`。未簽署的 Token 和使用共享密鑰簽署的 Token（`HS256` 及類似方式）會被拒絕。
- 在固定的 HTTPS URL 上以 JSON Web Key Set (JWKS) 形式發布其簽章金鑰。回應大小不得超過 64 KiB，且最多包含 20 個金鑰。
- 每個 Token 都必須包含過期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 發行者僅保留用於上述基於儲存庫的流程，不能用於信任政策。

> [!NOTE]
> 對於自行託管的部署，請在配置工作負載身份或將作業移至它們之前，應用資料庫遷移並升級每個正在服務的 Tuist 伺服器副本。然後將 CLI 或 Elixir 整合升級至支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise 作業繼續使用基於儲存庫的授權，不需要帳戶句柄。在切換生產作業之前，請驗證與預期工作負載的短期 Token 交換和快取操作。要停止新的交換，請移除政策；允許已簽發的 Tuist 存取 Token 最多一小時後過期。刪除政策不會立即撤銷這些 Token。

#### 建立政策 {#create-a-trust-policy}

在 Tuist 儀表板中，開啟你帳戶的 **設定** > **驗證** 並找到 **工作負載身份** 部分。你必須是帳戶管理員（或個人帳戶的所有者）。每個帳戶最多可以有 20 個政策。為帳戶範圍的 CI 存取配置一次身份；無需選擇專案。

使用 **工作負載身份** 旁邊的開關來開啟政策表單。當帳戶有已儲存的身份時，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身份的帳戶，開關預設為關閉。該部分出現在組織的 **SCIM 佈建** 下方。隱藏表單會保留你的草稿，並且不會停用工作負載驗證：已儲存身份的卡片和設定文件連結仍然可見。每張卡片顯示身份的名稱、發行者和 JWKS URL、受眾、精確的 JSON Claims、帳戶範圍和建立時間。使用卡片上的操作移除身份。

選擇 **自訂提供者** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織 Slug 以及數字的組織和應用程式 ID 生成它們。Fly 範本會在 **進階配置** 下保持生成的發行者、JWKS URL 和 Claims 可編輯。更改範本或輔助值會保留你手動編輯的欄位。如果你的發行者、JWKS URL 或 Claims 覆蓋了範本，Tuist 會展開 **進階配置** 並顯示警告，以便你可以檢視將要儲存的政策。切換回 **自訂提供者** 以在不使用 Fly 輔助工具的情況下繼續。範本僅填寫配置，不會改變 Tuist 驗證 Token 的方式。

| 欄位 | 描述 |
| --- | --- |
| 名稱 | 用於識別政策的標籤，在帳戶內必須唯一。 |
| 發行者 URL | Token 的 `iss` Claim。它必須完全匹配，包括任何尾隨斜線。 |
| JWKS URL | 提供者的簽署金鑰的 HTTPS URL。Tuist 直接使用此 URL，不會讀取提供者的 OpenID Connect 探索文件，因此請從提供者的文件或 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| 受眾 | Token 必須為其發行的受眾，預設為 `tuist`。Token 的 `aud` 必須等於它，或者當 `aud` 是列表時包含它。使用只有 Tuist 接受的值，這樣為其他服務鑄造的 Token 就無法在此重放。 |
| Claims | 一個包含 1 到 10 個 Token 必須包含的 Claims 的 JSON 物件，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、有符號 64 位整數或布林值，並且必須完全匹配，包括其類型：`"123"` 不匹配 `123`。不允許巢狀物件、列表以及時間或 Token Claims，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個政策授予對 **帳戶擁有的所有當前和未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在建立第一個專案之前配置身份。這不會授予帳戶管理權限或對另一個帳戶的存取權限。

每個能夠獲得具有匹配 Claims 的 Token 的工作負載都可以存取所有這些專案，因此請選擇提供者保證且無人可以重複使用的 Claims。優先使用穩定的數字 ID，而不是可以在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共享身份提供者上，將政策綁定到你的組織或租戶 **以及** 預期的應用程式、專案或服務帳戶。像 `main` 這樣的分支名稱、像 `production` 這樣的環境或單獨的通用角色並不是身份邊界：另一個租戶可能會獲得具有相同值的 Token。例如，GitLab.com 政策必須包含預期專案的穩定 `project_id`，而不僅僅是 `ref`。匹配的 Token 授予帳戶範圍的 CI 存取權限，包括快取寫入，因此信任無關工作負載的政策可能會允許快取污染。

Tuist 僅對其自身 JWKS URL 持有簽署 Token 的金鑰的政策授予存取權限，並在檢查發行者、受眾、過期時間、不早於時間（最多 60 秒的時鐘偏差）以及每個 Claim 之後。發行的一小時 CI Token 是帳戶範圍的，而不是專案 ID 的快照：它包括在發行後建立或轉移到帳戶中的專案。專案授權仍然需要當前的帳戶所有權，因此將專案轉移出去會移除其在該帳戶 Token 下的存取權限。

#### 驗證工作負載 {#authenticate-a-workload}

1. 向你的提供者請求具有政策受眾的身份 Token。
2. 將 `TUIST_OIDC_TOKEN` 設定為該 Token，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶的控制代碼。每個信任政策交換都需要帳戶。它僅選擇查找位置，本身不授予任何權限。
3. 執行 `tuist auth login`。對於 Elixir 專案，你可以改用 `mix tuist.login`，或者在沒有 `TUIST_TOKEN` 或有效儲存的憑證時讓 Elixir 整合自動交換 Token。

產生的 Tuist 存取 Token 僅具有 `ci` 範圍組，並涵蓋所選帳戶擁有的所有當前和未來專案。如果帳戶中超過 20 個政策匹配同一個 Token，或者它們使用超過兩個不同的 JWKS URL，則交換會失敗。

Tuist 不會刷新這些工作階段。存取 Token 在一小時後過期，且沒有刷新 Token。提供者身份 Token 通常僅在幾分鐘內有效，因此保留舊的 `TUIST_OIDC_TOKEN` 不是續訂策略：對於運行時間超過一小時的工作，請請求新的身份 Token 並在 Tuist 工作階段過期前再次登入。移除政策會停止新的交換，但已發行的存取 Token 在過期前仍然有效。

Tuist 在專用且大小受限的快取中快取提供者的簽署金鑰，成功獲取後最多保留 15 分鐘。條目可能會更早被逐出並再次獲取。失敗的獲取不會被快取。如果你的提供者輪換金鑰，它應該在使用新金鑰簽署 Token 之前至少 15 分鐘將其發布在其 JWKS 中，因為使用不在快取集中的金鑰簽署的 Token 會被拒絕，直到快取過期。只有當 JWKS 包含單個合格的簽署金鑰時，才接受沒有金鑰 ID (`kid`) 的 Token。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是一個通用的 Token 輸入，不是繞過伺服器信任的方法。它優先於 CI 提供者檢測，伺服器仍然只接受內建提供者和具有匹配信任政策的身份。不要將身份 Token 放入 `TUIST_TOKEN`，它期望的是 Tuist 憑證。

如果交換失敗，請檢查政策中的發行者、受眾和每個 Claim 是否與 Token 完全匹配，JWKS URL 是否提供簽署 Token 的金鑰，政策是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了擁有該專案的帳戶。為了避免暴露哪些身份受信任，Tuist 對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC 工作負載身份](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本地的 `/.fly/api` Unix socket 請求短暫的、已簽名的身份 Token，無需 Fly API Token 或長效的 Tuist 秘密。Fly Token 識別組織和應用程式，而不是原始碼儲存庫，因此請使用信任政策而不是連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部發行的身份 Token 中獲取發行者 (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。發行者是 `https://oidc.fly.io/<organization-slug>`。使用數字 ID，而不是組織或應用程式名稱。
2. 使用 **Fly.io Machines** 範本 [建立信任政策](#create-a-trust-policy)，並輸入組織 Slug 和兩個數字 ID。它會填寫下面的值並將 ID 保持為字串。你也可以使用 **自訂提供者** 手動輸入它們；在 Claims 中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | 發行者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 受眾 | `tuist` |
   | Claims | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶控制代碼（而不是 Fly 組織 Slug），請求受眾為 `tuist` 的 Token，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

對於初始設定，你可以在匯出 Token 之後、取消設定之前，僅在本地檢查身份欄位。這會解碼 Claims 以進行配置；Tuist 會在驗證期間單獨驗證簽名：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要列印或提交 Token 本身。已授權 Fly 應用程式中的每個 Machine 都可以驗證 Tuist 帳戶中的所有現有和未來專案。為每個額外的應用程式建立單獨的政策。Fly 身份 Token 大約十分鐘後過期，因此在長時間運行的 Machine 上，請在一個小時的 Tuist 工作階段過期之前請求新的 Token 並再次運行 `tuist auth login`。

### OIDC Token 範圍 {#oidc-token-scopes}

OIDC Token 被授予 `ci` 範圍群組。對於 GitHub Actions、CircleCI 和 Bitrise，這提供了對連接到儲存庫的所有專案的存取權限。對於工作負載身份信任政策，這提供了對所選帳戶擁有的所有現有和未來專案的存取權限，而不授予專案建立、專案管理、Runner 管理或帳戶成員管理權限。請參閱 [範圍群組](#scope-groups) 以了解 `ci` 範圍包含的內容詳情。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長效 Token 更安全，因為：
> - 無需輪換或管理秘密
> - Token 是短暫的
> - 驗證與你的儲存庫身份或明確授權的工作負載身份綁定


## Gradle 外掛程式驗證 {#gradle-plugin-authentication}

Gradle 外掛程式使用 Tuist CLI 驗證狀態，並且不定義單獨的登入流程。使用 CLI 驗證一次，外掛程式將重用這些憑證。

對於專案和伺服器配置，包括 `project` 和 `url`，請使用規範的 <.localized_link href="/references/tuist-toml">tuist.toml 參考</.localized_link>。

對於本地使用，請運行：

```bash
tuist auth login
```

對於 CI，請使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 驗證</.localized_link>（建議在可用時使用）
- <.localized_link href="/guides/server/authentication#continuous-integration">帳戶 Token 驗證</.localized_link> 透過 `TUIST_TOKEN`

對於自託管 Tuist 伺服器，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並運行標準登入流程。URL 從外掛程式使用的同一個配置文件解析。

配置驗證後，正常運行你的 Gradle 快取命令和任務。

## 帳戶 Token {#account-tokens}

對於不支援 OIDC 的 CI 環境，或者當你需要對權限進行細粒度控制時，你可以使用帳戶 Token。帳戶 Token 允許你精確指定 Token 可以存取的範圍和專案。

### 建立帳戶 Token {#creating-an-account-token}

建立帳戶 Token 最簡單的方法是從儀表板：

1. 在 Tuist 儀表板中打開組織。
2. 前往 **設定** > **Token**。
3. 選擇 **產生 Token**。
4. 選擇名稱、可選過期時間、專案存取權限以及 Token 所需的範圍。
5. 在關閉對話框之前複製產生的 Token 值。Token 值僅顯示一次。

你也可以從 CLI 建立帳戶 Token，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想要 Token 存取的專案的帳戶控制代碼。這可以是組織帳戶，不一定是你的個人帳戶。

該命令接受以下選項：

| 選項 | 描述 |
| --- | --- |
| `--scopes` | 必填。要授予 Token 的範圍的逗號分隔列表。 |
| `--name` | 必填。Token 的唯一標識符（1-32 個字元，僅限字母數字、連字號和下劃線）。 |
| `--expires` | 可選。Token 應何時過期。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。如果未指定，Token 永遠不會過期。 |
| `--projects` | 將 Token 限制為特定的專案控制代碼。如果未指定，Token 可以存取所有專案。 |

### 可用範圍 {#available-scopes}

| 範圍 | 描述 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進位檔案 |
| `account:cache:write` | 上傳帳戶範圍的快取二進位檔案 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:registry:read` | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發布到 Swift 套件註冊表 |
| `account:runners:read` | 讀取 runner 作業、工作流程、設定檔和磁碟區 |
| `account:runners:write` | 管理 runner 設定檔並清除 runner 磁碟區 |
| `project:previews:read` | 下載預覽 |
| `project:previews:write` | 上傳預覽 |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要一個具有所有專案存取權限的 Token |
| `project:cache:read` | 下載快取二進位檔案 |
| `project:cache:write` | 上傳快取二進位檔案 |
| `project:bundles:read` | 檢視捆綁包 |
| `project:bundles:write` | 上傳捆綁包 |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上傳測試結果 |
| `project:builds:read` | 讀取建置分析 |
| `project:builds:write` | 上傳建置分析 |
| `project:runs:read` | 讀取命令執行 |
| `project:runs:write` | 建立和更新命令執行 |

### 範圍群組 {#scope-groups}

範圍群組提供了一種方便的方式，透過單一標識符授予多個相關範圍。當你使用範圍群組時，它會自動展開以包含其包含的所有單獨範圍。

| 範圍群組 | 包含的範圍 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持續整合 {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立一個帶有 `ci` 範圍群組的帳戶 Token 來驗證你的 CI 工作流程。在儀表板中，產生 Token 時選擇 **CI** 預設值。

你也可以從 CLI 建立相同的 Token：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 操作所需所有範圍（快取、預覽、捆綁包、測試、建置和執行）的 Token。將產生的 Token 作為機密儲存在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### 管理帳戶 Token {#managing-account-tokens}

在帳戶儀表板中打開 **設定** > **Token** 以檢視帳戶 Token、檢查 Token 的範圍和專案存取權限，以及在輪換期間撤銷 Token。

要列出帳戶的所有 Token：

```bash
tuist account tokens list account-handle
```

要按名稱撤銷 Token：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用帳戶 Token {#using-account-tokens}

帳戶 Token 應定義為環境變數 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用帳戶 Token**
>
> 當你需要時使用帳戶 Token：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對 Token 可以執行的操作進行細粒度控制
> - 一個可以存取帳戶內多個專案的 Token
> - 具有自動過期時間限制的 Token
