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

該指令會引導你完成基於網頁的驗證流程。驗證成功後，CLI 會在 `~/.config/tuist/credentials` 下儲存一個長期有效的 refresh token 和一個短期有效的 access token。目錄中的每個檔案代表你驗證過的網域，預設應為 `tuist.dev.json`。儲存在該目錄中的資訊屬於敏感資料，因此 **請務必妥善保管**。

CLI 在向伺服器發出請求時會自動查找憑證。如果 access token 已過期，CLI 將使用 refresh token 獲取新的 access token。

> [!NOTE]
> 如果你的組織使用單一登入 (SSO)，請在瀏覽器中選擇企業登入選項並輸入你的工作電郵地址。Tuist 可以從你現有的組織成員資格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電郵網域</.localized_link> 中找到提供者。

## OIDC tokens {#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動驗證，無需你管理長期有效的 secret。在支援的 CI 環境中運行時，CLI 會自動檢測 OIDC token 提供者，並將 CI 提供的 token 交換為 Tuist access token。

### 支援的提供者 {#supported-ci-providers}

Tuist 識別這些 CI 提供者，並透過你的儲存庫連接將它們的 token 映射到專案：

- GitHub Actions
- CircleCI
- Bitrise

任何其他發出 OpenID Connect tokens 的身份提供者都可以透過 [workload identity trust policy](#workload-identity-trust-policies) 進行驗證，你只需為帳戶中的所有現有及未來專案配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 設定 OIDC 驗證 {#setting-up-oidc-authentication}

對於 GitHub Actions、CircleCI 和 Bitrise：

1. **將你的儲存庫連接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 整合指南</.localized_link> 將你的 GitHub 儲存庫連接到你的 Tuist 專案。

2. **執行 `tuist auth login`**：在你的 CI workflow 中，在任何需要驗證的指令之前執行 `tuist auth login`。CLI 會自動檢測 CI 環境並使用 OIDC 進行驗證。

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取特定於提供者的配置範例。

### Workload identity trust policies {#workload-identity-trust-policies}

Trust policy 允許來自另一個身份提供者（例如部署平台、Kubernetes cluster 或自行管理的 CI 系統）的 workload 存取專案，而無需長期有效的 Tuist secret。提供者必須：

- 透過 HTTPS 在公開地址上可存取。Tuist 不會跟隨重新導向，也不會連接到私人或內部網路地址，包括來自自行託管的 Tuist 伺服器。
- 簽發使用非對稱金鑰簽署的 JWTs，例如 `RS256` 或 `ES256`。未簽名的 token 和使用共享 secret 簽署的 token（`HS256` 及類似方式）會被拒絕。
- 在固定的 HTTPS URL 上將其簽章金鑰發布為 JSON Web Key Set (JWKS)。回應最多為 64 KiB，且最多包含 20 個金鑰。
- 在每个 token 中包含過期時間 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 的 issuers 保留給上述基於儲存庫的流程，不能用於 trust policy。

> [!NOTE]
> 對於自行託管的部署，請在配置 workload identities 或將 jobs 遷移過去之前，應用資料庫遷移並升級每個正在服務的 Tuist server replica。然後將 CLI 或 Elixir 整合升級到支援 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。現有的 GitHub Actions、CircleCI 和 Bitrise jobs 繼續使用基於儲存庫的授權，不需要帳戶 handle。在切換生產 jobs 之前，請驗證短期 token 交換以及與預期 workload 的快取操作。要停止新的交換，請移除 policy；允許已簽發的 Tuist access tokens 最多一小時後過期。刪除 policy 不會立即撤銷這些 tokens。

#### 建立 policy {#create-a-trust-policy}

在 Tuist dashboard 中，打開你帳戶的 **Settings** > **Authentication** 並找到 **Workload identities** 部分。你必須是帳戶管理員（或个人帳戶的所有者）。每個帳戶最多可以有 20 個 policies。為帳戶範圍的 CI 存取配置一次身份；無需選擇專案。

使用 **Workload identities** 旁邊的開關來打開 policy 表單。當帳戶有已儲存的身份時，開關預設為開啟狀態，並在儲存後保持開啟。對於沒有身份的帳戶，開關預設為關閉。該部分出現在組織的 **SCIM provisioning** 下方。隱藏表單會保留你的草稿，並且不會停用 workload 驗證：已儲存身份的卡片和設定文件連結仍然可見。每張卡片顯示身份的名稱、issuer 和 JWKS URLs、audience、精確的 JSON claims、帳戶範圍和建立時間。使用卡片上的操作移除身份。

選擇 **Custom provider** 以輸入以下欄位，或選擇 **Fly.io Machines** 以從你的組織 slug 和數字組織及應用程式 ID 生成它們。Fly 模板保持在 **Advanced configuration** 下可編輯生成的 issuer、JWKS URL 和 claims。更改模板或輔助值會保留你手動編輯的欄位。如果你的 issuer、JWKS URL 或 claims 覆蓋了模板，Tuist 會展開 **Advanced configuration** 並顯示警告，以便你可以審查將要儲存的 policy。切換回 **Custom provider** 以在沒有 Fly 輔助的情況下繼續。模板僅填寫配置，不會改變 Tuist 驗證 token 的方式。

| 欄位 | 描述 |
| --- | --- |
| 名稱 | 用於識別 policy 的標籤，在帳戶內必須唯一。 |
| Issuer URL | Token 的 `iss` claim。它必須完全匹配，包括任何尾部斜線。 |
| JWKS URL | Provider 簽署金鑰的 HTTPS URL。Tuist 會直接使用此 URL，而不會讀取 provider 的 OpenID Connect discovery document，因此請從 provider 的文件或 `<issuer>/.well-known/openid-configuration` 複製 `jwks_uri`。 |
| Audience | Token 必須發行的 audience，預設為 `tuist`。Token 的 `aud` 必須等於它，或者當 `aud` 是清單時包含它。使用只有 Tuist 接受的值，這樣為其他服務鑄造的 token 就無法在此重放。 |
| Claims | 一個 JSON 物件，包含 1 到 10 個 token 必須包含的 claims，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 輸入限制為 8 KiB。值必須是字串、有號 64 位元整數或布林值，並且必須完全匹配，包括其類型：`"123"` 與 `123` 不匹配。不允許巢狀物件、清單以及時間或 token claims，例如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每個 policy 授予對 **帳戶擁有的所有當前和未來專案** 的 CI 存取權限，無需選擇個別專案。你可以在建立第一個專案之前配置身份。這不會授予帳戶管理權限或對另一個帳戶的存取權限。

每個能夠取得具有匹配 claims 的 token 的 workload 都可以存取所有這些專案，因此請選擇 provider 保證且無人可以重複使用的 claims。優先使用穩定的數字 ID，而不是可以在刪除後重新命名或再次註冊的名稱。

> [!WARNING]
> 在共享身份 provider 上，將 policy 綁定到你的組織或租戶 **以及** 目標應用程式、專案或服務帳戶。像 `main` 這樣的分支名稱、像 `production` 這樣的環境或單獨的一般角色並不是身份邊界：另一個租戶可能會取得具有相同值的 token。例如，GitLab.com policy 必須包含目標專案的穩定 `project_id`，而不僅是 `ref`。匹配的 token 授予帳戶範圍的 CI 存取權限，包括快取寫入，因此信任無關 workload 的 policy 可能會允許快取污染。

Tuist 僅在檢查 issuer、audience、過期時間、not-before 時間（最多 60 秒的時鐘偏差）和每個 claim 後，才對其自身 JWKS URL 持有簽署 token 金鑰的 policy 授予存取權限。發行的一小時 CI token 是帳戶範圍的，而不是專案 ID 的快照：它包括發行後建立或轉移到帳戶中的專案。專案授權仍然需要當前帳戶所有權，因此將專案轉移出去會移除其在該帳戶 token 下的存取權限。

#### 驗證 workload {#authenticate-a-workload}

1. 向你的 provider 請求具有 policy audience 的身份 token。
2. 將 `TUIST_OIDC_TOKEN` 設定為該 token，並將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶句柄。每個 trust policy 交換都需要帳戶。它只選擇查找位置，本身不授予任何權限。
3. 執行 `tuist auth login`。對於 Elixir 專案，你可以改用 `mix tuist.login`，或者在沒有 `TUIST_TOKEN` 或有效儲存的憑證時讓 Elixir 整合自動交換 token。

產生的 Tuist access token 僅具有 `ci` scope group，並涵蓋所選帳戶擁有的所有當前和未來專案。如果帳戶中超過 20 個 policy 匹配同一個 token，或者它們使用超過兩個不同的 JWKS URLs，則交換會失敗。

Tuist 不會刷新這些工作階段。Access tokens 在一小時後過期，且沒有 refresh token。Provider 身份 token 通常僅在幾分鐘內有效，因此保留舊的 `TUIST_OIDC_TOKEN` 不是續訂策略：對於運行超過一小時的作业，請在 Tuist 工作階段過期前請求新的身份 token 並再次登入。移除 policy 會停止新交換，但已發行的 access tokens 在過期前仍然有效。

Tuist 在成功獲取後，會在專用的大小限制快取中快取 provider 的簽署金鑰長達 15 分鐘。條目可能會更早被驅逐並再次獲取。失敗的獲取不會被快取。如果你的 provider 輪換金鑰，它應該在用它簽署 token 之前至少 15 分鐘在其 JWKS 中發布新金鑰，因為用不在快取集中的金鑰簽署的 token 會被拒絕，直到快取過期。只有在 JWKS 包含單個符合條件的簽署金鑰時，才接受沒有金鑰 ID (`kid`) 的 token。當 JWKS 中存在金鑰 ID 時，它必須是最多 256 位元組的字串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是一般 token 輸入，不是繞過伺服器信任的方法。它優先於 CI provider 檢測，伺服器仍然只接受內建 provider 和具有匹配 trust policy 的身份。不要將身份 token 放入 `TUIST_TOKEN`，它需要 Tuist 憑證。

如果交換失敗，請檢查 policy 中的 issuer、audience 和每個 claim 是否與 token 完全匹配，JWKS URL 是否提供簽署 token 的金鑰，policy 是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名擁有該專案的帳戶。為了避免暴露哪些身份受信任，Tuist 對所有這些情況返回相同的錯誤。

### Fly.io Machines {#flyio-machines}

[Fly.io 支援 OIDC workload identity](https://docs.fly.io/reference/openid-connect/)。Machine 可以從其本地 `/.fly/api` Unix socket 請求短生命週期、已簽署的身份 token，無需 Fly API token 或長期有效的 Tuist secret。Fly tokens 識別組織和應用程式，而不是原始碼儲存庫，因此請使用 trust policy 而不是連接 GitHub 儲存庫：

1. 從在你的 Fly Machine 內部發行的身份 token 中獲取 issuer (`iss`)、組織 ID (`org_id`) 和應用程式 ID (`app_id`)。Issuer 是 `https://oidc.fly.io/<organization-slug>`。使用數字 ID，而不是組織或應用程式名稱。
2. 使用 **Fly.io Machines** 模板 [建立 trust policy](#create-a-trust-policy) 並輸入組織 slug 和兩個數字 ID。它會填寫下面的值並將 ID 保持為字串。你也可以使用 **Custom provider** 手動輸入它們；在 claims 中保留 ID 周圍的引號。

   | 欄位 | 值 |
   | --- | --- |
   | Issuer URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audience | `tuist` |
   | Claims | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 內部，將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶句柄（不是 Fly 組織 slug），請求具有 audience `tuist` 的 token，並使用 `TUIST_OIDC_TOKEN` 將其傳遞給 `tuist auth login`：

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

初次設定時，你可以在匯出 token 後、取消設定之前，於本機檢查身份欄位。這會解碼 claims 以供設定；Tuist 會在驗證期間單獨驗證簽章：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要列印或提交 token 本身。已授權 Fly app 中的每個 Machine 都可以驗證 Tuist 帳戶中所有現有和未來的專案。為每個額外的 app 建立獨立的 policy。Fly identity tokens 大約十分鐘後過期，因此在長時間運行的 Machines 上，請在一個小時的 Tuist session 過期前請求新的 token 並再次執行 `tuist auth login`。

### OIDC token scopes {#oidc-token-scopes}

OIDC tokens 被授予 `ci` scope group。對於 GitHub Actions、CircleCI 和 Bitrise，這提供對連接到儲存庫的所有專案的存取權限。對於 workload identity trust policies，這提供對所選帳戶擁有的所有現有和未來專案的存取權限，但不授予專案建立、專案管理、runner 管理或帳戶成員管理權限。請參閱 [Scope groups](#scope-groups) 以了解 `ci` scope 包含的內容。

> [!TIP]
> **安全性優勢**
>
> OIDC 驗證比長期有效的 tokens 更安全，因為：
> - 無需輪換或管理 secrets
> - Tokens 生命週期短
> - 驗證綁定到你的儲存庫身份或明確授權的 workload identity


## Gradle plugin authentication {#gradle-plugin-authentication}

Gradle plugin 使用 Tuist CLI 驗證狀態，不定義獨立的登入流程。使用 CLI 驗證一次，plugin 將重用這些憑證。

對於專案和伺服器設定，包括 `project` 和 `url`，請使用標準的 <.localized_link href="/references/tuist-toml">tuist.toml reference</.localized_link>。

對於本機使用，請執行：

```bash
tuist auth login
```

對於 CI，請使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC authentication</.localized_link>（建議在可用時使用）
- 透過 `TUIST_TOKEN` 進行 <.localized_link href="/guides/server/authentication#continuous-integration">Account token authentication</.localized_link>

對於自託管 Tuist servers，請在 `tuist.toml` 中定義伺服器 URL（例如 `url = "https://tuist.your-company.com"`）並執行標準登入流程。URL 從 plugin 使用的同一個設定檔案解析。

設定驗證後，正常執行你的 Gradle caching commands 和 tasks。

## Account tokens {#account-tokens}

對於不支援 OIDC 的 CI 環境，或者當你需要細粒度控制權限時，你可以使用 account tokens。Account tokens 允許你精確指定 token 可以存取的 scopes 和專案。

### 建立 account token {#creating-an-account-token}

建立 account token 最簡單的方法是從 dashboard：

1. 在 Tuist dashboard 中開啟組織。
2. 前往 **Settings** > **Tokens**。
3. 選擇 **Generate token**。
4. 選擇名稱、可選過期時間、專案存取權限以及 token 需要的 scopes。
5. 在關閉對話框之前複製生成的 token 值。Token 值僅顯示一次。

你也可以從 CLI 建立 account tokens，這對於腳本或自動化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 將 `account-handle` 替換為擁有你想讓 token 存取的專案的帳戶句柄。這可以是組織帳戶，不一定是你的個人帳戶。

該命令接受以下選項：

| 選項 | 描述 |
| --- | --- |
| `--scopes` | 必填。以空格分隔的 scopes 列表，授予 token。 |
| `--name` | 必填。token 的唯一識別符（1-32 個字元，僅限字母數字、連字號和下劃線）。 |
| `--expires` | 可選。token 應何時過期。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。如果未指定，token 永不過期。 |
| `--projects` | 將 token 限制為特定專案句柄。如果未指定，token 可以存取所有專案。 |

### 可用 scopes {#available-scopes}

| Scope | 描述 |
| --- | --- |
| `account:cache:read` | 下載帳戶範圍的快取二進制檔案 |
| `account:cache:write` | 上載帳戶範圍的快取二進制檔案 |
| `account:members:read` | 讀取帳戶成員 |
| `account:members:write` | 管理帳戶成員 |
| `account:registry:read` | 從 Swift package registry 讀取 |
| `account:registry:write` | 發佈到 Swift package registry |
| `account:runners:read` | 讀取 runner jobs、workflows、profiles 和 volumes |
| `account:runners:write` | 管理 runner profiles 並刪除 runner volumes |
| `project:previews:read` | 下載 previews |
| `project:previews:write` | 上載 previews |
| `project:admin:read` | 讀取專案及其設定 |
| `project:admin:write` | 建立、更新和刪除專案。建立專案需要具有存取所有專案權限的 token |
| `project:cache:read` | 下載快取二進制檔案 |
| `project:cache:write` | 上載快取二進制檔案 |
| `project:bundles:read` | 檢視 bundles |
| `project:bundles:write` | 上載 bundles |
| `project:tests:read` | 讀取測試結果 |
| `project:tests:write` | 上載測試結果 |
| `project:builds:read` | 讀取建置分析 |
| `project:builds:write` | 上載建置分析 |
| `project:runs:read` | 讀取命令執行 |
| `project:runs:write` | 建立和更新命令執行 |

### Scope groups {#scope-groups}

Scope groups 提供一種方便的方式，透過單一識別符授予多個相關 scopes。當你使用 scope group 時，它會自動展開以包含其包含的所有個別 scopes。

| Scope Group | Included Scopes |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Continuous Integration {#continuous-integration}

對於不支援 OIDC 的 CI 環境，請建立具有 `ci` scope group 的 account token 以驗證你的 CI workflows。在 dashboard 中，生成 token 時選擇 **CI** preset。

你也可以從 CLI 建立相同的 token：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

這會建立一個具有典型 CI 操作所需所有 scopes 的 token（cache、previews、bundles、tests、builds 和 runs）。將生成的 token 作為 secret 存儲在你的 CI 環境中，並將其設定為 `TUIST_TOKEN` 環境變數。

### Managing account tokens {#managing-account-tokens}

在帳戶 dashboard 中開啟 **Settings** > **Tokens** 以檢視 account tokens、檢查 token 的 scopes 和專案存取權限，以及在輪換期間撤銷 token。

列出帳戶的所有 token：

```bash
tuist account tokens list account-handle
```

按名稱撤銷 token：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Using account tokens {#using-account-tokens}

Account tokens 應定義為環境變數 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何時使用 account tokens**
>
> 當你需要以下情況時使用 account tokens：
> - 在不支援 OIDC 的 CI 環境中進行驗證
> - 對 token 可以執行的操作進行細粒度控制
> - 可以存取帳戶內多個專案的 token
> - 具有自動過期功能的限時 token
