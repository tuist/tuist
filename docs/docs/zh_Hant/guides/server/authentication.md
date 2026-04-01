---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 驗證{#authentication}

為了與伺服器進行互動，CLI 需要使用
[承載者驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/)
來驗證請求。CLI 支援以使用者身分、帳戶身分，或使用 OIDC 憑證進行驗證。

## 身為使用者{#as-a-user}

在您的電腦上本地使用 CLI 時，我們建議以使用者身分進行驗證。若要以使用者身分驗證，您需要執行以下指令：

```bash
tuist auth login
```

此指令將引導您完成基於網頁的驗證流程。驗證完成後，CLI 會將一個長效刷新憑證和一個短效存取憑證儲存於`~/.config/tuist/credentials`
目錄下。該目錄中的每個檔案代表您所驗證的網域，預設應為`tuist.dev.json` 。此目錄中儲存的資訊屬於敏感資料，請務必妥善保管**** 。

當 CLI 向伺服器發送請求時，系統會自動查詢憑證。若存取憑證已過期，CLI 將使用刷新憑證來取得新的存取憑證。

## OIDC 標記{#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可自動進行身份驗證，無需您管理長期有效的密鑰。在受支援的 CI
環境中執行時，CLI 會自動偵測 OIDC 憑證提供者，並將 CI 提供的憑證兌換為 Tuist 存取憑證。

### 支援的 CI 服務供應商{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### 設定 OIDC 驗證{#setting-up-oidc-authentication}

1. **將您的儲存庫連接到 Tuist**: 請依照
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub
   整合指南</LocalizedLink>，將您的 GitHub 儲存庫連接到 Tuist 專案。

2. **執行 `tuist auth login`** ：在您的 CI 工作流程中，請在任何需要驗證的指令之前執行`tuist auth login`
   。CLI 會自動偵測 CI 環境，並透過 OIDC 進行驗證。

請參閱
<LocalizedLink href="/guides/integrations/continuous-integration">持續整合指南</LocalizedLink>，以取得特定供應商的設定範例。

### OIDC 標記作用域{#oidc-token-scopes}

OIDC 憑證將被授予`ci` 範圍群組，該群組提供對該儲存庫所連接之所有專案的存取權限。關於`ci` 範圍所包含的內容詳情，請參閱
[範圍群組](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC 驗證比長期有效憑證更安全，因為：
- 無需輪替或管理的秘密
- 標記的存活時間很短，且僅限於個別工作流程執行範圍內
- 驗證與您的儲存庫身分相關
<!-- -->
:::

## 帳戶代碼{#account-tokens}

對於不支援 OIDC 的 CI 環境，或當您需要對權限進行細緻控制時，可以使用帳戶憑證。帳戶憑證可讓您精確指定該憑證可存取的範圍與專案。

### 建立帳戶憑證{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

此指令接受以下選項：

| 選項       | 說明                                                           |
| -------- | ------------------------------------------------------------ |
| `--作用域`  | 必填。以逗號分隔的權限範圍清單，用於授予該令牌權限。                                   |
| `--name` | 必填。此為該標記的唯一識別碼（1 至 32 個字元，僅限英數字、連字號及底線）。                     |
| `--過期`   | 可選。指定代幣的過期時間。格式如下：`30d` （天）、`6m` （月），或`1y` （年）。若未指定，代幣將永不過期。 |
| `--專案`   | 將權限限制在特定專案識別碼上。若未指定，該權限將可存取所有專案。                             |

### 可用範圍{#available-scopes}

| 適用範圍                     | 說明               |
| ------------------------ | ---------------- |
| `account:members:read`   | 讀取帳戶成員           |
| `account:members:write`  | 管理帳戶成員           |
| `account:registry:read`  | 從 Swift 套件註冊表中讀取 |
| `account:registry:write` | 發佈至 Swift 套件註冊表  |
| `project:previews:read`  | 下載預覽             |
| `project:previews:write` | 上傳預覽             |
| `project:admin:read`     | 閱讀專案設定           |
| `project:admin:write`    | 管理專案設定           |
| `project:cache:read`     | 下載快取二進位檔         |
| `project:cache:write`    | 上傳快取二進位檔         |
| `project:bundles:read`   | 檢視套件             |
| `project:bundles:write`  | 上傳套件             |
| `project:tests:read`     | 閱讀測試結果           |
| `project:tests:write`    | 上傳測試結果           |
| `project:builds:read`    | 閱讀建置分析           |
| `project:builds:write`   | 上傳建置分析           |
| `project:runs:read`      | 讀取指令執行           |
| `project:runs:write`     | 建立與更新指令執行        |

### 範圍群組{#scope-groups}

範圍群組提供了一種便捷的方式，可透過單一識別碼授予多個相關範圍。當您使用範圍群組時，它會自動展開以包含其所包含的所有個別範圍。

| Scope Group | 包含範圍                                                                                                                                     |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`        | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持續整合 (CI){#continuous-integration-ci}

對於不支援 OIDC 的 CI 環境，您可以建立一個具有`ci` 權限群組的帳戶憑證，以驗證您的 CI 工作流程：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

這會產生一個包含典型 CI 操作所需所有範圍（快取、預覽、封裝、測試、建置和執行）的憑證。請將生成的憑證作為機密儲存於您的 CI
環境中，並將其設定為`TUIST_TOKEN` 環境變數。

### 管理帳戶憑證{#managing-account-tokens}

要列出某個帳戶的所有標記：

```bash
tuist account tokens list my-account
```

若要根據名稱撤銷代幣：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用帳戶代碼{#using-account-tokens}

帳戶代號應定義為環境變數`TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
在需要時請使用帳戶代碼：
- 在不支援 OIDC 的 CI 環境中的驗證
- 對標記可執行的操作進行細緻控制
- 可在單一帳戶內存取多個專案的標記
- 會自動過期的限時代幣
<!-- -->
:::
