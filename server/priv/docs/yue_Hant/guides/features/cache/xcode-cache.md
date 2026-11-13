---
{
  "title": "Xcode 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 Xcode 快取整合，加快本地同 CI 上嘅 Xcode 建置速度。"
}
---
# Xcode 快取 {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊可以善用建構系統的快取功能，共用編譯產物。

Xcode 快取於 Xcode 26 引入。你也可能見到它被稱為 Xcode 建構快取；它會根據輸入內容重用編譯產物，而 Tuist 的遠端快取則讓這些產物可以在不同機器之間共用。

> [!TIP]
> **與模組快取搭配使用**
>
> Xcode 快取與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 在不同粒度層級運作，並互相補足。模組快取在建構執行前，以預先建置好的 `.xcframework` 取代整個模組；而 Xcode 快取則在建構期間重用編譯輸出。

> [!TIP]
> **在開發者機器上清理時，保留 `CompilationCache.noindex`**
>
> 預設情況下，編譯快取存放區位於 `DerivedData` 內，因此刪除 `DerivedData` 會連同建構產物一併清除。在開發者機器上，建議只刪除建構產物：重新建構時會直接從磁碟上的存放區重播，無需抓取任何內容。

## 設定 {#setup}

如果你尚未擁有 Tuist 帳戶與專案，可以執行以下指令來建立：

```bash
tuist init
```

