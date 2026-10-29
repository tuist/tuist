---
title: Elixir cache
titleTemplate: ":title · Cache · Guides · Tuist"
description: Enable dependency caching for your Elixir project and keep using Mix.
---

# Elixir 快取

Tuist 會在本機和 CI 建構中重複使用已編譯的相依套件。只需啟用一次，然後繼續使用 `mix compile` 和 `mix test`。

## 設定

請先按照 <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">開始使用 Elixir</.localized_link> 進行設定。此共用設定會同時啟用相依套件快取以及建構與測試洞察功能；無需額外的快取設定。

`cache: true` 會自動選取支援的 Hex 和 Git 相依套件；你不需要將它們列出。原生/自訂編譯和本機相依套件仍會透過 Mix 正常執行。你應用程式的原始程式檔不會被快取。

## 照常建構

```sh
mix compile
mix test
```

當相依套件需要編譯時，Tuist 會先檢查本機快取，再檢查共用的遠端快取。若未命中，則會正常編譯並將結果儲存以供未來的建構使用。Mix 認為已是最新版本的受支援相依套件，若其編譯輸出存在且有效，則計為本機命中；無需查詢快取。如果驗證或快取不可用，Mix 仍會正常編譯。

## 查看你的快取命中情況

在專案儀表板中開啟 **Mix Cache**，以查看命中率、傳輸量和最近的建構。選擇某個建構的 **Mix cache** 分頁，即可查看哪些任務命中或未命中。**CAS Outputs** 顯示實際的遠端下載和上傳；本機命中不會產生遠端傳輸記錄。重複使用已經最新的輸出有助於提高命中率，但不會產生傳輸位元組、還原延遲或預估節省的時間。

若要嘗試還原，請清除受支援相依套件的編譯輸出並再次建構：

```sh
mix deps.clean nimble_options --build
mix compile
```

將 `nimble_options` 替換為你專案中使用且已填入快取的相依套件。保持相同的 Mix 環境和編譯器設定。

## 僅在需要時自訂

大多數專案可以保留 `cache: true`。若有例外情況，請使用關鍵字清單：

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **額外的編譯時期輸入：** 使用 `inputs: ["schemas"]` 宣告外部檔案，並使用 `env: ["COMPILER_OPTION"]` 宣告環境變數。
- **僅限本機：** 設定 `remote: false`。
- **無遠端上傳：** 設定 `upload: false`。伺服器權限仍會控制存取。
- **停用快取：** 設定 `cache: false`。

> [!IMPORTANT]
> 編譯可以執行任意的 Elixir 程式碼。請宣告額外的輸入，並排除那些具有時間/網路相依程式碼或副作用、必須在每次建構時執行的相依套件。快取構件可能包含機密資訊，而快取寫入者是受信任的程式碼產生者：請勿給予不受信任的工作快取寫入憑證。

如需了解相依套件選取、在不同檢出路徑間的重複使用、疑難排解和實作細節，請參閱 <.localized_link href="/guides/features/cache/elixir-advanced">進階 Elixir 快取設定</.localized_link>。
