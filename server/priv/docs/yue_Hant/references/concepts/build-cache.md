---
{
  "title": "乜嘢係 build cache？解構本地同遠端 build cache",
  "titleTemplate": ":title · Tuist",
  "description": "Build cache 會重用之前 build 嘅輸出。了解 Xcode、Gradle 同 Bazel 點樣運作本地同遠端 build cache、Xcode cache 係乜，以及幾時用 caching 先至划算。"
}
---
# 甚麼是構建快取？ {#what-is-a-build-cache}

構建快取會將各個構建步驟的輸出（例如編譯後的物件檔、模組、程式庫或測試結果）儲存起來，並以根據所有產生這些輸出的因素計算得出的金鑰作為索引：原始碼檔案、編譯器旗標、依賴項、環境變數及工具鏈版本。當後續構建需要某個步驟，而其輸入所產生的金鑰與之前相同時，構建系統便會直接採用已儲存的輸出，而非再次執行該步驟。**本機構建快取**存放在單一機器上，可加速該機器日後的構建。**遠端構建快取**則是一個共享伺服器，供多部機器讀寫，讓 CI 工作、團隊成員或編碼代理程式能夠重用他人已構建好的輸出。

## 構建快取、增量構建與 CI 目錄快取 {#build-cache-incremental-build-and-ci-cache}

有三種概念常被統稱為「快取」，但它们的運作方式各不相同：

- **增量構建**會重用已存在於你自身構建目錄中的輸出，並僅重新構建自上次構建以來發生變更的部分。它們通常依賴檔案時間戳記或隨構建產物保存的依賴圖。切換分支、移動檢出目錄，或在全新機器上開始作業，都會導致這些狀態遺失。
- **構建快取**會根據輸入的內容來查找輸出，而非依據同一目錄中最後構建的內容。這使得輸出能夠在不同分支、檢出目錄及機器之間重用，只要輸入相符即可。
- **CI 目錄快取**（例如 GitHub Actions 上的 `actions/cache`）會在作業結束時儲存一個目錄，並在下一個作業開始時將其還原，使用的金鑰由你自行選擇（例如鎖定檔案的雜湊值）。這屬於檔案傳輸，並非構建快取：構建系統仍會決定需要重新構建哪些部分，而還原的目錄可能部分或完全過時。

依賴項快取（例如已下載的套件，或 Gradle 或 Swift 套件快取）則屬另一類情況：它們節省的是網路擷取時間，而非編譯時間。

## 構建快取的運作原理 {#how-a-build-cache-works}

支援快取的構建系統會將構建過程拆分為多個步驟（Bazel 稱之為 actions，Gradle 稱之為 tasks），並對每個步驟執行相同的操作：

1. **計算快取金鑰。** 構建系統會對所有可能影響輸出的輸入進行雜湊處理：輸入檔案的內容、命令列或任務設定、相關環境變數，以及工具鏈。
2. **查找金鑰。** 系統會先檢查本機快取，若已設定，也會檢查遠端快取。
3. **命中或未命中。** 若命中，系統會下載或複製已儲存的輸出，並跳過該步驟。若未命中，系統會執行該步驟，並在允許的情況下，將輸出以上述金鑰上傳。

大多數快取會將輸出儲存在**內容定址儲存空間**（CAS）中，其中每個資料區塊都以其自身內容的雜湊值作為儲存索引，另外還有一個獨立的索引，將快取金鑰對應至其所產生的輸出。相同的檔案只會儲存一次，用戶端可以驗證其下載的內容。

此模型有一項嚴格要求：金鑰必須包含所有會改變輸出的輸入。如果某個步驟讀取了構建系統未知的輸入（例如未宣告的檔案、環境變數、當前時間或機器上安裝的工具），快取可能會返回與當前輸入不符的輸出。構建系統將僅依賴已宣告輸入的步驟稱為**密封式**步驟。相反的問題更為常見且危險性較低：若金鑰包含了無關資訊（例如絕對路徑或時間戳記），則在每部機器上產生的金鑰都會不同，導致快取永遠無法命中。

## 各構建系統的快取運作方式 {#how-it-works-per-build-system}

### Gradle 構建快取 {#gradle}

