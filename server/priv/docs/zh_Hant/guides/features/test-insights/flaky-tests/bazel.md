---
{
  "title": "Bazel 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測 Bazel 不穩定測試、將其失敗設為靜音，並跳過已隔離的目標。"
}
---

# Bazel 不穩定測試 {#bazel-flaky-tests}

`tuist bazel test` 會在每次呼叫前取得 Tuist 的隔離政策，並將其套用到基礎的 `bazel test` 執行。

## 套用隔離 {#applying-quarantine}

在測試頁面中，將其狀態變更為 **已靜音**，然後執行：

```sh
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發給 `bazel test`。使用 `--path` 來選擇專案與工作目錄，並使用 `--bazel` 來選擇不同的可執行檔，例如 `bazelisk`。一般的 `bazel test` 仍會回報測試結果，但不會取得或強制執行 Tuist 隔離政策。

隔離不需要具名的 Bazel 設定或重試。**不穩定測試**、**已隔離測試**以及個別測試頁面支援與其他建置系統相同的手動狀態變更。使用 **設定 → 自動化** 來設定不穩定閾值、隔離動作與復原動作。

### 靜音 {#mute}

將 **靜音** 作為主要的隔離工作流程。已靜音的案例會繼續執行，其失敗仍可見，且健康的同層案例仍會影響結果。新的執行提供復原證據，同時不會從目標中排除任何案例。

Tuist 會讀取暫存的本地建置事件檔案與參照的 `test.xml` 報告。只有當完整報告將每個失敗目標中的所有回報失敗歸因於已靜音案例時，它才會將 Bazel 的測試失敗退出碼改為成功。

建置錯誤、逾時、中斷的執行、遺失或格式錯誤的報告、不完整的事件串流，以及不在靜音集合內的失敗，都會保留 Bazel 的失敗狀態。本地事件檔案上限為 64 MiB，個別報告上限為 5 MiB。Tuist 需要自己的本地建置事件檔案來驗證靜音失敗並從過時的已跳過目標中復原，因此明確的 `--build_event_json_file` 不能與作用中的靜音或已跳過案例同時使用。遠端建置事件回報仍透過 `tuist bazel setup` 進行設定。

原始的 Bazel 呼叫與報告會保留其實際結果。Tuist 伺服器會記錄案例在呼叫開始時是否已被隔離，即使其狀態在報告處理前發生變更亦然。

### 跳過 {#skip}

僅在你打算排除 **整個 Bazel 目標**（包括該目標內的健康案例）時才使用 **跳過**。將單一案例標記為 **已跳過** 會產生此目標範圍的影響。Bazel 的個別案例過濾語法取決於測試框架，並非普遍支援。因此，Tuist 使用啟用了測試套件展開的原生負向目標模式。明確目標、萬用字元選擇，以及 `test_suite` 規則內的測試會保留 Bazel 的正常選擇行為。

指令會取得每個隔離頁面並對目標去重。如果 Bazel 的完整事件日誌在目標設定或執行前識別出遺漏的已跳過目標，Tuist 會在警告中指出該目標，並在不含該過時排除的情況下重試。原始請求的模式與所有其他排除都會保留。復原限制為五次重試；其他載入失敗與證據不完整的情況會保留 Bazel 的錯誤。將過時案例恢復為 **已啟用** 以永久移除其政策。直接傳遞目標模式；`--target_pattern_file` 不能與隔離排除同時使用。若沒有剩餘的測試目標，Bazel 會保留其正常的「找不到測試」退出狀態，這也能捕捉意外產生的空測試選擇。

指令會列印每個被排除的目標標籤，讓建置日誌顯示隔離政策排除了哪些目標（包括其健康案例）。

### 再次執行已隔離的測試 {#running-quarantined-tests-again}

若要調查或驗證修復，請略過兩項隔離政策：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

將案例恢復為 **已啟用**，以便在後續的正常執行中包含其目標。已跳過的案例在明確包含之前不會產生新的執行，因此基於成功新執行的自動化需要在能夠復原它們之前先進行驗證執行。

隔離擷取錯誤會在執行測試前停止指令。指令也會拒絕超過 20,000 個案例的政策或超過其大小上限的目標引數；它絕不會套用部分政策。當你刻意想在無政策的情況下執行時，請使用 `--no-quarantine`。

## 選用設定與重試 {#optional-configuration-and-retries}

如果你的儲存庫在 `.bazelrc` 中定義了名為 `ci` 的設定，你可以使用 `--config=ci` 來選取它：

```sh
tuist bazel test -- --config=ci //app:tests
```

這是儲存庫定義的設定，並非 Tuist 的必要條件。當你的儲存庫未定義此設定時，請省略該選項。

重試也是選用的，且與隔離無關。`--flaky_test_attempts=3` 會為每個測試啟用最多 **三次 Bazel 嘗試總計**，而非額外三次重試。團隊可以將現有的重試設定保留在 `.bazelrc` 中，或明確傳遞：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

對於定義了 `ci` 的儲存庫，可以合併這些選項：

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## 偵測不穩定性 {#detecting-flakiness}

Tuist 使用 Bazel `test.xml` 報告中的個別案例，來偵測在持續整合中跨重試以及跨相同提交與目標選擇的執行之間的不一致結果。本地執行仍可見，但不會自動將測試案例標記為不穩定。當你的建置環境尚未發布提交與分支中繼資料時，請提供這些資訊：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

必須實際執行重試，Tuist 才能觀察其結果。僅憑 Bazel 目標的不穩定摘要無法識別哪個個別案例不穩定。無法取得或無法剖析的報告無法提供案例層級的證據。

案例由目標標籤、類別名稱（若無則退回使用套件名稱）與測試名稱來識別。這能讓不同類別中同名方法保持分離。使用不同外層套件名稱的舊報告會在舊身分下保留其歷史記錄；其隔離狀態必須套用到新身分。當失敗符合舊的套件基礎靜音而非目前的類別身分時，指令會警告需要重新套用哪項政策，並讓該失敗繼續阻擋。政策不會自動轉移，因為多個類別可能曾共用舊身分。

請參閱 Bazel 的 [測試過濾器](https://bazel.build/docs/user-manual#test-filter)、[指令選項](https://bazel.build/reference/command-line-reference) 與 [建置事件說明](https://bazel.build/remote/bep-glossary)，以了解底層行為。
