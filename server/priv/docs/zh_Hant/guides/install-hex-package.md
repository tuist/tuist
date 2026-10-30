---
{
  "title": "安裝 Hex 套件",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "了解如何在 Elixir 專案中安裝與設定 Tuist 的 Hex 套件。"
}
---
# 安裝 Hex 套件 {#install-the-hex-package}

Tuist 提供一個 [Hex](https://hex.pm/packages/tuist_ex) 套件 `tuist_ex`，可與你的 Elixir 專案整合，以啟用<.localized_link href="/guides/features/build-insights/elixir">建置洞察</.localized_link>與<.localized_link href="/guides/features/test-insights/elixir">測試洞察</.localized_link>等功能。本指南將帶領你完成安裝與設定步驟。

此套件需要 Elixir 1.18 或更新版本。它不需要 Tuist 命令列介面。

## 1. 建立專案 {#create-the-project}

在 Tuist 儀表板中建立專案，並選擇 **Mix (Elixir)** 作為其建置系統。其代號 `account/project` 是用來將你的 Mix 專案與之連結的識別碼。

## 2. 新增套件 {#add-the-package}

將 `tuist_ex` 加入 `mix.exs` 中的相依性：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

接著取得該套件：

```bash
mix deps.get
```

`runtime: false` 可讓 Tuist 不會出現在執行中的應用程式裡。請繼續參閱<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">開始使用 Elixir</.localized_link>，以同時設定快取、建置洞察與測試洞察。以下章節說明驗證與設定的詳細資訊。

## 3. 為團隊與持續整合進行驗證 {#authenticate}

每位團隊成員需執行以下指令，以便在其機器上使用 Tuist 功能：

```bash
mix tuist.login
```

這會開啟瀏覽器並等待你授權。若要在不使用瀏覽器的情況下登入，請傳入你的憑證：

```bash
mix tuist.login --email person@example.com --password secret
```

當你使用自架或本機 Tuist 伺服器時，請在 `mix.exs` 中設定其基礎 URL，或使用 `--url` 傳入：

```bash
mix tuist.login --url http://localhost:8080
```

請保持主機名稱拼寫一致。例如，為 `localhost` 儲存的登入資訊與為 `127.0.0.1` 儲存的登入資訊是分開的。

在 GitHub Actions、CircleCI 和 Bitrise 上，持續整合不需要登入步驟。當工作首次傳送報告時，它會將供應商的 OpenID Connect 權杖交換為 Tuist 權杖。請<.localized_link href="/guides/integrations/gitforge/github">將你的 GitHub 儲存庫</.localized_link>連結至你的 Tuist 專案，並在 GitHub Actions 中賦予該工作 `id-token: write` 權限：

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

對於其他任何 OpenID Connect 身分提供者（例如 Fly.io Machines），請在你帳戶的**工作負載身分**區段（位於**設定 → 驗證**頁面）中設定工作負載身分信任政策，這會授予 CI 存取該帳戶擁有之所有現有與未來專案的權限。將 `TUIST_OIDC_ACCOUNT` 設為擁有該專案的 Tuist 帳戶，並透過 `TUIST_OIDC_TOKEN` 提供具有該政策受眾的新頒發身分權杖。當沒有帳戶權杖或有效的已儲存登入資訊時，整合會自動交換該權杖；`mix tuist.login` 在非 CI 環境中也接受此權杖。自動交換僅會對相同的伺服器、帳戶與提供的身分權杖重複使用未過期的工作階段。變更該身分會觸發新的交換，而提供空白身分則會失敗，不會重複使用先前的工作階段。Tuist 工作階段在沒有重新整理權杖的情況下持續一小時，因此對於較長執行的工作負載，請在工作階段過期前頒發新的身分權杖並再次執行 `mix tuist.login`。請參閱<.localized_link href="/guides/server/authentication#workload-identity-trust-policies">工作負載身分設定</.localized_link>與<.localized_link href="/guides/server/authentication#flyio-machines">Fly.io 範例</.localized_link>。

來自分支複製的拉取請求不會取得 OpenID Connect 權杖，因此它們的執行不會被回報，仍會照常通過或失敗。在其他供應商上，請將 `TUIST_TOKEN` 環境變數設為帳戶權杖。請依照<.localized_link href="/guides/integrations/continuous-integration#authentication">持續整合驗證指南</.localized_link>建立權杖。

## 4. 繼續使用 `mix test` 與 `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">共用設定</.localized_link>會為你安裝編譯與測試別名。`mix test test/my_app_test.exs:12 --trace` 會以相同的輸出與結束碼回報執行結果，而編譯整合涵蓋由 `mix test` 或 `mix phx.server` 觸發的建置。若編譯發現無需執行任何事項，則不會回報。

這些任務在使用其自身名稱呼叫時也能運作。Mix 會在 `dev` 環境中以該方式啟動任務，因此該任務必須在第二個程序中重新啟動以用於測試環境。將任務加入偏好的環境以略過此步驟：

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 設定參考 {#configuration-reference}

下列選項可在 `mix.exs` 的專案選項中於 `tuist` 底下使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `project` | `String` | 無（必填） | 採用 `account/project` 格式的專案識別碼。 |
| `url` | `String` | `"https://tuist.dev"` | Tuist 伺服器的基礎 URL。 |
| `cache` | `boolean` 或關鍵字清單 | 停用 | 設定會啟用相依性快取。請參閱<.localized_link href="/guides/features/cache/elixir">Elixir 快取</.localized_link>以了解排除項目與額外輸入。 |
| `test_retries` | `integer` | `0` | 失敗測試的重試次數；請參閱<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">測試重試</.localized_link>。 |
| `tags` | `String` 清單 | `[]` | 附加至每次建置的標籤；請參閱<.localized_link href="/guides/features/build-insights/elixir#custom-metadata">自訂中繼資料</.localized_link>。 |
| `values` | 對應 | `%{}` | 附加至每次建置的鍵值資料。 |

環境變數的優先順序高於 `mix.exs`：

| 變數 | 說明 |
| --- | --- |
| `TUIST_PROJECT` | 採用 `account/project` 格式的專案識別碼。 |
| `TUIST_URL` | Tuist 伺服器的基礎 URL。 |
| `TUIST_TOKEN` | 用於驗證的權杖，以取代儲存的登入資訊。 |
| `TUIST_OIDC_TOKEN` | 新產生的 OpenID Connect 身分權杖，會交換為 Tuist 權杖。其受眾必須為 GitHub Actions 與 Bitrise 的 `tuist`，或符合其他供應商的專案信任政策。由 `mix tuist.login` 使用，或在沒有帳戶權杖或有效儲存登入資訊時作為備用。 |
| `TUIST_OIDC_ACCOUNT` | 擁有該專案的 Tuist 帳戶代號。在透過專案信任政策交換權杖時為必填。它會在現有的信任政策中進行選擇，本身並不會授予存取權限。 |
| `TUIST_TEST_RETRIES` | 失敗測試的重試次數。 |
| `TUIST_TAGS` | 以逗號分隔、要附加至建置的標籤。 |
| `TUIST_VALUES` | 以逗號分隔、要附加至建置的 `key=value` 配對。 |
| `TUIST_DEBUG` | 設為 `1` 以列印無法傳送報告的原因。 |

回報絕不會改變 `mix test` 或 `mix compile` 的結束碼。若無法傳送報告，除非設定了 `TUIST_DEBUG=1`，否則任務不會輸出任何訊息。

## 後續步驟 {#next-steps}

安裝並設定套件後，你可以使用：

- <.localized_link href="/guides/features/cache/elixir">相依性快取</.localized_link>，以便在本機與 CI 建置中重複使用已編譯的相依性。
- <.localized_link href="/guides/features/build-insights/elixir">建置洞察</.localized_link>，以追蹤編譯時間、警告，以及拖慢建置的因素。
- <.localized_link href="/guides/features/test-insights/elixir">測試洞察</.localized_link>，以追蹤每個測試的效能表現。
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">不穩定測試</.localized_link>，以偵測並追蹤間歇性失敗的測試。
- <.localized_link href="/guides/features/test-sharding/elixir">測試分片</.localized_link>，以便將測試分散到多個持續整合執行器上執行。
