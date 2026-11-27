---
{
  "title": "咩係編譯快取？本地同遠端編譯快取詳解",
  "titleTemplate": ":title · Tuist",
  "description": "編譯快取會重用之前編譯嘅輸出。解釋 Xcode、Gradle 同 Bazel 入面本地同遠端編譯快取點運作、Xcode 快取係乜，以及幾時用快取先至抵。"
}
---
# 咩係 build cache？{#what-is-a-build-cache}

Build cache 會將個別 build 步驟嘅輸出（例如編譯後嘅 object files、modules、libraries 或測試結果）儲存起來，並用一條根據所有輸入計算得出嘅 key 來索引：包括原始碼檔案、編譯器參數、依賴項、環境變數同工具鏈版本。當後續 build 需要執行某個步驟，而其輸入產生相同嘅 key 時，build system 就會直接使用已儲存嘅輸出，而唔係重新執行該步驟。**Local build cache** 存放喺單一機器上，可以加速該機器後續嘅 build。**Remote build cache** 係一個共享伺服器，多部機器都可以讀寫，令到 CI job、團隊成員或 coding agent 可以重用其他人已經 build 好嘅輸出。

## Build cache、incremental build 同 CI cache {#build-cache-incremental-build-and-ci-cache}

有三個概念經常被稱為「cache」，但佢哋嘅運作方式唔同：

- **Incremental builds** 會重用你本地 build 目錄中已經存在嘅輸出，只重新 build 自上次 build 以來發生變化嘅部分。佢哋通常依賴檔案時間戳或與 build 產物一齊保存嘅依賴關係圖。切換分支、移動 checkout 位置，或者從全新機器開始，都會導致呢啲狀態丟失。
- **Build cache** 係根據輸入內容來查找輸出，而唔係根據同一目錄中最後 build 咗乜嘢。只要輸入匹配，輸出就可以跨分支、checkout 同機器重用。
- **CI directory caching**（例如 GitHub Actions 上嘅 `actions/cache`）會在 job 結束時保存一個目錄，並在下一個 job 開始時恢復它，使用你選擇嘅 key（例如 lockfile hash）。這只係檔案傳輸，並唔係 build cache：build system 仍然決定要重新 build 乜嘢，而且恢復嘅目錄可能部分或全部過時。

Dependency caches（例如下載嘅 packages 或 Gradle/Swift package cache）又係另一回事：佢哋節省嘅係網絡下載，而唔係編譯過程。

## Build cache 點樣運作 {#how-a-build-cache-works}

支援 caching 嘅 build system 會將 build 拆分為多個步驟（Bazel 稱之為 actions，Gradle 稱之為 tasks），並對每個步驟執行相同操作：

1. **計算 cache key。** Build system 會對所有可能影響輸出嘅輸入進行哈希處理：包括輸入檔案內容、命令行或 task 配置、相關環境變數以及工具鏈。
2. **查找 key。** 它會先檢查 local cache，如果配置咗 remote cache，也會檢查 remote cache。
3. **Hit 或 miss。** 如果 hit，它會下載或複製儲存的輸出並跳過該步驟。如果 miss，它會執行該步驟，並在允許的情況下將輸出以上述 key 上傳。

大多數 cache 將輸出存儲喺 **content-addressable storage** (CAS) 中，其中每個 blob 都以其自身內容嘅哈希值存儲，另外還有一個從 cache keys 到其產生輸出嘅獨立索引。相同檔案只存儲一次，客戶端可以驗證下載內容。

呢個模型有一個嚴格要求：key 必須包含所有會改變輸出嘅輸入。如果一個步驟讀取咗 build system 不知情嘅輸入（例如未聲明嘅檔案、環境變數、當前時間或機器上安裝嘅工具），cache 可能會返回與當前輸入不匹配嘅輸出。Build system 將只依賴已聲明輸入嘅步驟稱為 **hermetic**。相反嘅問題更常見且危險性較低：如果 key 包含無關內容（例如絕對路徑或時間戳），則每部機器都會產生不同嘅 key，導致 cache 永遠無法 hit。

## 不同 build system 中 build cache 嘅運作方式 {#how-it-works-per-build-system}

