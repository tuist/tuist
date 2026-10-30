---
{
  "title": "Elixir 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "為 Elixir 設定一次 Tuist，即可享有相依性快取、建置與測試洞察、不穩定測試偵測，以及選擇性的測試分片功能。"
}
---
# Elixir 專案 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

只需設定一次 Tuist，之後繼續使用 `mix compile` 與 `mix test`。`tuist_ex` Hex 套件會快取支援的相依性，並將建置與測試執行回報至你的儀表板。

## 前置需求

- 一個以 Mix 建構的 Elixir 專案，且使用 Elixir 1.18 或更新版本。
- 一個 Tuist 帳號。

## 設定 Tuist {#set-up-tuist}

在 Tuist 儀表板中建立專案，並選擇 **Mix (Elixir)** 作為其建置系統。將套件加入你的 `mix.exs` 中的相依性：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得套件、設定專案，並登入：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

設定程序會以你的專案代號更新 `mix.exs`，啟用相依性快取，並安裝編譯與測試的別名。它會保留其他設定以及標準的測試準備步驟（例如 Phoenix 的資料庫設定）。若無法安全整合自訂別名，則會停止且不變更檔案。

提交更新後的 `mix.exs`，讓團隊與 CI 使用相同的設定。無需複製任何腳本或評估程式碼。登入會開啟瀏覽器；如需無頭登入與 CI 憑證，請參閱 <.localized_link href="/guides/install-hex-package#authenticate">驗證</.localized_link>。

現在執行你慣用的指令：

```bash
mix compile
mix test
```

建置會出現在 **Builds** 底下，測試執行會出現在 **Tests** 底下，而相依性快取活動會出現在 **Mix cache** 底下。這是三者共用的設定。不穩定測試偵測會使用已回報的執行記錄；重試與 CI 分片為可選項目。

## 相依性快取

Tuist 會自動挑選支援的 Hex 與 Git 相依性，無需維護相依性清單。快取未命中時會正常編譯並儲存結果；快取命中時則還原結果。原生/自訂編譯與本機相依性仍由 Mix 處理。

編譯必須可重現：宣告額外的編譯期輸入，並排除具有未建模輸入或必要副作用的相依性。請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir 快取</.localized_link> 以了解支援的輸入、快取驗證與自訂選項。

## 建置洞察

建置時間、檔案之間的相依圖，以及兩者隨時間的變化，能讓你最佳化建置圖，並充分利用編譯環境中可用的所有核心。

在 `compile` 別名就位後，Tuist 會回報每次建置：耗時、警告與錯誤、每個檔案的編譯時間，以及其相依的檔案。在下一次 `mix compile` 之後，於儀表板開啟 **Builds** 即可查看。

## 測試洞察

Tuist 會記錄每次 `mix test` 執行中每個測試的結果與耗時，讓你能觀察測試套件隨時間的變化、找出緩慢或變慢的測試，並了解 CI 中執行失敗的原因。你可以在儀表板的 **Tests** 中找到這些資訊，細分到模組、`describe` 區塊與個別測試。

## 不穩定測試

不穩定測試會在相同程式碼下有時通過、有時失敗。當某個測試在 CI 的同一個 commit 上既失敗又通過時，Tuist 會將其標記為不穩定。你也可以讓套件重試失敗的測試，以便在一次執行中偵測它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

若在重試中通過，該測試會被回報為不穩定，且該次執行視為成功。**Flaky Tests** 頁面會列出這些測試。

## 測試分片

測試分片會將你的測試套件分散到多個 CI 執行器上。Tuist 會依據先前執行中每個測試檔案的耗時來平衡分片，並且只編譯專案一次，再與所有執行器共用該建置。一條指令即可規劃分片：

```bash
mix tuist.test.build --shard-max 4
```

每個執行器會在設定 `TUIST_SHARD_INDEX` 的情況下執行其分片，結果會以單一測試執行的形式呈現在儀表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 邀請團隊成員

洞察價值會隨著連線至專案的人數增加而累積。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `mix tuist.login`。

CI 請勿使用個人登入。GitHub Actions、CircleCI 與 Bitrise 可透過 OpenID Connect 進行驗證；在其他提供者上，請設定具範圍限制的 `TUIST_TOKEN`。請遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI 驗證步驟</.localized_link>。
