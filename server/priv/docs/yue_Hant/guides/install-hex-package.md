---
{
  "title": "安裝 Hex 套件",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "學習如何喺你嘅 Elixir 專案入面安裝同設定 Tuist 嘅 Hex 套件。"
}
---
# 安裝 Hex 套件 {#install-the-hex-package}

Tuist 提供一個 [Hex](https://hex.pm/packages/tuist_ex) 套件 `tuist_ex`，可整合至你的 Elixir 專案以啟用如 <.localized_link href="/guides/features/build-insights/elixir">建構洞察</.localized_link> 及 <.localized_link href="/guides/features/test-insights/elixir">測試洞察</.localized_link> 等功能。本指南將帶你逐步完成安裝與設定。

此套件需要 Elixir 1.18 或更新版本。它不需要 Tuist 命令列介面。

## 1. 建立專案 {#create-the-project}

在 Tuist 儀表板中建立專案，並選擇 **Mix (Elixir)** 作為其建構系統。其代號 `account/project` 是用來將你的 Mix 專案與其連結。

## 2. 新增套件 {#add-the-package}

將 `tuist_ex` 加入你的 `mix.exs` 中的相依項目：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

然後取得它：

```bash
mix deps.get
```

`runtime: false` 讓 Tuist 不會進入你執行中的應用程式。請繼續參考 <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">開始使用 Elixir</.localized_link> 以同時設定快取、建構洞察和測試洞察。以下章節涵蓋驗證與設定的詳細資訊。

## 3. 為你的團隊與持續整合進行驗證 {#authenticate}

每位團隊成員需執行以下指令，以便在其機器上使用 Tuist 功能：

```bash
mix tuist.login
```

這會開啟瀏覽器並等待你授權。若要在沒有瀏覽器的情況下登入，請傳入你的憑證：

```bash
mix tuist.login --email person@example.com --password secret
```

當你使用自託管或本機 Tuist 伺服器時，請在 `mix.exs` 中設定其基礎 URL，或使用 `--url` 傳入：

```bash
mix tuist.login --url http://localhost:8080
```

保持主機名稱拼寫一致。例如，為 `localhost` 儲存的登入與為 `127.0.0.1` 儲存的登入是分開的。

在 GitHub Actions、CircleCI 和 Bitrise 上，持續整合不需要登入步驟。當任務首次發送報告時，它會將供應商的 OpenID Connect 權杖交換為 Tuist 權杖。請將 <.localized_link href="/guides/integrations/gitforge/github">你的 GitHub 儲存庫</.localized_link> 連結到你的 Tuist 專案，並在 GitHub Actions 中給予工作 `id-token: write` 權限：

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

對於任何其他 OpenID Connect 身分提供者（例如 Fly.io Machines），請在你帳戶的 **設定 → 驗證** 頁面的 **工作負載身分** 區段中設定工作負載身分信任政策，這將授予 CI 存取該帳戶擁有之所有目前及未來專案的權限。將 `TUIST_OIDC_ACCOUNT` 設定為擁有該專案的 Tuist 帳戶，並透過 `TUIST_OIDC_TOKEN` 提供具有政策受眾的新簽發身分權杖。當沒有帳戶權杖或有效的已儲存登入時，整合會自動交換它；`mix tuist.login` 在非 CI 環境下也接受它。自動交換僅會對相同的伺服器、帳戶和所提供的身分權杖重複使用未過期的工作階段。更改該身分會觸發新的交換，而空白的身分則會失敗而非重複使用先前的工作階段。Tuist 工作階段在沒有重新整理權杖的情況下持續一小時，因此對於較長時間執行的工作負載，請在工作階段過期前簽發新的身分權杖並再次執行 `mix tuist.login`。請參閱 <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">工作負載身分設定</.localized_link> 和 <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io 範例</.localized_link>。

來自分支的拉取請求不會獲得 OpenID Connect 權杖，因此它們的執行不會被報告，並仍會像往常一樣通過或失敗。在其他供應商上，將 `TUIST_TOKEN` 環境變數設定為帳戶權杖。請依照 <.localized_link href="/guides/integrations/continuous-integration#authentication">持續整合驗證指南</.localized_link> 建立一個。

## 4. 繼續使用 `mix test` 和 `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">共享設定</.localized_link> 會為你安裝編譯和測試別名。`mix test test/my_app_test.exs:12 --trace` 會以相同的輸出和退出碼報告執行，而編譯整合涵蓋由 `mix test` 或 `mix phx.server` 觸發的建構。如果編譯發現無需執行任何操作，則不會報告。

當你以其自身名稱呼叫任務時，這些任務也會運作。Mix 會在 `dev` 環境中以該方式啟動任務，因此任務必須在第二個程序中為測試環境重新開始。將任務加入到偏好環境中以跳過此步驟：

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 設定參考 {#configuration-reference}

以下選項可在 `mix.exs` 的專案選項中於 `tuist` 底下使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `project` | `String` | 無（必填） | 採用 `account/project` 格式的專案識別碼。 |
| `url` | `String` | `"https://tuist.dev"` | Tuist 伺服器的基礎 URL。 |
| `cache` | `boolean` 或關鍵字清單 | 已停用 | 設定會啟用相依性快取。請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir 快取</.localized_link> 以了解排除項目和額外輸入。 |
| `test_retries` | `integer` | `0` | 重試失敗測試的次數；請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link>。 |
| `tags` | `String` 清單 | `[]` | 附加到每個建構的標籤；請參閱 <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">自訂中繼資料</.localized_link>。 |
| `values` | 映射 | `%{}` | 附加到每個建構的鍵值資料。 |

環境變數優先於 `mix.exs`：

| 變數 | 說明 |
| --- | --- |
| `TUIST_PROJECT` | 採用 `account/project` 格式的專案識別碼。 |
| `TUIST_URL` | Tuist 伺服器的基礎 URL。 |
| `TUIST_TOKEN` | 用於驗證的權杖，以取代儲存的登入資訊。 |
| `TUIST_OIDC_TOKEN` | 新簽發的 OpenID Connect 身分權杖，會交換為 Tuist 權杖。其受眾對於 GitHub Actions 和 Bitrise 必須為 `tuist`，或符合其他供應商的專案信任政策。由 `mix tuist.login` 使用，或在沒有帳戶權杖或有效儲存登入時作為備用。 |
| `TUIST_OIDC_ACCOUNT` | 擁有該專案的 Tuist 帳戶代號。當透過專案信任政策交換權杖時為必填。它會在現有信任政策中進行選擇，本身並不會授予存取權限。 |
| `TUIST_TEST_RETRIES` | 重試失敗測試的次數。 |
| `TUIST_TAGS` | 以逗號分隔、要附加到建構的標籤。 |
| `TUIST_VALUES` | 以逗號分隔的 `key=value` 配對，要附加到建構。 |
| `TUIST_DEBUG` | 設定為 `1` 以列印無法傳送報告的原因。 |

報告永遠不會改變 `mix test` 或 `mix compile` 的退出碼。如果無法傳送報告，除非設定了 `TUIST_DEBUG=1`，否則任務不會顯示任何訊息。

## 下一步 {#next-steps}

安裝並設定套件後，你可以使用：

- <.localized_link href="/guides/features/cache/elixir">相依性快取</.localized_link>，以便在本機和 CI 建構中重複使用已編譯的相依性。
- <.localized_link href="/guides/features/build-insights/elixir">建構洞察</.localized_link>，以追蹤編譯時間、警告，以及拖慢建構的因素。
- <.localized_link href="/guides/features/test-insights/elixir">測試洞察</.localized_link>，以追蹤每個測試的效能表現。
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">不穩定測試</.localized_link>，以偵測和追蹤間歇性失敗的測試。
- <.localized_link href="/guides/features/test-sharding/elixir">測試分片</.localized_link>，以便將你的測試分散到持續整合執行器上。
