---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 驗證{#authentication}

要與伺服器互動，CLI 需要使用 [bearer
authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/)
來驗證請求。CLI 支援以使用者、帳號或使用 OIDC 令牌進行驗證。

## 身為使用者{#as-a-user}

在本機使用 CLI 時，我們建議您以使用者身份進行驗證。要以使用者身份驗證，您需要執行以下指令：

```bash
tuist auth login
```

該指令會帶您經過網頁式驗證流程。驗證完成後，CLI 會在`~/.config/tuist/credentials`
下儲存一個長效的刷新令牌和一個短效的存取令牌。該目錄中的每個檔案代表您驗證的網域，預設應為`tuist.dev.json`
。該目錄中儲存的資訊相當敏感，因此**請務必妥善保管** 。

CLI 在向伺服器提出要求時會自動查詢憑證。如果存取權限已過期，CLI 會使用刷新權限來取得新的存取權限。

## OIDC 代幣{#oidc-tokens}

對於支援 OpenID Connect (OIDC) 的 CI 環境，Tuist 可以自動進行驗證，而不需要您管理長期保密資訊。在支援的 CI
環境中執行時，CLI 會自動偵測 OIDC 令牌提供者，並將 CI 提供的令牌交換為 Tuist 存取令牌。

### 支援的 CI 提供者{#supported-ci-providers}

- GitHub 動作
- CircleCI
- Bitrise

### 設定 OIDC 驗證{#setting-up-oidc-authentication}

1. **將您的套件庫連接到 Tuist**: 按照
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub 整合指南</LocalizedLink>，將您的 GitHub 套件庫連接到 Tuist 專案。

2. **執行 `tuist auth login`** ：在您的 CI 工作流程中，在任何需要驗證的指令之前執行`tuist auth login` 。CLI
   會自動偵測 CI 環境，並使用 OIDC 進行驗證。

請參閱 <LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integration 指南</LocalizedLink>，以瞭解特定提供商的配置範例。

### OIDC 令牌範圍{#oidc-token-scopes}

OIDC 原始碼授權給`ci` scope group，可存取與儲存庫相連的所有專案。有關`ci` 範圍包括的詳細資訊，請參閱
[範圍群組](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC 驗證比長期使用的權杖更安全，因為：
- 無須輪換或管理秘密
- 代幣的有效期很短，而且只適用於個別工作流程的執行
- 驗證與您的儲存庫身分掛鉤
<!-- -->
:::

## 帳戶代幣{#account-tokens}

對於不支援 OIDC 的 CI 環境，或當您需要對權限進行精細控制時，您可以使用帳戶令牌。帳戶令牌可讓您精確指定令牌可以存取的範圍和專案。

### 建立帳戶標記{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

指令接受下列選項：

| 選項     | 說明                                                          |
| ------ | ----------------------------------------------------------- |
| `-範圍`  | 必填。以逗號分隔的範圍清單，以授予權標。                                        |
| `--名稱` | 必須填寫。令牌的唯一識別碼（1-32 個字元，僅限字母、數字、連字符號及底線）。                    |
| `--到期` | 可選擇。令牌的到期時間。使用格式如`30d` (天)、`6m` (月)，或`1y` (年)。如果未指定，令牌永不過期。 |
| `--項目` | 限制令牌存取特定專案句柄。如果未指定，令牌可存取所有專案。                               |

### 可用範圍{#available-scopes}

| 範圍                       | 說明              |
| ------------------------ | --------------- |
| `帳戶:成員:讀取`               | 讀取帳戶成員          |
| `account:members:write`  | 管理帳戶成員          |
| `帳號:註冊表:讀取`              | 從 Swift 套件註冊表讀取 |
| `account:registry:write` | 發佈至 Swift 套件註冊表 |
| `專案:預覽:閱讀`               | 下載預覽            |
| `project:previews:write` | 上傳預覽            |
| `project:admin:read`     | 讀取專案設定          |
| `project:admin:write`    | 管理專案設定          |
| `專案:快取:讀取`               | 下載快取的二進位檔       |
| `project:cache:write`    | 上傳快取的二進位檔       |
| `project:bundles:read`   | 檢視束裝產品          |
| `project:bundles:write`  | 上傳束裝            |
| `project:tests:read`     | 讀取測試結果          |
| `project:tests:write`    | 上傳測試結果          |
| `專案:建置:讀取`               | 閱讀建立分析          |
| `project:builds:write`   | 上傳建立分析          |
| `專案:執行:讀取`               | 讀取指令執行          |
| `project:runs:write`     | 建立與更新指令執行       |

### 範圍群組{#scope-groups}

作用域群組提供了一種方便的方式，可以使用單一識別碼授予多個相關的作用域。當您使用作用域群組時，它會自動展開以包含它所包含的所有個別作用域。

| 範圍組  | 包含的鏡頭                                                                                                                                    |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci` | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持續整合 (CI){#continuous-integration-ci}

對於不支援 OIDC 的 CI 環境，您可以使用`ci` 範圍群組建立帳號令牌，以驗證您的 CI 工作流程：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

這會建立一個具有典型 CI 作業 (快取、預覽、bundles、測試、建立和執行) 所需的所有權限的標記。在您的 CI
環境中，將產生的標記儲存為秘密，並設定為`TUIST_TOKEN` 環境變數。

### 管理帳戶代幣{#managing-account-tokens}

列出帳戶的所有代幣：

```bash
tuist account tokens list my-account
```

以名稱撤銷權限：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用帳戶代幣{#using-account-tokens}

帳號代碼預期會定義為環境變數`TUIST_TOKEN` ：

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
需要時使用帳戶代用幣：
- 在不支援 OIDC 的 CI 環境中進行驗證
- 對於令牌可執行的操作進行細粒度控制
- 可存取帳戶內多個專案的標記
- 自動過期的限時代用幣
<!-- -->
:::
