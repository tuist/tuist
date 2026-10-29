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

只需設定一次 Tuist，然後繼續使用 `mix compile` 和 `mix test`。`tuist_ex` Hex 套件會快取支援的依賴項，並將建置和測試執行報告傳送至你的儀表板。

## 先決條件

- 一個使用 Mix 建置的 Elixir 專案，基於 Elixir 1.18 或更高版本。
- 一個 Tuist 帳戶。

## 設定 Tuist {#set-up-tuist}

在 Tuist 儀表板中建立專案，並選擇 **Mix (Elixir)** 作為其建置系統。將套件加入你的 `mix.exs` 中的依賴項：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得它、設定你的專案，然後登入：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

設定會更新 `mix.exs` 以包含你的專案代號，啟用依賴項快取，並安裝編譯和測試別名。它會保留其他設定和標準測試準備（例如 Phoenix 的資料庫設定）。如果無法安全地整合自訂別名，它會在未更改檔案的情況下停止。

提交更新後的 `mix.exs`，以便你的團隊和 CI 使用相同的設定。無需複製任何腳本或評估程式碼。登入會開啟瀏覽器；請參閱 <.localized_link href="/guides/install-hex-package#authenticate">驗證</.localized_link> 以了解無頭登入和 CI 憑證。

現在執行你常用的指令：

```bash
mix compile
mix test
```

建置會顯示在 **Builds** 下，測試執行會顯示在 **Tests** 下，依賴項快取活動會顯示在 **Mix cache** 下。這是三者共用的設定。不穩定測試偵測會使用報告的執行結果；重試和 CI 分片是可選的。

## 依賴項快取

Tuist 會自動選擇支援的 Hex 和 Git 依賴項，無需依賴項清單。快取未命中時會正常編譯並儲存結果；命中時則還原結果。原生/自訂編譯和本機依賴項仍由 Mix 處理。

編譯必須可重複：宣告額外的編譯時間輸入，並排除具有未建模輸入或必要副作用的依賴項。請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir 快取</.localized_link> 以了解支援的輸入、快取驗證和自訂選項。

## 建置洞察

建置時間、檔案之間的依賴圖，以及兩者隨時間的演變，為你提供優化建置圖並充分利用編譯環境中所有核心所需的資訊。

有了 `compile` 別名後，Tuist 會報告每次建置：耗時多久、警告和錯誤、每個檔案的編譯時間，以及它所依賴的檔案。在下一次 `mix compile` 之後，開啟儀表板上的 **Builds** 即可查看。

## 測試洞察

Tuist 會記錄每次 `mix test` 執行中每個測試的結果和持續時間，讓你可以查看測試套件隨時間的演變、找出緩慢或變慢的測試，並了解為何在 CI 中執行失敗。你可以在儀表板的 **Tests** 下找到它們，細分到模組、`describe` 區塊和測試。

## 不穩定測試

不穩定測試在使用相同程式碼時有時通過有時失敗。當測試在 CI 的同一個提交中既失敗又通過時，Tuist 會將其標記為不穩定。你也可以讓套件重試失敗的測試，這可以在單次執行中偵測到它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

在重試中通過的測試會被報告為不穩定，且執行成功。**Flaky Tests** 頁面會列出它們。

## 測試分片

測試分片會將你的測試套件分散到多個 CI 執行器上。Tuist 會根據先前執行中每個測試檔案的耗時來平衡分片，並且只會編譯專案一次，然後與每個執行器共用該建置。一個指令即可規劃分片：

```bash
mix tuist.test.build --shard-max 4
```

每個執行器隨後會在設定 `TUIST_SHARD_INDEX` 的情況下執行其分片，結果會作為單一測試執行出現在儀表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 邀請團隊成員加入

洞察會隨著連接到專案的人數增加而累積。從儀表板的帳戶設定中邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），這樣入職只需點擊一下，而不需要每人執行 `mix tuist.login`。

對於 CI，請勿使用個人登入。GitHub Actions、CircleCI 和 Bitrise 可以透過 OpenID Connect 進行驗證；在其他提供者上，請設定具範圍限制的 `TUIST_TOKEN`。請遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI 驗證步驟</.localized_link>。