[Gradle 構建快取](https://docs.gradle.org/current/userguide/build_cache.html)會儲存可快取任務的輸出（例如 Java 和 Kotlin 編譯及測試執行），並以任務類型、實作方式、輸入屬性及標準化後的輸入檔案作為金鑰。此功能預設為關閉。你可以在 `gradle.properties` 中使用 `org.gradle.caching=true` 啟用，或在單次構建中使用 `--build-cache` 啟用。

- **本機。** 內建的本機快取是位於 Gradle 使用者主目錄中的一個目錄（預設為 `~/.gradle`）。一旦啟用構建快取，此功能便會生效，且 Gradle 會定期移除近期未使用的項目。
- **遠端。** 遠端快取在 `settings.gradle(.kts)` 中設定，例如使用 `HttpBuildCache`。當本機未命中時，Gradle 會從遠端快取下載輸出，並在本機儲存以供下次使用。遠端快取預設不接受上傳；常見的設定是讓 CI 負責推送（在 CI 中運行時設定 `isPush = true`），而開發者機器僅限讀取。

Gradle 會將從快取還原的任務標示為 `FROM-CACHE`，這與 `UP-TO-DATE` 不同：up-to-date 表示 Gradle 的增量構建發現任務的輸出已就緒，無須查詢快取。設定快取則是第三項獨立功能，它快取的是設定階段的結果，而非任務輸出。

### Bazel 遠端快取 {#bazel}

Bazel 會快取每個 action。其 action 快取將 action 的金鑰（由其命令列、環境及輸入檔案的摘要組成）對應至 action 的輸出，而輸出本身則儲存在內容定址儲存空間中。

- **本機。** Bazel 會在其輸出基礎目錄中保留 action 快取及構建輸出，從而讓你在單一工作區中獲得快速的增量構建。`--disk_cache=<path>` 會新增一個磁碟快取，供同一部機器上的不同工作區及分支共享。
- **遠端。**`--remote_cache=grpcs://…`（或 `https://…`）會將 Bazel 指向一個實作了 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 或純 HTTP 快取的遠端快取。`--remote_upload_local_results=false` 會將機器設為唯讀模式，許多團隊藉此防止開發者機器寫入共享快取。`--remote_download_minimal` 或 `--remote_download_toplevel`（「build without the bytes」）可避免下載本機構建永遠不需要的中間輸出。

Bazel 也會快取測試結果：若測試的輸入未發生變更，則會回報為 `(cached) PASSED` 而無需實際運行。遠端快取不同於遠端執行，後者的 action 也會在遠端機器上運行；快取僅儲存結果。

### Xcode 快取是甚麼？ {#xcode}

Xcode 使用了多種容易混淆的快取及目錄。影響構建時間的主要包括：

- **DerivedData**（`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`）儲存每個項目的構建產物、中間檔案、索引、日誌及已解析的 Swift 套件。這是增量構建所重用的狀態。刪除它是安全的，但該項目的下一次構建將會是完整重建，且索引與套件解析會再次執行。
- **Clang 模組快取**（`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`）儲存用於匯入 C 和 Objective-C 模組及 SDK 框架的預編譯 Clang 模組（`.pcm` 檔案），並在不同項目之間共享。若啟用明確構建模組，Xcode 會將模組作為常規構建任務進行構建，並將其與每個項目的中間檔案一起保存。刪除它是安全的；模組會按需重新構建。
- **編譯快取**（Xcode 26 及更高版本，預設位於 DerivedData 內的 `CompilationCache.noindex`，可透過 `COMPILATION_CACHE_CAS_PATH` 設定）在 `COMPILATION_CACHE_ENABLE_CACHING = YES` 時，儲存 Swift、C 和 Objective-C 的內容定址編譯輸出。刪除它是安全的；原本可以重放的編譯會再次執行。
- **Swift Package Manager 快取**（`~/Library/Caches/org.swift.swiftpm/`）儲存下載的套件儲存庫及清單，並在不同項目之間共享。刪除它是安全的；套件會再次抓取。

`~/Library/Developer` 下的其他大型目錄並非構建快取，但在清理磁碟空間時經常出現：`Xcode/Archives` 儲存歸檔的應用程式構建及其除錯符號（保留你可能需要用來符號化崩潰報告的符號），`Xcode/iOS DeviceSupport` 儲存已連接裝置作業系統版本的符號，而 `CoreSimulator/Devices` 則儲存模擬器及其資料（`xcrun simctl delete unavailable` 會移除已不再安裝的執行環境對應的模擬器）。

DerivedData 是 Xcode 的增量構建狀態，而非內容定址快取：它與項目在磁碟上的位置及檔案時間戳記綁定。從不同路徑的 CI 快取還原 DerivedData，或在全新檢出後因所有檔案的修改時間變更，通常仍會導致完整重建。

Xcode 26 引入的 **編譯快取**，正是本頁所指 Xcode 的構建快取。它根據輸入內容儲存編譯結果，並在命中時重放結果，因此輸出能在切換分支或清理構建產物後依然保留。它快取的是編譯，而非每個構建步驟：連結、資源處理及腳本階段仍會執行。預設情況下，儲存空間僅限於單一機器並位於 DerivedData 內，因此刪除整個 DerivedData 會將其清除；僅刪除項目的構建產物則會保留它。Xcode 亦可透過外掛程式將編譯快取連接至遠端快取服務（`COMPILATION_CACHE_ENABLE_PLUGIN` 及 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`），從而將其轉變為共享遠端快取。

在編譯快取出現之前，Xcode 項目主要透過 **二進制快取** 整個模組來跨機器重用工作：將依賴項構建為預建框架或 XCFrameworks，並連結這些檔案而非編譯原始碼。這是在模組層級而非編譯層級運作，並改變了項目的構建方式。

## 延遲、blob 大小及 blob 數量 {#latency-blob-size-and-blob-count}

遠端快取命中並非免費。獲取輸出需要為每個必須等待前一個請求完成的請求支付固定延遲，加上傳輸其位元組所需的時間：

**time ≈ R × L + S / B**

其中 *R* 是無法重疊的往返次數，*L* 是往返快取的延遲，*S* 是傳輸的位元組數，而 *B* 是頻寬。哪一項佔主導地位，取決於構建系統如何將工作切割成 blob：

- **少量大型 blob 受頻寬限制。** 儲存粗粒度輸出（例如 Gradle 任務的打包輸出或二進制模組快取中的預建框架）的快取，發出的請求較少，但每個請求傳輸數 MB。一組 200 MB 的輸出在 100 Mbit/s 下約需 16 秒，在 1 Gbit/s 下則不到 2 秒，而幾毫秒的額外延遲幾乎無關緊要。
- **大量小型 blob 受延遲限制。** 細粒度快取（例如 Bazel 的每 action 快取和 Xcode 的編譯快取）會發出數千個請求以獲取幾 KB 的 blob，其中許多請求僅用於查詢金鑰是否存在。若有 2,000 次查找，同時進行 8 次，延遲為 40 ms，則構建僅在往返上就需等待約 10 秒，無論 blob 多麼小。若延遲為 2 ms，同樣的查找則需約半秒。增加頻寬在此無助；使用更近的快取才有幫助。
- **未命中也會產生往返成本。** 每次未命中的查找都會增加延遲，卻無法節省任何工作。命中率低的遠端快取可能使構建比完全沒有遠端快取更慢。
- **數量會加倍影響兩者。** blob 的數量隨項目結構增長：由許多小型模組或目標組成的圖譜，會產生比少數大型模組更多、更小的輸出。拆分項目可提升平行處理能力及失效效率，但會使構建對快取延遲更為敏感。

只有當獲取輸出比重新計算更快時，命中才值得，而這種比較會隨距離變化。本地耗時 50 ms 的編譯，從同一網路的快取獲取是良好的命中，但從另一大陸的快取獲取則是糟糕的命中。這就是為何遠端快取的調整槓桿主要在於延遲和請求數量，而非原始頻寬：

- **將快取放置在靠近構建運行的位置**，與 CI 運行器處於同一區域或網路，並盡可能靠近開發者。
- **重疊請求。** Bazel 的 Remote Execution API 會批量處理存在性檢查（`FindMissingBlobs`）及小型讀取，而 `--remote_max_connections` 則限制併發數。Xcode 的 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會在構建的其餘部分同時執行編譯快取查找，而非佔用其執行通道。HTTP/2 可在單一連接上多工處理許多請求。
- **減少下載量。** Bazel 的 `--remote_download_minimal` 會跳過中間輸出，而本地快取層（例如 Bazel 的 `--disk_cache` 或 Gradle 的本機構建快取）可在無需網路請求的情況下服務重複命中。
- **壓縮大型 blob。** 當快取支援時，Bazel 的 `--remote_cache_compression` 會使用 zstd，這有助於受頻寬限制的傳輸，但對受延遲限制的傳輸幫助不大。

## 常見陷阱 {#common-pitfalls}

- **未宣告的輸入。** 某個步驟讀取了不屬於其鍵值的檔案、環境變數或工具。快取隨後可能傳回由不同輸入構建的輸出。在 Gradle 中，請宣告自訂任務的所有輸入；在 Bazel 中，請保持動作封閉，並考慮使用 `--incompatible_strict_action_env`，以免主機 `PATH` 洩漏進來。
- **機器專屬的鍵值。** 嵌入輸入或輸出中的絕對路徑、使用者名稱及構建時間戳記，會導致不同機器間的鍵值不同，使遠端快取永遠無法命中。Gradle 的路徑敏感性、Bazel 的相對執行路徑，以及 Xcode 中的 Clang 和 Swift 前綴映射設定，皆旨在消除這些差異。
- **靠近圖譜根節點的易變輸入。** 將構建編號、提交雜湊或日期印入所有模組依賴的模組中，會在每次構建時使該模組之上的所有內容失效。請盡可能延後注入易變值，理想情況下僅注入至發布構建。
- **工具鏈不相符。** 不同的編譯器、JDK 或 Xcode 版本會產生不同的鍵值。這是正確行為，但混合版本的機器群組實際上會分割快取。
- **受污染或不可信的寫入。** 擁有未提交變更或非封閉設定的開發者機器，可能會上傳讓其他人重複使用的輸出。許多團隊僅允許受信任分支上的 CI 寫入遠端快取，並將其他所有機器設為唯讀。不可信拉取請求的構建不應寫入受信任構建所讀取的快取。
- **忽略傳輸成本。** 耗時 50 毫秒執行的步驟，從遠端快取獲取可能需要更長時間。請參閱[延遲、blob 大小與 blob 數量](#latency-blob-size-and-blob-count)。
- **隱藏的測試執行。** 當測試具有確定性時，快取測試結果是正確的，但這也意味著曾通過一次的不穩定測試會持續顯示通過而無需執行。請參閱<.localized_link href="/references/concepts/flaky-test">什麼是不穩定測試？</.localized_link>。

## 如何衡量構建快取 {#how-to-measure-a-build-cache}

快取的價值在於端到端節省的時間，而非僅看命中率：

- **按工作量加權的命中率。** 統計每個步驟的命中與未命中次數，但需根據每個步驟的執行時間進行加權。在低成本步驟上達到 95% 的命中率，其節省效果可能低於在最慢編譯上達到 50% 的命中率。
- **冷啟動、暖啟動及典型構建。** 比較空快取時的構建、完全暖快取時的構建，以及人們實際運行的構建（例如小幅變更後拉取請求上的 CI）。最後一項才是關鍵數字。
- **花在快取本身的時間。** 測量請求數量、延遲、位元組數，以及下載和上傳所花費的時間。如果大部分時間都在等待許多小型請求，則較近的快取比增加頻寬更有幫助；如果是在移動少數大型 blob，則頻寬和壓縮更為重要。
- **未命中的原因。** 比較兩台機器上相同步驟的快取鍵值。Gradle 可使用 `-Dorg.gradle.caching.debug=true` 列印每個鍵值背後的輸入，Bazel 可寫入執行日誌（`--execution_log_compact_file`）以便在兩次構建間進行差異比較，而當 `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` 時，Xcode 會在構建日誌中報告編譯快取的命中與未命中情況。

## 何時不值得使用 {#when-it-isnt-worth-it}

構建快取會增加基礎設施、安全邊界及新一類的錯誤。它並非總是合適的工具：

- **小型或快速構建。** 如果乾淨構建只需一分鐘，遠端快取節省的效果有限，且網路往返可能使其更慢。
- **設計上就會未命中的構建。** 如果大多數構建都會變更靠近圖譜根節點的輸入，在修正此問題之前，快取無法提供幫助。請先修正失效機制；快取僅能跳過輸入相符的工作。
- **持久化的構建機器。** 在同一分支的不同作業間保留構建目錄的 CI 機器，已能獲得增量構建的好處。當機器是暫存的、存在許多分支，或開發者與 CI 應重複使用彼此的工作時，共享快取才有幫助。
- **尚無法修正的非封閉構建。** 偶爾傳回錯誤輸出的快取，所消耗的信任成本高於其節省的時間。請先確保您快取的步驟可重現，或讓有問題的步驟不被快取（例如使用 Bazel 的 `no-remote-cache` 標籤）。
- **緩慢或遙遠的網路。** 如果快取距離構建運行位置遙遠，請在向所有人推廣前先測量傳輸時間。

## 使用 Tuist 進行構建快取 {#build-caching-with-tuist}

[Tuist](https://tuist.dev) 提供一個遠端快取，可插入每個構建系統自身的快取機制，使開發者機器、CI 及編碼代理能夠重複使用彼此的輸出，並記錄命中、未命中及傳輸時間，以便您衡量效果：

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link>將 Xcode 的編譯快取連接至共享遠端快取，適用於 Xcode 26 或更高版本的任何 Xcode 項目。
- <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>在由 Tuist 生成的項目中，以預構建二進制檔取代整個模組。
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle 快取</.localized_link>與<.localized_link href="/guides/features/cache/bazel-cache">Bazel 快取</.localized_link>分別作為 Gradle 遠端構建快取及 Bazel 的 Remote Execution API 快取。
- <.localized_link href="/guides/features/cache">快取</.localized_link>列出所有支援的構建系統，包括 Elixir 和 Once。
- [緩慢構建](https://tuist.dev/solutions/slow-builds)是一份實用指南，幫助您在選擇快取前找出值得移除的工作。
- [構建系統的物理學](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems)與[Kura](https://tuist.dev/blog/2026/09/14/kura)透過 Tuist 快取的測量數據，解釋模組快取、Xcode 編譯快取、Bazel 及 Gradle 之間在產物大小與請求量上的差異。
