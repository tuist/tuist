---
{
  "title": "乜嘢係建構快取？解釋本地同遠端建構快取",
  "titleTemplate": ":title · Tuist",
  "description": "建構快取會重用之前建構嘅輸出。解釋 Xcode、Gradle 同 Bazel 入面本地同遠端建構快取點樣運作、Xcode 快取係乜，以及幾時用快取先至划算。"
}
---
# 咩係 build cache？{#what-is-a-build-cache}

Build cache 會將個別 build step 嘅輸出（例如編譯好嘅 object file、module、library 或測試結果）儲存落去，並以一個根據所有產生呢啲輸出所需輸入計算得出嘅 key 來索引：包括原始碼檔案、編譯器旗標、依賴項、環境變數同工具鏈版本。當後續 build 需要某個 step，而其輸入產生相同 key 時，build system 會直接使用已儲存嘅輸出，而唔係重新執行該 step。**Local build cache** 存放於單一機器上，並加速該機器後續嘅 build。**Remote build cache** 係一個共享伺服器，多部機器可以讀取同寫入，令到 CI job、團隊成員或 coding agent 能夠重用其他人已經 build 好嘅輸出。

## Build cache、incremental build 同 CI cache {#build-cache-incremental-build-and-ci-cache}

有三個概念經常被稱為「cache」，但佢哋嘅行為各不相同：

- **Incremental builds** 會重用你自身 build 目錄中已經存在嘅輸出，並只重新 build 自上次於該目錄 build 以來發生變化嘅部分。佢哋通常依賴檔案時間戳記或與 build 產物一同保存嘅依賴圖。切換 branch、移動 checkout 或從全新機器開始都會導致失去呢種狀態。
- **Build cache** 係根據輸入內容來查找輸出，而唔係根據同一目錄中最後 build 咗乜嘢。只要輸入匹配，這使得輸出能夠跨 branch、checkout 同機器重用。
- **CI directory caching**（例如 GitHub Actions 上嘅 `actions/cache`）會在 job 結束時保存一個目錄，並在下一個 job 開始時使用你所選擇嘅 key（例如 lockfile hash）將其恢復。這係檔案傳輸，而唔係 build cache：build system 仍然決定要重新 build 乜嘢，而恢復嘅目錄可能部分或全部過時。

Dependency cache（例如下載嘅 package 或 Gradle 或 Swift package cache）則完全不同：佢哋保存嘅係網絡獲取過程，而唔係編譯過程。

## Build cache 點樣運作 {#how-a-build-cache-works}

支援 cache 嘅 build system 會將 build 拆分為多個 step（Bazel 稱之為 actions，Gradle 稱之為 tasks），並對每個 step 執行相同操作：

1. **計算 cache key。** Build system 會對所有可能影響輸出嘅輸入進行哈希處理：包括輸入檔案內容、命令行或 task 配置、相關環境變數同工具鏈。
2. **查找 key。** 它會先檢查 local cache，如果已配置，則檢查 remote cache。
3. **Hit 或 miss。** 如果 hit，它會下載或複製已儲存嘅輸出並跳過該 step。如果 miss，它會執行該 step，並在允許情況下將輸出以上述 key 上傳。

大多數 cache 將輸出儲存於 **content-addressable storage**（CAS）中，其中每個 blob 都以其自身內容嘅哈希值儲存，另外還有一個從 cache key 到其所產生輸出嘅獨立索引。相同檔案只儲存一次，客戶端可以驗證其下載內容。

該模型有一個嚴格要求：key 必須包含所有會改變輸出嘅輸入。如果一個 step 讀取咗 build system 不知情嘅輸入（例如未聲明嘅檔案、環境變數、當前時間或機器上安裝嘅工具），cache 可能會返回與當前輸入不匹配嘅輸出。Build system 將僅依賴已聲明輸入嘅 step 稱為 **hermetic**。相反嘅問題更為常見且危險性較低：如果 key 包含無關緊要嘅內容（例如絕對路徑或時間戳記），則會在每部機器上產生不同嘅 key，導致 cache 永遠無法 hit。

## 各 build system 中 build cache 嘅運作方式 {#how-it-works-per-build-system}