### Gradle build cache {#gradle}

[Gradle build cache](https://docs.gradle.org/current/userguide/build_cache.html) 會儲存可 cache task 嘅輸出（例如 Java 和 Kotlin 編譯及測試執行），key 由 task 類型、實現、輸入屬性和規範化輸入檔案決定。默認情況下它是關閉嘅。你可以透過在 `gradle.properties` 中設置 `org.gradle.caching=true`，或使用 `--build-cache` 執行單次 build 來啟用它。

- **Local。** 內置嘅 local cache 係 Gradle user home 中嘅一個目錄（默認為 `~/.gradle`）。一旦啟用 build cache，它就會生效，Gradle 會定期刪除近期未使用嘅條目。
- **Remote。** Remote cache 喺 `settings.gradle(.kts)` 中配置，例如使用 `HttpBuildCache`。當 local miss 時，Gradle 會從 remote cache 下載輸出並本地儲存以供下次使用。默認情況下，remote cache 不接受上傳；常見嘅設置係讓 CI 推送（在 CI 運行時設置 `isPush = true`），而開發者機器只讀。

Gradle 將從 cache 恢復嘅 task 報告為 `FROM-CACHE`，這與 `UP-TO-DATE` 不同：up-to-date 表示 Gradle 嘅 incremental build 發現 task 輸出已經就位，無需查詢 cache。Configuration cache 係第三個獨立功能，它 cache 配置階段嘅結果，而非 task 輸出。

### Bazel remote cache {#bazel}

Bazel 會 cache 每個 action。其 action cache 將 action key（命令行、環境和輸入檔案嘅摘要）映射到 action 輸出，而輸出本身存儲喺 content-addressable store 中。

- **Local。** Bazel 將其 action cache 和 build 輸出保存在 output base 中，這使得單一 workspace 中可以快速進行 incremental build。`--disk_cache=<path>` 添加咗一個 disk cache，可以在同一部機器上跨 workspace 和分支共享。
- **Remote。** `--remote_cache=grpcs://…`（或 `https://…`）將 Bazel 指向一個實現咗 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 或普通 HTTP cache 嘅 remote cache。`--remote_upload_local_results=false` 使機器成為只讀模式，這是許多團隊防止開發者機器寫入共享 cache 嘅方法。`--remote_download_minimal` 或 `--remote_download_toplevel`（「build without the bytes」）避免下載本地 build 永遠不需要嘅中間輸出。

Bazel 也會 cache 測試結果：輸入未改變嘅測試會被報告為 `(cached) PASSED` 而無需運行。Remote cache 不等於 remote execution（後者係指 actions 也在遠程機器上運行）；cache 只儲存結果。

### Xcode caches 係乜嘢？{#xcode}

Xcode 使用多個容易混淆嘅 cache 和目錄。影響 build 時間嘅包括：

- **DerivedData** (`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`) 儲存每個 project 嘅 build products、intermediate files、index、logs 同 resolved Swift packages。呢個係 incremental builds 重用嘅狀態。刪除佢係安全嘅，但該 project 嘅下一次 build 會變成 full rebuild，而 indexing 同 package resolution 亦會重新運行。
- **The Clang module cache** (`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`) 儲存預編譯嘅 Clang modules（`.pcm` 檔案），用於匯入嘅 C 和 Objective-C modules 同 SDK frameworks，並喺不同 project 之間共享。如果啟用咗 explicitly built modules，Xcode 會將 modules 作為常規 build tasks 進行構建，並將佢哋同每個 project 嘅 intermediates 放在一起。刪除佢係安全嘅；modules 會按需重新構建。
- **The compilation cache**（Xcode 26 及更高版本，默認情況下位於 DerivedData 內嘅 `CompilationCache.noindex`，可通過 `COMPILATION_CACHE_CAS_PATH` 配置）喺 `COMPILATION_CACHE_ENABLE_CACHING = YES` 時儲存 Swift、C 和 Objective-C 嘅 content-addressed compilation outputs。刪除佢係安全嘅；原本可以重放嘅 compilations 會重新運行。
- **The Swift Package Manager cache** (`~/Library/Caches/org.swift.swiftpm/`) 儲存下載嘅 package repositories 和 manifests，並喺不同 project 之間共享。刪除佢係安全嘅；packages 會重新獲取。

`~/Library/Developer` 下嘅其他大型目錄唔係 build caches，但在清理磁碟空間時經常出現：`Xcode/Archives` 儲存歸檔嘅 app builds 及其 debug symbols（保留你可能需要用嚟 symbolicate crashes 嘅那些），`Xcode/iOS DeviceSupport` 儲存連接設備 OS 版本嘅 symbols，而 `CoreSimulator/Devices` 儲存 simulators 及其數據（`xcrun simctl delete unavailable` 會移除已不再安裝嘅 runtimes 對應嘅 simulators）。

DerivedData 係 Xcode 嘅 incremental build state，唔係 content-addressed cache：佢與 project 喺磁碟上嘅位置同文件時間戳綁定。從 CI cache 以不同路徑恢復 DerivedData，或者喺 fresh checkout 改變咗每個文件嘅修改時間之後恢復，通常都會導致 full rebuild。

**compilation cache** 喺 Xcode 26 中引入，就本頁而言係 Xcode 嘅 build cache。佢根據輸入嘅內容儲存 compilation results，並在 hit 時重放佢哋，因此 outputs 可以喺 branch 切換和清理 build products 後依然保留。佢 cache 嘅係 compilation，而非每個 build step：linking、resource processing 和 script phases 仍然會運行。默認情況下，store 係本地嘅並位於 DerivedData 內，因此刪除整個 DerivedData 會丟失佢；只刪除 project 嘅 build products 則會保留佢。Xcode 還可以通過插件（`COMPILATION_CACHE_ENABLE_PLUGIN` 和 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`）將 compilation cache 連接到 remote cache service，從而將其變為共享嘅 remote cache。

喺 compilation cache 出現之前，Xcode projects 主要通過 **binary caching** 整個 modules 來跨機器重用工作：將 dependencies 構建為 prebuilt frameworks 或 XCFrameworks 並鏈接佢哋，而不是編譯源碼。這係喺 module 粒度而非 compilation 粒度上運作，並改變咗 project 嘅構建方式。

## Latency、blob size 和 blob count {#latency-blob-size-and-blob-count}

Remote cache hit 唔係免費嘅。獲取 output 需要為每個必須等待前一個請求完成嘅請求付出固定延遲，加上傳輸其字節所需嘅時間：

**time ≈ R × L + S / B**

其中 *R* 係無法重疊嘅 round trips 數量，*L* 係到 cache 嘅 round-trip latency，*S* 係傳輸嘅字節數，而 *B* 係頻寬。哪個項佔主導取決於 build system 如何將工作切割成 blobs：

- **少量大 blobs 受頻寬限制。** 儲存粗粒度 outputs 嘅 caches（例如 Gradle task 嘅打包 outputs 或 binary module cache 中嘅 prebuilt framework）發出嘅請求較少，但每個請求傳輸兆字節級別嘅數據。一組 200 MB 嘅 outputs 喺 100 Mbit/s 下大約需要 16 秒，喺 1 Gbit/s 下少於 2 秒，而幾毫秒嘅額外 latency 幾乎無關緊要。
- **大量小 blobs 受 latency 限制。** 細粒度 caches（例如 Bazel 嘅 per-action cache 和 Xcode 嘅 compilation cache）會發出數千個請求來獲取幾千字節嘅 blobs，其中許多請求只係為了詢問 key 是否存在。如果有 2,000 次查找，同時進行 8 次，latency 為 40 ms，那麼 build 僅喺 round trips 上就要等待大約 10 秒，無論 blobs 有多小。如果 latency 為 2 ms，同樣嘅查找大約需要半秒。增加頻寬對此無助；更接近嘅 cache 才有幫助。
- **Misses 亦會產生 round trip 成本。** 每次 miss 嘅查找都會增加 latency 而唔節省任何工作。一個距離遠且 hit rate 低嘅 cache 可能會使 build 比完全沒有 remote cache 更慢。
- **數量會放大兩者影響。** Blob 嘅數量隨 project 結構增長：由許多小 modules 或 targets 組成嘅圖會產生更多、更小嘅 outputs，而非少數大 outputs。拆分 project 可以提高並行性和 invalidation 效率，但亦會使 build 對 cache latency 更敏感。

只有當獲取 output 快過重新計算時，hit 先至值得，而這種比較會隨距離變化。一個本地需要 50 ms 嘅 compilation，對於同一網絡上嘅 cache 來說係好嘅 hit，但對於另一個大陸上嘅 cache 來說則係差嘅 hit。這就是為什麼 remote caches 嘅槓桿主要在於 latency 和請求數量，而非原始頻寬：

- **將 cache 放置在靠近 build 運行嘅地方**，與 CI runners 處於同一區域或網絡，並盡可能靠近開發者。
- **重疊請求。** Bazel 嘅 Remote Execution API 批量處理存在性檢查（`FindMissingBlobs`）和小讀取，而 `--remote_max_connections` 限制併發性。Xcode 嘅 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會喺 build 嘅其餘部分進行時同時運行 compilation cache 查找，而非佔用其執行通道。HTTP/2 喺單一連接上多路復用多個請求。
- **減少下載量。** Bazel 嘅 `--remote_download_minimal` 跳過中間 outputs，而本地 cache 層（例如 Bazel 嘅 `--disk_cache` 或 Gradle 嘅 local build cache）無需網絡請求即可服務重複 hits。
- **壓縮大 blobs。** 當 cache 支持時，Bazel 嘅 `--remote_cache_compression` 使用 zstd，這有助於受頻寬限制嘅傳輸，但對受 latency 限制嘅傳輸幫助不大。

## 常見陷阱 {#common-pitfalls}

- **未宣告的輸入。** 某個步驟讀取咗一個唔屬於其 key 一部分嘅檔案、環境變數或工具。Cache 隨後可能會返回由不同輸入構建嘅 outputs。喺 Gradle 中，宣告自定義 tasks 嘅每一個輸入；喺 Bazel 中，保持 actions 嘅 hermetic 性，並考慮使用 `--incompatible_strict_action_env` 以防止主機嘅 `PATH` 滲漏進去。
- **機器專屬嘅 keys。** 嵌入喺輸入或輸出中嘅絕對路徑、用戶名和 build timestamps 會導致 keys 喺不同機器之間有所不同，因此 remote cache 永遠無法 hit。Gradle 嘅路徑敏感性、Bazel 嘅相對執行路徑，以及 Xcode 中 Clang 和 Swift 嘅 prefix-mapping 設置，都係為咗消除這些差異而存在。
- **靠近圖表根部嘅易變輸入。** 將 build number、commit hash 或日期印入一個所有其他模塊都依賴嘅模塊中，會導致每次 build 時其上層嘅所有內容失效。盡可能晚啲注入易變值，理想情況下只注入到 release builds 中。
- **Toolchain 不匹配。** 不同嘅編譯器、JDK 或 Xcode 版本會產生不同嘅 keys。這係正確嘅行為，但混合版本嘅機群實際上會分割 cache。
- **受污染或不可信嘅寫入。** 帶有未提交更改或非 hermetic 設置嘅開發者機器可能會上傳 outputs，然後被其他人重用。許多團隊只允許受信分支上嘅 CI 寫入 remote cache，並將其他所有機器設為只讀。不受信 pull requests 嘅 builds 不應寫入受信 builds 所讀取嘅 cache。
- **忽略傳輸成本。** 一個運行需要 50 毫秒嘅步驟，從遠處嘅 cache 獲取可能需要更長時間。請參閱 [Latency、blob 大小和 blob 數量](#latency-blob-size-and-blob-count)。
- **隱藏嘅測試運行。** 當測試係確定性嘅時候，cache 測試結果係正確嘅，但這亦意味著一個曾經通過嘅 flaky test 會喺唔運行嘅情況下繼續顯示為通過。請參閱 <.localized_link href="/references/concepts/flaky-test">什麼是 flaky test？</.localized_link>。

## 如何衡量 build cache {#how-to-measure-a-build-cache}

Cache 嘅價值在於它端到端節省咗幾多，而唔係單單睇佢嘅 hit rate：

- **Hit rate，按工作量加權。** 計算每個步驟嘅 hits 和 misses，但按每個步驟運行所需嘅時間進行加權。喺便宜步驟上達到 95% 嘅 hit rate 所節省嘅時間，可能少過喺最慢編譯上達到 50% hit rate 所節省嘅時間。
- **Cold、warm 和典型 builds。** 比較一個空 cache 嘅 build、一個完全 warm cache 嘅 build，以及人們實際運行嘅 builds（例如小改動後 pull request 上嘅 CI）。最後一個數字先至最重要。
- **花費喺 cache 本身嘅時間。** 測量請求數量、latency、字節數，以及下載和上傳所花費嘅時間。如果大部分時間都係喺等待許多小請求，那麼更近嘅 cache 比更大頻寬更有幫助；如果係移動少數大 blobs，則頻寬和壓縮更為重要。
- **Misses 發生嘅原因。** 比較兩台機器上同一個步驟嘅 cache keys。Gradle 可以使用 `-Dorg.gradle.caching.debug=true` 打印每個 key 背後嘅輸入，Bazel 可以寫入執行日誌（`--execution_log_compact_file`），你可以對比兩次 build 之間嘅差異，而當 `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` 時，Xcode 會喺 build log 中報告 compilation cache 嘅 hits 和 misses。

## 何時不值得使用 {#when-it-isnt-worth-it}

Build cache 會增加基礎設施、安全邊界和一類新嘅 bugs。它並不總係正確嘅工具：

- **小型或快速 builds。** 如果 clean build 只需要一分鐘，remote cache 節省嘅時間好少，而網絡 round trips 甚至可能使其變慢。
- **設計上就會 miss 嘅 builds。** 如果大多數 builds 都會改變靠近圖表根部嘅輸入，喺修復之前 cache 無法提供幫助。首先修復 invalidation 問題；cache 只會跳過輸入匹配嘅工作。
- **持久化嘅 build 機器。** 喺同一分支嘅不同 jobs 之間保留 build 目錄嘅 CI 機器已經可以獲得增量 builds。當機器係短暫嘅、有許多分支，或者開發者和 CI 應該重用彼此工作時，共享 cache 會更有幫助。
- **暫時無法修復嘅非 hermetic builds。** 偶爾返回錯誤 outputs 嘅 cache 所消耗嘅信任，多過它所節省嘅時間。首先確保你 cache 嘅步驟係可重現嘅，或者讓有問題嘅步驟不被 cache（例如使用 Bazel 嘅 `no-remote-cache` tag）。
- **緩慢或遙遠嘅網絡。** 如果 cache 距離 build 運行嘅地方好遠，喺向所有人推廣之前先測量傳輸時間。

## 使用 Tuist 進行 build caching {#build-caching-with-tuist}

[Tuist](https://tuist.dev) 提供一個 remote cache，它可以插入每個 build system 自身嘅 caching 機制中，令開發者機器、CI 和 coding agents 能夠重用彼此嘅 outputs，並且它會記錄 hits、misses 和傳輸時間，以便你衡量效果：

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> 將 Xcode 嘅 compilation cache 連接到共享嘅 remote cache，適用於 Xcode 26 或更高版本上嘅任何 Xcode project。
- <.localized_link href="/guides/features/cache/module-cache">Module cache</.localized_link> 喺使用 Tuist 生成嘅 projects 中，用預構建嘅二進制文件替換整個 modules。
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle cache</.localized_link> 和 <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link> 分別作為 Gradle 嘅 remote build cache 和 Bazel 嘅 Remote Execution API cache。
- <.localized_link href="/guides/features/cache">Cache</.localized_link> 列出咗所有支持嘅 build systems，包括 Elixir 和 Struo。
- [Slow builds](https://tuist.dev/solutions/slow-builds) 係一份實用指南，幫助你喺選擇 cache 之前找出值得移除嘅工作。
- [The physics of build systems](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) 和 [Kura](https://tuist.dev/blog/2026/09/14/kura) 透過 Tuist cache 嘅測量數據，解釋咗 module cache、Xcode compilation cache、Bazel 和 Gradle 之間 artifact 大小和請求量嘅差異。
