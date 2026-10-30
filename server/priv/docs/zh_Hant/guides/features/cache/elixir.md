---
title: Elixir 快取
titleTemplate: ":title · 快取 · 指南 · Tuist"
description: 為你的 Elixir 專案啟用相依性快取，並繼續使用 Mix。
---

# Elixir 快取

Tuist 會在本地與 CI 建置之間重複使用已編譯的相依套件。只需啟用一次，即可繼續使用 `mix compile` 和 `mix test`。

## 設定

請先參閱 <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">開始使用 Elixir</.localized_link>。此共用設定可同時啟用相依性快取以及建置與測試洞察；無需額外設定快取。

`cache: true` 會自動選擇支援的 Hex 與 Git 相依套件；你無須逐一列出。原生／自訂編譯與本機相依套件仍會透過 Mix 正常執行。應用程式的原始碼檔案不會被快取。

## 照常建置

```sh
mix compile
mix test
```

當相依套件需要編譯時，Tuist 會先檢查本機快取，再檢查共用的遠端快取。若未命中，則以正常方式編譯並儲存結果供後續建置使用。Mix 認為已是最新的受支援相依套件，在其編譯產出存在且有效時會被計為本機命中；此時不需查詢快取。若驗證或快取服務不可用，Mix 仍會正常編譯。

## 查看你的快取命中情況

在專案儀表板中開啟 **Mix Cache**，即可查看命中率、傳輸量與最近的建置紀錄。選取某次建置的 **Mix cache** 分頁，查看哪些任務命中或未命中。**CAS Outputs** 顯示實際的遠端下載與上傳；本機命中不會產生遠端傳輸記錄。重複使用已為最新的產出會計入命中率，但不會產生傳輸位元組、還原延遲或預估節省時間。

若要嘗試還原，請清除某個受支援相依套件的編譯產出後再次建置：

```sh
mix deps.clean nimble_options --build
mix compile
```

將 `nimble_options` 替換為你的專案中使用且已填入快取的相依套件。保持相同的 Mix 環境與編譯器設定。

## 僅在需要時自訂

多數專案可保留 `cache: true`。若有例外情況，請使用關鍵字列表：

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **額外的編譯期輸入：** 使用 `inputs: ["schemas"]` 宣告外部檔案，並使用 `env: ["COMPILER_OPTION"]` 宣告環境變數。
- **僅限本機：** 設定 `remote: false`。
- **不上傳至遠端：** 設定 `upload: false`。伺服器權限仍會控制存取。
- **停用快取：** 設定 `cache: false`。

> [!IMPORTANT]
> 編譯過程可能執行任意的 Elixir 程式碼。請宣告額外輸入，並排除那些依賴時間／網路或具有副作用、必須在每次建置時執行的相依套件。快取產物可能包含機密資訊，而快取寫入者是被信任的程式碼產生者：請勿將快取寫入憑證提供給不受信任的工作。

如需了解相依套件選擇、在不同檢出路徑間的重複使用、疑難排解與實作細節，請參閱 <.localized_link href="/guides/features/cache/elixir-advanced">進階 Elixir 快取設定</.localized_link>。
