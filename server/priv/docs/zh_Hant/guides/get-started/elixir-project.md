---
{
  "title": "Elixir project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Set up Tuist once for Elixir dependency caching, build and test insights, flaky test detection, and optional test sharding."
}
---
# Elixir 專案 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

只需設定一次 Tuist，然後繼續使用 `mix compile` 和 `mix test`。`tuist_ex` Hex 套件會快取支援的相依性，並將建構與測試執行回報至您的儀表板。

## 必要條件

- 一個使用 Mix 建置的 Elixir 專案，且 Elixir 版本為 1.18 或更新版本。
- 一個 Tuist 帳號。

## 設定 Tuist {#set-up-tuist}

在 Tuist 儀表板中建立專案，並選擇 **Mix (Elixir)** 作為其建置系統。將套件新增至您 `mix.exs` 中的相依性：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得套件、設定您的專案，並登入：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

設定程序會以您的專案代號更新 `mix.exs`、啟用相依性快取，並安裝編譯與測試的別名。它會保留其他設定以及標準的測試準備步驟（例如 Phoenix 的資料庫設定）。如果無法安全地整合自訂別名，它會停止且不變更檔案。

提交更新後的 `mix.exs`，讓您的團隊與 CI 使用相同的設定。無需複製任何指令碼或評估程式碼。登入會開啟瀏覽器；如需無頭登入與 CI 憑證，請參閱 <.localized_link href="/guides/install-hex-package#authenticate">authentication</.localized_link>。

現在執行您慣用的指令：

```bash
mix compile
mix test
```

建構會顯示在 **Builds** 下方，測試執行會顯示在 **Tests** 下方，而相依性快取活動則顯示在 **Mix cache** 下方。這是三者共用的設定。不穩定測試偵測會使用回報的執行記錄；重試與 CI 分片則是選用功能。

## 相依性快取

Tuist 會自動選取支援的 Hex 與 Git 相依性，無需維護相依性清單。快取未命中時會正常編譯並儲存結果；命中時則還原結果。原生/自訂編譯與本機相依性仍由 Mix 處理。

編譯必須可重現：宣告額外的編譯期輸入，並排除具有未建模輸入或必要副作用的相依性。請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> 以了解支援的輸入、快取驗證與自訂選項。

## 建構洞察

建構時間、檔案之間的相依圖，以及兩者隨時間的變化，能讓您獲得優化建構圖所需資訊，並充分利用編譯環境中的所有核心。

啟用 `compile` 別名後，Tuist 會回報每次建構：耗時、警告與錯誤、每個檔案的編譯時間，以及其依賴的檔案。在下一次 `mix compile` 之後，於儀表板上開啟 **Builds** 即可查看。

## 測試洞察

Tuist 會記錄每次 `mix test` 執行中每個測試的結果與持續時間，讓您可以觀察測試套件隨時間的變化、找出緩慢或變慢的測試，並了解 CI 中執行失敗的原因。您可以在儀表板的 **Tests** 下方找到這些資訊，細分到模組、`describe` 區塊與個別測試。

## 不穩定測試

不穩定測試在使用相同程式碼時有時通過、有時失敗。當某個測試在 CI 的同一個提交中既失敗又通過時，Tuist 會將其標記為不穩定。您也可以讓套件重試失敗的測試，以便在單次執行中偵測到它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

若測試在重試時通過，會被回報為不穩定，且該次執行視為成功。**Flaky Tests** 頁面會列出這些測試。

## 測試分片

測試分片會將您的測試套件分散到多個 CI 執行器上。Tuist 會根據先前執行中每個測試檔案的耗時來平衡分片，並且只編譯專案一次，再與所有執行器共用該建構。使用單一指令即可規劃分片：

```bash
mix tuist.test.build --shard-max 4
```

每個執行器接著會在設定 `TUIST_SHARD_INDEX` 的情況下執行其分配的部分，結果會以單一測試執行的形式出現在儀表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 邀請團隊成員加入

洞察價值會隨著連接至專案的人數增加而累積。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `mix tuist.login`。

對於 CI，請勿使用個人登入。GitHub Actions、CircleCI 與 Bitrise 可以透過 OpenID Connect 進行驗證；在其他提供者上，請設定具範圍限制的 `TUIST_TOKEN`。請遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI authentication steps</.localized_link>。