### Gradle build cache {#gradle}

[Gradle build cache](https://docs.gradle.org/current/userguide/build_cache.html) 儲存可 cache task 嘅輸出（例如 Java 和 Kotlin 編譯同測試執行），並以 task 類型、實現、輸入屬性同規範化輸入檔案作為 key。預設情況下係關閉嘅。你可以透過在 `gradle.properties` 中設置 `org.gradle.caching=true` 或使用 `--build-cache` 進行單次 build 來啟用它。

- **Local。** 內置嘅 local cache 係 Gradle 用戶主目錄中嘅一個目錄（預設為 `~/.gradle`）。一旦啟用 build cache，它就會生效，並且 Gradle 會定期移除近期未使用嘅條目。
- **Remote。** Remote cache 喺 `settings.gradle(.kts)` 中配置，例如使用 `HttpBuildCache`。當 local miss 時，Gradle 會從 remote cache 下載輸出並本地儲存以備下次使用。預設情況下，remote cache 不接受上傳；常見嘅設置係讓 CI 進行推送（在 CI 中運行時設置 `isPush = true`），而開發者機器只能讀取。

Gradle 將從 cache 恢復嘅 task 報告為 `FROM-CACHE`，這與 `UP-TO-DATE` 不同：up-to-date 表示 Gradle 嘅 incremental build 發現 task 嘅輸出已經就位，無需查詢 cache。Configuration cache 係第三個獨立功能，它 cache 咗 configuration 階段嘅結果，而唔係 task 輸出。

### Bazel remote cache {#bazel}

Bazel 會 cache 每個 action。其 action cache 將 action 嘅 key（由其命令行、環境同輸入檔案嘅摘要組成）映射到 action 嘅輸出，而輸出本身則存放在 content-addressable store 中。

- **Local。** Bazel 將其 action cache 同 build 輸出保存在其 output base 中，這使得你可以在單一 workspace 中獲得快速嘅 incremental build。`--disk_cache=<path>` 添加咗一個 disk cache，可以在同一部機器上跨 workspace 同 branch 共享。
- **Remote。** `--remote_cache=grpcs://…`（或 `https://…`）將 Bazel 指向一個實現咗 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 或普通 HTTP cache 嘅 remote cache。`--remote_upload_local_results=false` 使機器變成只讀模式，這是許多團隊防止開發者機器寫入共享 cache 嘅方法。`--remote_download_minimal` 或 `--remote_download_toplevel`（「build without the bytes」）避免下載本地 build 永遠不需要嘅中間輸出。

Bazel 亦會 cache 測試結果：輸入未發生變化嘅測試會被報告為 `(cached) PASSED` 而無需運行。Remote cache 唔同於 remote execution（後者係 action 亦會在遠程機器上運行）；cache 只儲存結果。

### Xcode cache 係乜嘢？{#xcode}

Xcode 使用多個容易混淆嘅 cache 同目錄。影響 build 時間嘅包括：

- **DerivedData**（`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`）儲存每個 project 嘅 build products、中間檔案、index、logs 同已解析嘅 Swift packages。呢個係 incremental builds 重用嘅狀態。刪除佢係安全嘅，但該 project 嘅下一次 build 會變成完整 rebuild，indexing 同 package resolution 亦會重新運行。
- **The Clang module cache**（`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`）儲存預編譯嘅 Clang modules（`.pcm` 檔案），用於匯入嘅 C 同 Objective-C modules 同 SDK frameworks，並喺不同 project 之間共享。當啟用 explicitly built modules 時，Xcode 會將 modules 作為常規 build tasks 進行構建，並將其與每個 project 嘅中間檔案一起保存。刪除佢係安全嘅；modules 會按需重建。
- **The compilation cache**（Xcode 26 及更高版本，預設情況下位於 DerivedData 內嘅 `CompilationCache.noindex`，可透過 `COMPILATION_CACHE_CAS_PATH` 配置）喺 `COMPILATION_CACHE_ENABLE_CACHING = YES` 時，儲存 Swift、C 同 Objective-C 嘅 content-addressed 編譯輸出。刪除佢係安全嘅；原本可以重放嘅編譯會重新運行。
- **The Swift Package Manager cache**（`~/Library/Caches/org.swift.swiftpm/`）儲存下載嘅 package repositories 同 manifests，並喺不同 project 之間共享。刪除佢係安全嘅；packages 會重新獲取。

`~/Library/Developer` 底下嘅其他大型目錄唔係 build caches，但喺清理磁碟空間時經常出現：`Xcode/Archives` 儲存歸檔嘅 app builds 同其 debug symbols（保留你可能需要用嚟 symbolicate crashes 嘅檔案），`Xcode/iOS DeviceSupport` 儲存已連接設備 OS 版本嘅 symbols，而 `CoreSimulator/Devices` 儲存 simulators 同其數據（`xcrun simctl delete unavailable` 會移除已不再安裝嘅 runtimes 對應嘅 simulators）。

DerivedData 係 Xcode 嘅 incremental build 狀態，而唔係 content-addressed cache：佢與 project 喺磁碟上嘅位置同檔案時間戳綁定。從 CI cache 恢復 DerivedData 到不同路徑，或者喺 fresh checkout 後（因為每個檔案嘅修改時間都改變咗），通常都會導致完整 rebuild。

**compilation cache** 喺 Xcode 26 中引入，就本頁而言，佢就係 Xcode 嘅 build cache。佢根據輸入內容儲存編譯結果，並在命中時重放，因此輸出可以喺 branch 切換同清理 build products 後依然保留。佢只 cache 編譯，而唔係每個 build 步驟：linking、resource processing 同 script phases 仍然會運行。預設情況下，儲存庫位於單一機器本地並存放喺 DerivedData 內，因此刪除整個 DerivedData 會將其丟棄；只刪除 project 嘅 build products 則會保留佢。Xcode 亦可透過 plugin（`COMPILATION_CACHE_ENABLE_PLUGIN` 同 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`）將 compilation cache 連接到 remote cache service，從而將其變為共享嘅 remote cache。

喺 compilation cache 出現之前，Xcode projects 主要透過 **binary caching** 整個 modules 嚟跨機器重用工作：將 dependencies 構建為預製 frameworks 或 XCFrameworks 並鏈接佢哋，而唔係編譯源碼。呢種方式作用於 module 粒度而唔係編譯粒度，並且會改變 project 嘅構建方式。

## 延遲、blob 大小同 blob 數量 {#latency-blob-size-and-blob-count}

Remote cache hit 並唔係免費嘅。獲取輸出需要為每個必須等待前一個請求完成嘅請求付出固定延遲，加上傳輸其字節所需嘅時間：

**time ≈ R × L + S / B**

其中 *R* 係無法重疊嘅往返次數，*L* 係往返 cache 嘅延遲，*S* 係傳輸嘅字節數，而 *B* 係頻寬。邊個項佔主導地位取決於 build system 如何將工作切割成 blobs：

- **少量大 blobs 受頻寬限制。** 儲存粗粒度輸出嘅 caches（例如 Gradle task 嘅打包輸出或 binary module cache 中嘅預製 framework）發出嘅請求較少，但每個請求傳輸兆字節級別嘅數據。一組 200 MB 嘅輸出喺 100 Mbit/s 下大約需要 16 秒，喺 1 Gbit/s 下則少於 2 秒，而幾毫秒嘅額外延遲幾乎無關緊要。
- **大量小 blobs 受延遲限制。** 細粒度 caches（例如 Bazel 嘅 per-action cache 同 Xcode 嘅 compilation cache）會發出數千個請求來獲取幾千字節嘅 blobs，其中許多請求只係為了查詢 key 是否存在。如果有 2,000 次查找，同時進行 8 次，延遲為 40 ms，那麼無論 blobs 有多小，build 僅喺往返上就要等待大約 10 秒。如果延遲為 2 ms，同樣嘅查找大約只需半秒。增加頻寬對此無幫助；更接近嘅 cache 才有用。
- **Misses 亦會產生往返成本。** 每次 miss 嘅查找都會增加延遲而唔節省任何工作。一個距離遠且命中率低嘅 cache 可能會令 build 比完全沒有 remote cache 更慢。
- **數量會放大兩者影響。** Blob 嘅數量隨 project 結構增長：由許多小 modules 或 targets 組成嘅圖會產生更多、更小嘅輸出，相比少數大輸出而言。拆分 project 可以改善並行性同失效處理，但亦會令 build 對 cache 延遲更敏感。

只有當獲取輸出快過重新計算時，hit 先至值得，而呢個比較會隨距離變化。一個本地需時 50 ms 嘅編譯，對於同一網絡上嘅 cache 來講係良好嘅 hit，但對於另一個大陸上嘅 cache 來講則係糟糕嘅 hit。這就是為什麼 remote caches 嘅調節槓桿主要關於延遲同請求數量，而唔係原始頻寬：

- **將 cache 放置在靠近 build 運行嘅地方**，與 CI runners 處於同一區域或網絡，並盡可能靠近開發者。
- **重疊請求。** Bazel 嘅 Remote Execution API 批量處理存在性檢查（`FindMissingBlobs`）同小型讀取，而 `--remote_max_connections` 限制併發。Xcode 嘅 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會喺 build 其餘部分運行時同時進行 compilation cache 查找，而唔係佔用其執行通道。HTTP/2 透過單一連接多路複用多個請求。
- **減少下載量。** Bazel 嘅 `--remote_download_minimal` 跳過中間輸出，而本地 cache 層（例如 Bazel 嘅 `--disk_cache` 或 Gradle 嘅 local build cache）可以在無需網絡請求嘅情況下服務重複 hit。
- **壓縮大 blobs。** 當 cache 支持時，Bazel 嘅 `--remote_cache_compression` 會使用 zstd，這有助於受頻寬限制嘅傳輸，但對受延遲限制嘅傳輸幫助不大。

## 常見陷阱 {#common-pitfalls}

- **未聲明嘅輸入。** 某個步驟讀取咗唔屬於其 key 一部分嘅文件、環境變數或工具。Cache 隨後可能會返回由不同輸入構建嘅輸出。喺 Gradle 中，請聲明自定義任務嘅所有輸入；喺 Bazel 中，請保持動作嘅封閉性（hermetic），並考慮使用 `--incompatible_strict_action_env` 以防止主機 `PATH` 洩漏。
- **機器專屬嘅 Key。** 嵌入喺輸入或輸出中嘅絕對路徑、用戶名同 build 時間戳會令 key 喺不同機器之間產生差異，導致 remote cache 永遠無法命中。Gradle 嘅路徑敏感性、Bazel 嘅相對執行路徑，以及 Xcode 中 Clang 同 Swift 嘅前綴映射設置，都係為咗消除呢啲差異而存在。
- **靠近圖根節點嘅易變輸入。** 將 build 編號、commit hash 或日期印入一個被所有其他模組依賴嘅模組中，會導致每次 build 時其上層嘅所有內容失效。請盡可能遲啲注入易變值，理想情況下只注入到 release build 中。
- **工具鏈不匹配。** 不同嘅編譯器、JDK 或 Xcode 版本會產生不同嘅 key。雖然呢個係正確行為，但混合版本嘅集群實際上會分割 cache。
- **受污染或不可信嘅寫入。** 帶有未提交更改或非封閉設置嘅開發者機器可能會上傳輸出，而被其他人重複使用。許多團隊只允許受信分支上嘅 CI 寫入 remote cache，並將其他所有機器設為只讀。不可信 pull request 嘅 build 不應寫入受信 build 所讀取嘅 cache。
- **忽略傳輸成本。** 一個運行需時 50 毫秒嘅步驟，從遠程 cache 獲取可能需要更長時間。請參閱 [延遲、Blob 大小同 Blob 數量](#latency-blob-size-and-blob-count)。
- **隱藏嘅測試運行。** 當測試係確定性時，緩存測試結果係正確嘅，但這亦意味著一個曾經通過嘅不穩定測試會喺唔運行嘅情況下持續顯示通過。請參閱 <.localized_link href="/references/concepts/flaky-test">什麼係不穩定測試？</.localized_link>。

## 如何衡量 build cache {#how-to-measure-a-build-cache}

Cache 嘅價值在於佢端到端節省咗幾多，而唔係單單睇命中率：

- **按工作量加權嘅命中率。** 統計每個步驟嘅 hit 同 miss，但要根據每個步驟嘅運行時間進行加權。喺低成本步驟上達到 95% 嘅命中率，可能比喺最慢嘅編譯上達到 50% 嘅命中率節省更少時間。
- **Cold、Warm 同典型 Build。** 比較空 cache 嘅 build、完全 warm cache 嘅 build，同人哋實際運行嘅 build（例如小改動後 pull request 上嘅 CI）。最後一個數字先至最重要。
- **花費喺 cache 本身嘅時間。** 測量請求數量、延遲、字節數，以及下載同上傳所花費嘅時間。如果大部分時間都係喺等待許多小請求，那麼更近嘅 cache 比更大頻寬更有幫助；如果係傳輸少數大 blob，則頻寬同壓縮更為重要。
- **Miss 發生嘅原因。** 比較兩台機器上同一步驟嘅 cache key。Gradle 可以透過 `-Dorg.gradle.caching.debug=true` 打印每個 key 背後嘅輸入，Bazel 可以寫入執行日誌（`--execution_log_compact_file`）供你比較兩次 build 之間嘅差異，而當 `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` 時，Xcode 會喺 build 日誌中報告 compilation cache 嘅 hit 同 miss。

## 何時唔值得使用 {#when-it-isnt-worth-it}

Build cache 會增加基礎設施、安全邊界同一類新嘅 bug。佢並唔總係正確嘅工具：

- **小型或快速 Build。** 如果 clean build 只需一分鐘，remote cache 節省嘅時間好少，而網絡往返甚至可能令其更慢。
- **設計上就會 Miss 嘅 Build。** 如果大多數 build 都會改變靠近圖根節點嘅輸入，喺修復之前 cache 無法提供幫助。先修復失效問題；cache 只會跳過輸入匹配嘅工作。
- **持久化嘅 Build 機器。** 喺同一分支嘅作業之間保留 build 目錄嘅 CI 機器已經獲得增量 build。當機器係短暫存在、有許多分支，或者開發者同 CI 應該重用彼此工作時，共享 cache 先至有帮助。
- **暫時無法修復嘅非封閉 Build。** 偶爾返回錯誤輸出嘅 cache 所消耗嘅信任成本超過佢節省嘅時間。請先確保你緩存嘅步驟可復現，或者讓有問題嘅步驟不緩存（例如使用 Bazel 嘅 `no-remote-cache` 標籤）。
- **緩慢或遙遠嘅網絡。** 如果 cache 距離 build 運行位置好遠，請喺向所有人推廣之前測量傳輸時間。

## 使用 Tuist 進行 Build 緩存 {#build-caching-with-tuist}

[Tuist](https://tuist.dev) 提供一個 remote cache，插入每個 build 系統自身嘅緩存機制中，令開發者機器、CI 同編碼代理可以重用彼此嘅輸出，並記錄 hit、miss 同傳輸時間，以便你衡量效果：

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> 將 Xcode 嘅 compilation cache 連接到共享 remote cache，適用於 Xcode 26 或更高版本上嘅任何 Xcode project。
- <.localized_link href="/guides/features/cache/module-cache">Module cache</.localized_link> 喺由 Tuist 生成嘅 project 中，用預構建二进制文件替換整個 modules。
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle cache</.localized_link> 同 <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link> 分別作為 Gradle remote build cache 同 Bazel 嘅 Remote Execution API cache。
- <.localized_link href="/guides/features/cache">Cache</.localized_link> 列出所有支持嘅 build 系統，包括 Elixir 同 Once。
- [Slow builds](https://tuist.dev/solutions/slow-builds) 係一份實用指南，幫助你喺選擇 cache 之前找出值得移除嘅工作。
- [The physics of build systems](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) 同 [Kura](https://tuist.dev/blog/2026/09/14/kura) 透過 Tuist cache 嘅測量數據，解釋 module cache、Xcode compilation cache、Bazel 同 Gradle 之間 artifact 大小同請求量嘅差異。
