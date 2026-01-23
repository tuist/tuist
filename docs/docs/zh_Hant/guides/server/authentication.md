---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 驗證{#authentication}

為與伺服器互動，命令列介面需透過[承載者驗證](https://swagger.io/docs/specification/authentication/bearer-authentication/)驗證請求。本介面支援以使用者身分、帳戶身分或使用OIDC憑證進行驗證。

## 身為使用者{#as-a-user}

在本地機器上使用 CLI 時，建議以使用者身分進行驗證。欲以使用者身分驗證，請執行以下指令：

```bash
tuist auth login
```

此指令將引導您完成網頁式驗證流程。驗證成功後，CLI 會將長效刷新令牌與短效存取令牌儲存至`~/.config/tuist/credentials 目錄下的`
檔案。該目錄內每個檔案代表您驗證的網域，預設應為`tuist.dev.json 及` 。此目錄所儲存的資訊屬敏感資料，請務必妥善保管**並確保其安全** 。

CLI 在向伺服器發送請求時會自動查詢憑證。若存取權杖已過期，CLI 將使用更新權杖取得新的存取權杖。

## OIDC 通證{#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的持續整合環境，Tuist 可自動完成驗證，無需您管理長期存效的機密金鑰。在支援的 CI
環境中執行時，命令列介面將自動偵測 OIDC 憑證提供者，並將 CI 提供的憑證兌換為 Tuist 存取憑證。

### 支援的 CI 供應商{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### 設定 OIDC 驗證{#setting-up-oidc-authentication}

1. **將您的儲存庫連結至 Tuist** ：請遵循
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub
   整合指南</LocalizedLink>，將您的 GitHub 儲存庫連結至 Tuist 專案。

2. **執行 `tuist auth login`**: 在您的 CI 工作流程中，於任何需要驗證的指令執行前，請先執行`tuist auth login`
   。CLI 將自動偵測 CI 環境並透過 OIDC 進行驗證。

請參閱
<LocalizedLink href="/guides/integrations/continuous-integration">持續整合指南</LocalizedLink>
以獲取供應商專屬的設定範例。

### OIDC 憑證作用範圍{#oidc-token-scopes}

OIDC 憑證授予`ci` 範圍群組，該群組可存取與儲存庫連結的所有專案。有關`ci` 範圍群組的詳細內容，請參閱 [範圍群組](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC 驗證比長期存活的憑證更安全，因為：
- 無需輪替或管理的機密
- 代幣具有短暫生命週期，且僅限於個別工作流程執行範圍內生效
- 驗證機制與您的儲存庫身分綁定
<!-- -->
:::

## 帳戶令牌{#account-tokens}

對於不支援 OIDC 的 CI 環境，或需要精細控制權限時，可使用帳戶代幣。帳戶代幣能精確指定代幣可存取的範圍與專案。

### 建立帳戶令牌{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

此指令接受以下選項：

| 選項          | 說明                                                         |
| ----------- | ---------------------------------------------------------- |
| `--範圍`      | 必填。以逗號分隔的權限範圍清單，用於授予代幣權限。                                  |
| `--name`    | 必填。代幣的唯一識別碼（1-32個字元，僅限英數字元、連字號及底線）。                        |
| `--expires` | 可選。指定代幣失效時間。格式如下：`30d` （天）、`6m` （月）、或`1y` （年）。若未指定，代幣永久有效。 |
| `--專案`      | 將代幣限制於特定專案代號。若未指定，該代幣將可存取所有專案。                             |

### 可用範圍{#available-scopes}

| 範圍                       | 說明              |
| ------------------------ | --------------- |
| `account:members:read`   | 閱讀帳戶成員          |
| `account:members:write`  | 管理帳戶成員          |
| `帳戶：註冊表：讀取`              | 從 Swift 套件註冊表讀取 |
| `帳戶：註冊表：寫入`              | 發佈至 Swift 套件註冊庫 |
| `project:previews:read`  | 下載預覽            |
| `project:previews:write` | 上傳預覽            |
| `project:admin:read`     | 閱讀專案設定          |
| `project:admin:write`    | 管理專案設定          |
| `project:cache:read`     | 下載快取二進位檔        |
| `project:cache:write`    | 上傳快取二進位檔        |
| `project:bundles:read`   | 檢視套件            |
| `project:bundles:write`  | 上傳組合包           |
| `project:tests:read`     | 閱讀測試結果          |
| `project:tests:write`    | 上傳測試結果          |
| `project:builds:read`    | 閱讀建置分析          |
| `project:builds:write`   | 上傳建置分析資料        |
| `project:runs:read`      | 讀取指令執行          |
| `project:runs:write`     | 建立與更新指令執行       |

### 作用域群組{#scope-groups}

範圍群組提供了一種便捷方式，可透過單一識別碼授予多個相關範圍。使用範圍群組時，系統會自動展開包含所有個別範圍。

| 範圍群組 | 包含範圍                                                                                                                                     |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci` | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持續整合 (CI){#continuous-integration-ci}

對於不支援 OIDC 的 CI 環境，可透過`ci` 建立具有 scope group 的帳戶令牌，用於驗證 CI 工作流程：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

此操作將產生包含典型 CI 操作所需所有作用域（快取、預覽、套件、測試、建置及執行）的代幣。請將生成的代幣儲存為 CI
環境中的機密，並設定為環境變數：`TUIST_TOKEN`

### 管理帳戶令牌{#managing-account-tokens}

要列出帳戶的所有代幣：

```bash
tuist account tokens list my-account
```

按名稱撤銷代幣：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用帳戶令牌{#using-account-tokens}

帳戶令牌預期將定義為環境變數：`TUIST_TOKEN`

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
需要時請使用帳戶代幣：
- 在不支援 OIDC 的 CI 環境中進行驗證
- 對標記可執行的操作進行細粒度控制
- 可在單一帳戶內存取多個專案的存取權限令牌
- 限時代幣將自動失效
<!-- -->
:::