當你擁有參照你 `fullHandle` 的 `Tuist.swift` 檔案後，就可以執行以下指令為你的專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在啟動時執行本機快取服務，供 Swift [建構系統](https://github.com/swiftlang/swift-build) 用來共用編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

若要在 CI 上設定快取，請確保你已<.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

### 更新快取元件 {#updating-the-cache-components}

快取代理程式使用穩定的啟動器，而非綁定至最後一次執行設定的 Tuist 安裝路徑。安裝後，`tuist setup cache` 與啟用快取的 `tuist generate` 會將可用目標推進至較新的 Tuist 版本。因此，綁定至較舊 Tuist 的專案不會降級共用的代理程式。產生作業只會更新現有的啟動器目標：它不會安裝服務、進行驗證、替換外掛程式，或重新啟動代理程式。自訂的外掛程式、代理程式、通訊端或註冊表覆寫會略過自動推進。

執行中的代理程式只會在至少 30 秒內沒有快取請求、沒有進行中的請求或背景工作，且其發布佇列已清空的情況下，才採用新目標。隨後它會退出，launchd 會啟動所選的 CLI，並保留服務的參數與憑證環境。只有實際採用目標的代理程式才會以原子方式從其套件刷新磁碟上的外掛程式；當較舊的代理程式仍在清空時，設定不會安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒設定會重新啟動所選代理程式以重試刷新。仍然只有一個代理程式擁有註冊表與佇列。無法使用的目標或未清空的上傳會延遲切換，而不會中斷進行中的請求。憑證刷新會跟隨所選的 CLI，即使在切換之前也是如此，因此移除較舊的 CLI 安裝不會導致等待清空的上傳被擱置。

在穩定啟動器出現之前建立的現有安裝需要一次明確的遷移。當沒有建構正在執行時，請執行以下指令：

```bash
tuist setup cache
```

完成該遷移後，更新 Tuist 並執行你慣用的 `tuist generate` 就足以推進代理程式與已安裝的外掛程式；你不需要為每個 CLI 版本重新執行設定。若要選擇不同的 Xcode（包括在同一路徑更新的 Xcode），仍需要明確設定。當共享服務的配置變更時，設定可能會替換該服務，因此請先等待機器上的所有建構完成。代理程式同時支援先前與目前的外掛程式協定，因此已在 Xcode 中載入的相容外掛程式在代理程式升級後仍可繼續運作。完全退出並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更了產生的建構設定時，請重新產生專案。

保持所選的 Tuist 安裝可用：啟動器會使用它來進行啟動、配置與憑證刷新。一旦啟動器已推進，就可以移除較舊的安裝。如果所選的可執行檔已被刪除或不再可執行，`tuist setup cache` 可以使用可用的安裝（即使是較舊的版本）修復目標，而無需先拆除快取。穩定的可執行檔別名會在套件管理器升級期間保留；只有在比較安裝身分時才會解析符號連結。在啟動時，代理程式會記錄實際啟動的版本，包括就地更新或刻意回滾，同時保留所使用的最高版本，以防止不相關的較舊檢出切換至可用的安裝。

沒有發行版本且明確設定 `TUIST_CAS_PLUGIN_PATH` 或 `TUIST_CAS_PROXY_PATH` 的原始碼建構 CLI 會使用明確的啟動配置，而非自動版本選擇。在重建這些元件後，請重新執行設定。設定會檢查它們的新鮮度，並僅在其替換品就緒後才停用受管理的目標推進。

`tuist teardown cache` 會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可供重新啟動與再次嘗試拆除。成功拆除後，產生作業無法重新建立服務。

### 配置 Xcode 建構設定 {#configure-xcode-build-settings}

對於現有的 Xcode 專案，請將 `tuist setup cache` 印出的建構設定複製到專案的「Build Settings」或現有的 `.xcconfig` 檔案中。該指令會印出你帳戶的配置；它不會產生配置文件或編輯你的 Xcode 專案。在擴充 `OTHER_SWIFT_FLAGS` 時請保留 `$(inherited)`，以確保其他編譯器選項得以保留。

設定包括：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 與 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 需要作為 **使用者定義的建構設定** 加入，因為它們並未直接在 Xcode 的建構設定 UI 中公開。

> [!NOTE]
> **外掛程式路徑**
>
> `libtuist_cas_plugin.dylib` 是隨 Tuist 一併提供的編譯快取外掛程式，位於 `tuist` 可執行檔旁邊。`tuist setup cache` 會將其複製到 `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而 `COMPILATION_CACHE_PLUGIN_PATH` 則指向該副本。此路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與專案一同提交。設定程序與新啟動的代理程式會從所選的 Tuist 套件刷新該副本；從較舊的檢出版本執行設定不會將較新的外掛程式降級。

> [!NOTE]
> **每個專案使用同一個 Socket**
>
> `tuist setup cache` 會在每台機器上安裝單一快取代理程式，因此每個專案都使用相同的 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance` 外掛程式選項是用來識別專案的設定。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 是用來共用 C 與 Objective-C 的設定**
>
> 這個設定很容易被解讀為「快取服務的位置」而被視為可選。但它也是決定是否共用 C、Objective-C、預編譯模組與預編譯標頭檔的關鍵開關：只有在配置了遠端快取服務時，建構系統才會為這些項目執行快取。如果省略此設定，Swift 編譯仍會共用，但在任何未曾建構過該專案的機器上，每個 C/Objective-C 檔案與每個模組都會重新編譯。

> [!NOTE]
> **並行快取查詢**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會讓建構系統為每次編譯執行的遠端快取查詢與其餘建構工作並行進行，而不是在建構的執行通道上一次只處理少數幾個。當建構需要從遠端快取錯過或還原大量編譯時，能更快完成。

你也可以在執行 `xcodebuild` 時透過加入以下旗標來指定這些設定，例如：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Xcode 27 及之後版本的前綴映射**
>
> 在 Xcode 27 及之後版本中，`tuist setup cache` 也會印出 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING` 與 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。這些設定讓編譯快取金鑰獨立於專案與 `DerivedData` 所在的位置。請將它們作為使用者定義的建構設定加入。啟用這些設定會改變所有快取金鑰，因此下一次建構會重新填充快取。當 `enableCaching` 啟用時，`tuist generate` 會為你設定這些值。
>
> 編譯器也會將映射後的路徑寫入程式碼涵蓋率資料中，而 Xcode 無法解析這些路徑，因此涵蓋率報告會遺漏所有使用前綴映射編譯的原始碼。印出的設定連同 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 相關設定，會在收集程式碼涵蓋率的建構中關閉前綴映射。`tuist generate` 也會執行相同操作。這些建構仍會使用編譯快取，但其快取金鑰取決於專案與 `DerivedData` 路徑。
>
> 當你在命令列將這些設定傳遞給 `xcodebuild` 時，請對包含 `$(...)` 的值使用單引號包覆，如同上方的 `OTHER_SWIFT_FLAGS`。否則 Shell 會將它們展開為空字串，導致前綴映射被關閉：
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **產生的專案**
>
> 如果你的專案是由 Tuist 產生的，則無需手動設定這些設定。
>
> 在這種情況下，你只需在 `Tuist.swift` 檔案中加入 `enableCaching: true`：
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### 使用前綴映射的涵蓋率 {#coverage-with-prefix-mapping}

預設情況下，產生的專案會在涵蓋率建構中停用前綴映射，以確保 Xcode 的涵蓋率報告與 `xccov` 正常運作。你可以啟用它，讓涵蓋率編譯在不同檢出版本之間可共用：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）的優先級高於 `prefixMapping`。此選項適用於 Xcode 27 及之後版本，且需要啟用 `enableCaching`。涵蓋率 `tuist test` 上傳支援此功能：Tuist 使用 `llvm-cov` 測量執行過程，它會讀取具有映射路徑的原始碼，並將它們對應回你儲存庫中的檔案。Xcode 自身的涵蓋率報告與 `xccov` 仍可能遺漏這些原始碼，而如果 `llvm-cov` 匯出失敗，上傳作業退回使用結果套件的 `xccov` 報告時也會遺漏。映射後的 `#filePath` 值也可能影響相對於原始碼檔案定位測試固定裝置的測試；請改為透過明確的執行時期檢出路徑來解析固定裝置。如果你自行處理涵蓋率，請將每個檢測過的二進位檔與其目標的 `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` 配對，該檔案會將虛擬前綴映射回本機目錄。當啟用每專案映射時，請勿將單一目標的映射重複用於每個二進位檔。

涵蓋率前綴設定會參與二進位快取與選擇性測試的雜湊計算，因為它們控制寫入涵蓋率產物的路徑。更改此選項或以不同方式設定 `TUIST_COVERAGE_PREFIX_MAPPING`，即使對於一般建構也會使這些雜湊失效。如果開發人員與 CI 工作應該共用二進位快取與選擇性測試結果，請保持該值一致。

### 除錯產生的專案 {#debugging-generated-projects}

還原的原生模組需要連結的除錯資訊以及對編譯快取的存取權限。Tuist 會使用 dSYM 與每切片原始碼身分元資料來暖身 Debug 與 Release 模組，然後在替換目標之前，根據消費者宣告的原始碼驗證元資料。缺少或不兼容的元資料會保留該目標的原始碼。腳本產生的 `.generated(...)` 原始碼擁有宣告指紋而非可驗證的內容雜湊，因此這些目標會保持從原始碼建構，且不會發布至原生模組快取。具有實際內容雜湊的產生資源存取器仍然符合資格。不支援的除錯資訊會跳過受影響目標的發布，而不會阻擋不相關的產品；原始碼變更與取消仍會導致暖身失敗。快取格式已變更，因此由較舊版本暖身的產物需要重新暖身。

對於已驗證的替換，Tuist 會在消費者擁有的 dSYM UUID plist 中準備原始碼重定位，並為靜態快取程式碼連結僅供除錯使用的伴隨檔案。它不會重寫快取的二進位檔，也不會在 LLDB 的持久全域原始碼地圖中安裝生產者原始碼路徑。明確的除錯器初始化器與模組載入器設定仍然具有權威性。除錯符號與原始碼重定位不會修復相對於原始碼的執行時期檔案存取或原生 Xcode 涵蓋率報告；涵蓋率變體選擇與 LLVM 匯出仍然是獨立的功能。

啟用 `enableCaching: true` 時，Tuist 會為 Run 與 Test 動作設定 LLDB 原始碼地圖。當動作擁有自訂 LLDB 初始化器時，Tuist 會先寫入已解析的原始碼地圖，然後載入該自訂初始化器，以便擴充或覆寫地圖。否則，它會在替換原始碼地圖之前，若檔案存在則載入 `~/.lldbinit-Xcode`，否則回退至 `~/.lldbinit`。它只會載入一個主目錄檔案，在避免重複載入的情況下恢復每位使用者的除錯器設定。替換會移除先前執行留下的過時映射，並優先於主目錄檔案的原始碼地圖；請將需要保留的原始碼地圖條目放入動作的自訂初始化器中。其他主目錄設定則會保留。Tuist 專用於快取的模組搜尋路徑、載入器設定與 Clang 旗標會在之後套用，並優先於使用者對這些設定的值。主目錄檔案錯誤仍然可見，不會阻止後續命令載入，且命令不會被回顯。即使沒有 `enableCaching` 或在較舊的 Xcode 版本上，當 Tuist 為從模組快取還原的二進位檔設定除錯時，此初始化器保留機制同樣適用。

在 Xcode 27 及更高版本中，產生的專案會關閉 Xcode 的每專案前綴映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 與 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`），除非專案明確設定它們。它們的前綴（例如 `/^src`）在每個專案中指向不同的目錄，而 LLDB 僅針對被除錯目標所屬的專案來解析它們。原始碼會改為記錄在工作區範圍的前綴之下：`/^root` 代表 Tuist 根目錄，`/^spm` 代表 Swift 套件暫存目錄，而 `/^intermediates` 與 `/^products` 則代表建構產物。每個前綴在所有專案中都指向同一個目錄，因此斷點可以解析工作區中任何專案的原始碼。

Tuist 根目錄以外的路徑不會被映射。根目錄以外專案的快取金鑰取決於其檢出位置，因此其他檢出副本與機器會錯過該專案的快取。若要使其金鑰獨立於檢出位置，請在該專案的 manifest 中開啟每專案映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該 `Project`。當你除錯來自另一個專案的目標時，LLDB 將無法找到該專案的原始碼。Manifest 中的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

更改這些設定會改變編譯快取金鑰、二進位快取雜湊與選擇性測試雜湊，因此這些快取需要重新暖身。請在團隊中保持此選擇一致。

### 快取上傳政策 {#cache-upload-policy}

預設情況下，快取服務會同時下載與上傳產物至遠端快取。你可以在 `Tuist.swift` 檔案中使用 `xcodeCache` 選項來控制此行為，以啟用唯讀模式，在此模式下產物會被下載但絕不會上傳：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

常見的做法是僅從 CI 推送產物，因為那裡的建構是可重現的，同時保持本地環境為唯讀。你可以使用 `Environment.isCI` 來達成此目的，它會檢查大多數 CI 提供者設定的 `CI` 環境變數：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

透過此設定，本地建構可以受益於快取產物而無需上傳，同時 CI 建構會為團隊其他成員填充快取。

上傳政策會記錄在執行 `tuist setup cache` 的機器上，並按專案區分。若要更改它，請更新 `upload` 並再次執行 `tuist setup cache`，如果 Tuist 產生你的專案，也請執行 `tuist generate`。之後的上傳將遵循新政策，無需重新啟動該機器上的快取。在同一台機器上同時執行的相同專案工作會共用其政策，因此最近的 `tuist setup cache` 會為所有工作決定該政策。

### 儲存空間大小限制 {#store-size-limit}

編譯快取儲存空間會隨著每次建構而增長。若要限制專案的儲存空間，請在 `Tuist.swift` 檔案中設定 `storeSizeLimit`：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

當沒有建構執行時，Tuist 會每 10 分鐘檢查專案的每個儲存空間。一旦較新的建構寫入了約一半的限制容量，它就會刪除儲存空間中最舊的快取產物，使儲存空間穩定在限制容量附近。在建構執行期間，儲存空間可能大於限制容量；若在設定限制時儲存空間已經較大，則在新建構寫入足夠資料後會縮小。當多個專案使用同一個儲存空間（如預設位置所示），則適用其中最小的限制。該限制適用於你執行 `tuist setup cache` 的每一台機器，因此在更改限制後請再次執行它。

### 模組快取雜湊 {#module-cache-hashes}

編譯快取設定不屬於 <.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link> 的一部分。Tuist 會將每個 `COMPILATION_CACHE_*` 建構設定以及每個帶有值的 `-cas-plugin-option` 旗標排除在雜湊之外。開啟或關閉 `enableCaching`，或更改上傳政策，會保留你目標的雜湊，因此你已暖身的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔仍然有效。你可以針對相同的模組快取比較有與沒有 Xcode 快取的建構。

> [!NOTE]
> **前綴映射設定會被雜湊化**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true` 也會設定 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 以及 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定。這些設定屬於模組快取雜湊的一部分，因此在 Xcode 27 及更高版本中，開啟或關閉 `enableCaching` 會改變你目標的雜湊。

### 重用大型產物的部分內容 {#reusing-parts-of-large-outputs}

當伺服器支援時，Xcode 快取會以區塊形式傳輸大型產物，並僅發送或獲取自先前版本以來發生變更的區塊。區塊保存在與 `DerivedData` 分離的小型本地快取中，因此它們能在清理編譯快取後存活下來。小型產物、較舊的伺服器與較舊的用戶端則使用普通的完整產物傳輸。

這減少了下載與上傳的量，而非重新編譯的量。一台沒有匹配區塊的冷機器仍然會下載整個產物。

### 持續整合 {#continuous-integration}

若要在你的 CI 環境中啟用快取，你需要執行與本地環境相同的命令：`tuist setup cache`。

對於身分驗證，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身分驗證</.localized_link>（建議用於支援的 CI 提供者）或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。

使用 OIDC 身分驗證的 GitHub Actions 工作流程範例：
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以获取更多範例，包括基於權杖的身分驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 與 Codemagic。

### CI 上的編譯快取儲存空間 {#compilation-cache-store-on-ci}

編譯快取儲存空間是 Xcode 存放編譯產物的本地目錄。`COMPILATION_CACHE_CAS_PATH` 建構設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存空間 {#stateful-store}

若要在建構之間保留儲存空間，請將 `COMPILATION_CACHE_CAS_PATH`（以及用於 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存空間大小限制](#store-size-limit) 來限制其大小。

## 疑難排解 {#troubleshooting}

### 建構警告指出 Xcode 快取代理伺服器失敗 {#cas-proxy-failed}

如果建構顯示如下警告，Xcode 會根據哪個編譯最先遇到失敗，在前方加上 `CAS error:` 或 `CAS operation failed:` 前綴：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

這表示編譯快取無法連線到由 `tuist setup cache` 安裝的本地快取代理伺服器。建構仍然成功，但受影響的編譯無法獲得遠端快取命中，因此運作方式如同使用空快取的建構。它們的上傳內容會保留在磁碟上，並在代理伺服器再次處理請求時發送：如果在同一個建構期間恢復連線，則會在該建構稍後發送；否則會在同一台機器的下一次建構期間發送。在作業完成後即被丟棄的 CI 機器會遺失這些資料。此警告會在每次建構中出現一次，顯示於 Xcode 的 Issue navigator 以及 `xcodebuild` 輸出中。

若要檢查代理伺服器是否正在執行，請尋找監聽警告中所述 Socket 的程序：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果命令沒有輸出任何內容，請執行 `tuist setup cache` 以重新啟動代理伺服器。在 CI 上，請在每個作業中的任何 `xcodebuild` 呼叫之前執行 `tuist setup cache`。

### 建構極度緩慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建構耗時遠超預期，且 Xcode 建構日誌充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

這表示 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一個無人監聽的 Socket，通常是早期版本的 Tuist 所設定的每個專案專用 Socket（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供該 Socket 的服務。Xcode 會在每次編譯快取請求時重試連線，而非快速失敗，這可能導致建構耗時一小時或更久，而 Tuist 無法改變此行為。

要修復此問題：

- **產生的專案**：再次執行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建構設定替換為 `tuist setup cache` 印出的設定，如 [設定 Xcode 建構設定](#configure-xcode-build-settings) 中所述。

如果你未使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建構設定並執行 `tuist teardown cache`。

### 即使已停用上傳，本地仍出現 `uploaded CAS output` {#uploaded-cas-output-with-upload-disabled}

當設定為 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定為 `upload: Environment.isCI`）時，你仍可能在建構日誌中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法略過這些呼叫，因此 Tuist 仍會接收它們，但不會將任何內容發布到 Tuist 伺服器。儀表板指標已將此情況納入考量，因此不會報告虛假的上傳流量。
