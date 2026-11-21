---
{
  "title": "Elixir 專案",
  "titleTemplate": ":title · 入門指南 · 教學 · Tuist",
  "description": "為 Elixir 設定一次 Tuist，即可享受依賴快取、構建與測試洞察、不穩定測試偵測，以及可選的測試分片功能。"
}
---
# Elixir 專案 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

設定一次 Tuist，然後繼續使用 `mix compile` 同 `mix test`。`tuist_ex` Hex 套件會快取支援嘅依賴項，並將編譯同測試執行回報到你嘅儀表板。

## 前置條件

- 一個用 Mix 建構嘅 Elixir 專案，運行喺 Elixir 1.18 或更高版本。
- 一個 Tuist 帳戶。

## 設定 Tuist {#set-up-tuist}

喺 Tuist 儀表板建立專案，並選擇 **Mix (Elixir)** 作為其建構系統。將套件加入你 `mix.exs` 入面嘅依賴項：

<!-- @snippet: ../_tuist-ex-dependency -->

獲取它、設定你嘅專案，然後登入：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

設定程序會用你嘅專案句柄更新 `mix.exs`，啟用依賴項快取，並安裝編譯同測試別名。佢會保留其他設定同標準測試準備（例如 Phoenix 嘅資料庫設定）。如果無法安全整合自訂別名，佢會停止而唔會更改檔案。

提交更新後嘅 `mix.exs`，令你嘅團隊同 CI 使用相同設定。無需複製腳本或評估代碼。登入會開啟瀏覽器；有關無頭登入同 CI 憑證，請參閱 <.localized_link href="/guides/install-hex-package#authenticate">驗證</.localized_link>。

而家運行你慣常嘅指令：

```bash
mix compile
mix test
```

編譯會顯示喺 **Builds** 之下，測試執行顯示喺 **Tests** 之下，依賴項快取活動顯示喺 **Mix cache** 之下。呢個係三者共用嘅設定。不穩定測試偵測使用已回報嘅執行；重試同 CI 分片係可選。

## 依賴項快取

Tuist 會自動選擇支援嘅 Hex 同 Git 依賴項，無需依賴項清單。快取未命中會正常編譯並儲存結果；命中則會還原它。原生/自訂編譯同本地依賴項仍由 Mix 處理。

編譯必須可重現：聲明額外嘅編譯時輸入，並排除具有未建模輸入或_required_副作用嘅依賴項。有關支援嘅輸入、快取驗證同自訂，請參閱 <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link>。

## 編譯洞察

編譯時間、你檔案之間嘅依賴圖，以及兩者隨時間嘅演變，提供你優化編譯圖所需嘅資訊，並充分利用進行編譯環境中可用嘅所有核心。

有咗 `compile` 別名後，Tuist 會回報每次編譯：所需時間、警告同錯誤、每個檔案嘅編譯時間，以及它所依賴嘅檔案。喺下次 `mix compile` 之後，喺儀表板打開 **Builds** 即可查看。

## 測試洞察

Tuist 會記錄每次 `mix test` 執行中每個測試嘅結果同持續時間，令你可以查看測試套件隨時間嘅演變、找出緩慢或變慢嘅測試，並了解為何某次執行喺 CI 中失敗。你會喺儀表板嘅 **Tests** 之下找到它們，詳細到模組、`describe` 區塊同測試。

## 不穩定測試

不穩定測試會喺相同代碼下有時通過有時失敗。當測試喺 CI 中同一個 commit 上既失敗又通過時，Tuist 會將其標記為不穩定。你亦可以令套件重試失敗嘅測試，從而喺單次執行中偵測到它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

喺重試中通過嘅測試會被報告為不穩定，且該次執行視為成功。**Flaky Tests** 頁面會列出它們。

## 測試分片

測試分片將你嘅測試套件分佈到多個 CI runner。Tuist 根據之前執行中每個測試檔案嘅耗時來平衡分片，並且只編譯專案一次，然後同每個 runner 共享該編譯結果。一條指令即可規劃分片：

```bash
mix tuist.test.build --shard-max 4
```

每個 runner 隨後喺設定咗 `TUIST_SHARD_INDEX` 嘅情況下運行其分片，結果會作為單次測試執行顯示喺儀表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 邀請團隊加入

洞察數據會隨連接至專案嘅人數增加而累積。從儀表板嘅帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），令入職只需點擊一下，而無需每人執行 `mix tuist.login`。

對於 CI，請勿使用個人登入。GitHub Actions、CircleCI 同 Bitrise 可以透過 OpenID Connect 進行驗證；喺其他供應商上，設定一個具範圍限制嘅 `TUIST_TOKEN`。請遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI 驗證步驟</.localized_link>。
