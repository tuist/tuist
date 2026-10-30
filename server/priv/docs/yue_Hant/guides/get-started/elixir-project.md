---
{
  "title": "Elixir 專案",
  "titleTemplate": ":title · 入門指南 · 教學 · Tuist",
  "description": "為 Elixir 設定一次 Tuist，即可啟用依賴快取、建構與測試洞察、不穩定測試偵測，以及選用嘅測試分片功能。"
}
---
# Elixir 專案 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

設定一次 Tuist，之後繼續使用 `mix compile` 同 `mix test`。`tuist_ex` Hex 套件會快取支援嘅依賴項，並將建置同測試執行回報到你嘅儀表板。

## 前置條件

- 一個用 Mix 建構嘅 Elixir 專案，運行於 Elixir 1.18 或更高版本。
- 一個 Tuist 帳戶。

## 設定 Tuist {#set-up-tuist}

喺 Tuist 儀表板建立一個專案，並選擇 **Mix (Elixir)** 作為其建置系統。將套件加入你 `mix.exs` 中嘅依賴項：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

取得它、設定你嘅專案，然後登入：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

設定會更新 `mix.exs` 以包含你嘅專案標識符，啟用依賴項快取，並安裝編譯同測試別名。它會保留其他設定同標準測試準備（例如 Phoenix 嘅資料庫設定）。如果無法安全整合自訂別名，它會停止而不更改檔案。

提交更新後嘅 `mix.exs`，讓你嘅團隊同 CI 使用相同設定。無需複製腳本或評估代碼。登入會開啟瀏覽器；請參閱 <.localized_link href="/guides/install-hex-package#authenticate">驗證</.localized_link> 了解無頭登入同 CI 憑證。

而家執行你平常嘅指令：

```bash
mix compile
mix test
```

建置會顯示喺 **Builds** 下，測試執行會顯示喺 **Tests** 下，依賴項快取活動會顯示喺 **Mix cache** 下。呢個係三者共用嘅設定。不穩定測試偵測使用已回報嘅執行；重試同 CI 分片係可選項目。

## 依賴項快取

Tuist 會自動選擇支援嘅 Hex 同 Git 依賴項，無需依賴項清單。快取未命中時會正常編譯並儲存結果；命中時則還原結果。原生/自訂編譯同本地依賴項仍由 Mix 處理。

編譯必須可重現：聲明額外嘅編譯時輸入，並排除具有未建模輸入或必要副作用嘅依賴項。請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir 快取</.localized_link> 了解支援嘅輸入、快取驗證同自訂選項。

## 建置洞察

建置時間、檔案之間嘅依賴圖，以及兩者隨時間嘅變化，為你提供優化建置圖所需嘅資訊，並充分利用編譯環境中可用嘅所有核心。

有了 `compile` 別名後，Tuist 會報告每次建置：耗時、警告同錯誤、每個檔案嘅編譯時間，以及它所依賴嘅檔案。下次執行 `mix compile` 後，喺儀表板打開 **Builds** 即可查看。

## 測試洞察

Tuist 會記錄每次 `mix test` 執行中每個測試嘅結果同持續時間，讓你可以查看測試套件隨時間嘅變化、找出緩慢或變慢嘅測試，並了解 CI 中執行失敗嘅原因。你可以在儀表板嘅 **Tests** 下找到它們，細化到模組、`describe` 區塊同具體測試。

## 不穩定測試

不穩定測試喺相同代碼下有時通過有時失敗。當測試喺 CI 中同一個提交上既失敗又通過時，Tuist 會將其標記為不穩定。你也可以讓套件重試失敗嘅測試，從而喺單次執行中偵測到它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

重試後通過嘅測試會被報告為不穩定，且執行成功。**Flaky Tests** 頁面會列出它們。

## 測試分片

測試分片將你嘅測試套件分佈到多個 CI 執行器上。Tuist 根據早期執行中每個測試檔案嘅耗時來平衡分片，並編譯專案一次，然後與每個執行器共享該建置。一條指令即可規劃分片：

```bash
mix tuist.test.build --shard-max 4
```

每個執行器隨後喺設定 `TUIST_SHARD_INDEX` 嘅情況下運行其分片，結果會作為單次測試執行顯示喺儀表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 邀請團隊加入

洞察效果會隨著連接到專案嘅人數增加而累積。從儀表板嘅帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職只需點擊一下，而非每人執行一次 `mix tuist.login`。

對於 CI，請勿使用個人登入。GitHub Actions、CircleCI 同 Bitrise 可以通過 OpenID Connect 進行驗證；對於其他提供者，請設定具範圍限制嘅 `TUIST_TOKEN`。請遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI 驗證步驟</.localized_link>。
