---
title: Elixir 快取
titleTemplate: ":title · 快取 · 指南 · Tuist"
description: 為你的 Elixir 專案啟用依賴快取，並繼續使用 Mix。
---

# Elixir 快取

Tuist 會在本地及 CI 建構中重複使用已編譯的依賴項。只需啟用一次，然後繼續使用 `mix compile` 和 `mix test`。

## 設定

請先按照<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">開始使用 Elixir</.localized_link>進行設定。此共用設定可同時啟用依賴項快取以及建構與測試洞察；無需額外設定快取。

`cache: true` 會自動選擇支援的 Hex 和 Git 依賴項；你無需將它們列出。原生／自訂編譯和本地依賴項仍會透過 Mix 正常進行。你的應用程式原始碼檔案不會被快取。

## 如常建構

```sh
mix compile
mix test
```

當某個依賴項需要編譯時，Tuist 會先檢查本地快取，再檢查共用的遠端快取。若未命中（miss），則會正常編譯並將結果儲存以供日後建構使用。對於 Mix 認為已是最新版本的受支援依賴項，只要其編譯輸出存在且有效，即計為本地命中（hit）；無需查詢快取。如果驗證或快取服務不可用，Mix 仍會正常編譯。

## 查看你的快取命中情況

在專案儀表板中開啟**Mix Cache**，以查看命中率、傳輸量和近期的建構記錄。選擇某個建構的**Mix cache**分頁，即可查看哪些任務命中或未命中。**CAS Outputs** 顯示實際的遠端下載和上傳；本地命中不會產生遠端傳輸記錄。重複使用已經最新的輸出有助於提高命中率，但不會產生傳輸位元組、還原延遲或估計節省的時間。

若要測試還原，請清除某個受支援依賴項的編譯輸出並重新建構：

```sh
mix deps.clean nimble_options --build
mix compile
```

將`nimble_options`替換為你的專案所用且已填充快取的依賴項。保持相同的 Mix 環境和編譯器設定。

## 僅在需要時自訂

大多數專案可以保留`cache: true`。如有例外情況，請使用關鍵字列表：

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **額外的編譯時輸入：** 使用`inputs: ["schemas"]`宣告外部檔案，並使用`env: ["COMPILER_OPTION"]`宣告環境變數。
- **僅限本地：** 設定`remote: false`。
- **不上傳至遠端：** 設定`upload: false`。伺服器權限仍然控制存取權。
- **停用快取：** 設定`cache: false`。

> [!IMPORTANT]
> 編譯過程可以執行任意的 Elixir 程式碼。請宣告額外的輸入，並排除那些含有時間／網路依賴程式碼或副作用、必須在每次建構時執行的依賴項。快取構件可能包含機密資料，而快取寫入者是受信任的程式碼產生者：切勿授予不受信任的工作快取寫入憑證。

如需了解依賴項選擇、在不同檢出路徑間的重複使用、疑難排解和實作細節，請參閱<.localized_link href="/guides/features/cache/elixir-advanced">進階 Elixir 快取設定</.localized_link>。
