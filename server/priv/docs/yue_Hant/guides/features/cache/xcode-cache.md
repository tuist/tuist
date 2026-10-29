---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Speed up Xcode builds locally and on CI with Tuist's Xcode cache integration."
}
---
# Xcode 快取 {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊能夠利用建置系統的快取功能來共享編譯產物。

Xcode 快取於 Xcode 26 中引入。你也可能看到它被稱為 Xcode 建置快取；它會根據輸入內容重用編譯產物，而 Tuist 的遠端快取讓這些產物可以在不同機器之間共享。

> [!TIP]
> **與模組快取搭配使用**
>
> Xcode 快取和<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>在不同粒度層級上運作並相輔相成。模組快取在建置執行前以預先建置的`.xcframework`取代整個模組，而 Xcode 快取則在建置期間重用編譯輸出。

> [!TIP]
> **在開發者機器上，清理時保留`CompilationCache.noindex`**
>
> 預設情況下，編譯快取儲存區位於`DerivedData`內，因此刪除`DerivedData`會連同建置產物一起將其移除。在開發者機器上，建議只刪除建置產物：重新建置時會從磁碟上的儲存區重播，無需抓取任何內容。

## 設定 {#setup}

如果你還沒有 Tuist 帳戶和專案，可以透過執行以下指令來建立：

```bash
tuist init
```

一旦你擁有參考你的`fullHandle`的`Tuist.swift`檔案，就可以透過執行以下指令為你的專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，以便在啟動時執行本機快取服務，Swift [建置系統](https://github.com/swiftlang/swift-build)會使用該服務來共享編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

若要在 CI 上設定快取，請確保你已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

### 更新快取元件 {#updating-the-cache-components}

快取代理程式使用穩定的啟動器，而非固定到上次執行設定的 Tuist 安裝路徑。安裝後，`tuist setup cache`和啟用快取的`tuist generate`會將可用目標推進到較新的 Tuist 版本。因此，固定到較舊 Tuist 的專案不會降級共享代理程式。產生僅更新現有的啟動器目標：它不會安裝服務、進行驗證、替換外掛程式或重新啟動代理程式。自訂外掛程式、代理程式、通訊端或註冊表覆寫會跳過自動推進。

執行中的代理程式只有在至少 30 秒沒有快取請求、沒有進行中的請求或背景工作，且其發布佇列已排空的情況下，才會採用新目標。然後它會退出，launchd 會啟動所選的 CLI，保留服務的參數和憑證環境。只有實際採用目標的代理程式會原子性地從其套件刷新磁碟上的外掛程式；當較舊的代理程式仍在排空時，設定不會安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒設定會重新啟動所選代理程式以重試刷新。仍然只有一個代理程式擁有註冊表和佇列。不可用的目標或未排空的上傳會延遲切換，而不是中斷活動請求。憑證刷新會在切換之前就跟隨所選的 CLI，因此移除較舊的 CLI 安裝不會導致等待排空的上傳被擱置。

在穩定啟動器之前建立的現有安裝需要一次明確的遷移。在沒有建置執行時執行以下操作：

```bash
tuist setup cache
```

遷移後，更新 Tuist 並執行你平常的`tuist generate`就足以推進代理程式和已安裝的外掛程式；你不需要為每個 CLI 版本重新執行設定。若要選擇不同的 Xcode（包括在同一路徑更新的 Xcode），仍然需要明確設定。當共用服務的組態變更時，設定可以替換該服務，因此請先等待機器上的所有建置完成。代理程式支援先前的外掛程式協定以及目前的協定，因此已在 Xcode 中載入的相容外掛程式在代理程式升級後仍可繼續運作。完全退出並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更產生的建置設定時，請重新產生專案。

保持所選的 Tuist 安裝可用：啟動器會使用它來啟動、組態和刷新憑證。一旦啟動器推進後，就可以移除較舊的安裝。如果所選的可執行檔已被刪除或不再可執行，`tuist setup cache`可以使用可用的安裝（甚至是較舊的版本）修復目標，而無需先拆除快取。穩定的可執行檔別名在套件管理器升級期間會保留；符號連結僅在比較安裝身分時才會解析。在啟動時，代理程式會記錄實際啟動的版本，包括就地更新或刻意回滾，同時保留使用的最高版本，以防止不相關的較舊檢出切換可用的安裝。

沒有發行版本且明確設定`TUIST_CAS_PLUGIN_PATH`或`TUIST_CAS_PROXY_PATH`的原始碼建置 CLI 會使用明確的啟動組態，而非自動版本選擇。重建這些元件後請重新執行設定。設定會檢查它們的新鮮度，並僅在其替換品準備好後才停用受管理的目標推進。

`tuist teardown cache`會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可供重新啟動和再次嘗試拆除。成功拆除後，產生無法重新建立服務。

### 組態 Xcode 建置設定 {#configure-xcode-build-settings}

對於現有的 Xcode 專案，請將`tuist setup cache`輸出的建置設定複製到專案的「Build Settings」或現有的`.xcconfig`檔案中。該指令會輸出你帳戶的組態；它不會產生組態檔案或編輯你的 Xcode 專案。在擴充`OTHER_SWIFT_FLAGS`時請保留`$(inherited)`，以便保留其他編譯器選項。

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

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`和`COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`需要作為**使用者定義的建置設定**新增，因為它們並未直接在 Xcode 的建置設定 UI 中公開。

> [!NOTE]
> **外掛程式路徑**
>
> `libtuist_cas_plugin.dylib`是隨 Tuist 一起提供的編譯快取外掛程式，位於`tuist`可執行檔旁邊。`tuist setup cache`將其複製到`$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而`COMPILATION_CACHE_PLUGIN_PATH`指向該副本。該路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與你的專案一起提交。設定和新啟動的代理程式會從所選的 Tuist 套件刷新副本；從較舊的檢出執行設定不會降級較新的外掛程式。

> [!NOTE]
> **每個專案一個 Socket**
>
> `tuist setup cache`會在每台機器上安裝單一快取代理程式，因此每個專案都使用相同的`COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance`外掛程式選項是用來識別專案的。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`是共用 C 和 Objective-C 的關鍵**
>
> 很容易將此設定解讀為「快取服務的位置」並視為可選。它也是決定是否共用 C、Objective-C、預編譯模組和預編譯標頭檔的開關：只有在組態了遠端快取服務時，建置系統才會為這些項目執行快取。如果省略它，你仍然可以共用 Swift 編譯，但在任何尚未建置過該專案的機器上，每個 C/Objective-C 檔案和每個模組都會重新編譯。

> [!NOTE]
> **並行快取查詢**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`會與建置的其他部分同時執行建置系統為每次編譯進行的遠端快取查詢，而不是在建置的執行通道上一次只執行幾個。從遠端快取錯過或還原許多編譯的建效能更快完成。

你也可以在執行`xcodebuild`時透過新增以下旗標來指定這些設定，例如：

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
> **Xcode 27 及更新版本的前綴映射**
>
> 在 Xcode 27 及更新版本中，`tuist setup cache`也會輸出`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`和`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它們讓編譯快取金鑰獨立於專案和`DerivedData`所在的位置。將它們新增為使用者定義的建置設定。啟用它們會改變每個快取金鑰，因此下一次建工會再次填充快取。當`enableCaching`開啟時，`tuist generate`會為你設定它們。
>
> 編譯器也會將映射的路徑寫入程式碼涵蓋率資料中，而 Xcode 無法解析它們，因此涵蓋率報告會遺漏所有使用前綴映射編譯的原始碼。輸出的設定以及`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`設定，會在收集程式碼涵蓋率的建置中關閉前綴映射。`tuist generate`也會執行相同操作。這些建置仍然使用編譯快取，但它們的快取金鑰取決於專案和`DerivedData`路徑。
>
> 當你在命令列將這些設定傳遞給`xcodebuild`時，請用單引號括住包含`$(...)`的值，如同上面的`OTHER_SWIFT_FLAGS`。否則 shell 會將它們展開為空字串，並關閉前綴映射：
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
> 在這種情況下，你只需要在`Tuist.swift`檔案中新增`enableCaching: true`：
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

### 使用前綴映射的涵蓋率{#coverage-with-prefix-mapping}

預設情況下，產生的專案會為涵蓋率建置停用前綴映射，以保持 Xcode 的涵蓋率報告和`xccov`正常運作。你可以啟用它，以便在不同檢出之間共用涵蓋率編譯：

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

`TUIST_COVERAGE_PREFIX_MAPPING`環境變數（`1`或`0`）優先於`prefixMapping`。此選項適用於 Xcode 27 及更新版本，且需要`enableCaching`。涵蓋率`tuist test`上傳支援此功能：Tuist 使用`llvm-cov`測量執行，它會讀取具有映射路徑的原始碼，並將它們綁定回你的儲存庫檔案。Xcode 自身的涵蓋率報告和`xccov`仍可能遺漏這些原始碼，如果因`llvm-cov`匯出失敗而回退到結果套件的`xccov`報告，上傳也可能遺漏它們。映射的`#filePath`值也可能影響相對於原始碼檔案定位測試裝置的測試；請改為透過明確的執行階段檢出路徑來解析測試裝置。如果你自行處理涵蓋率，請將每個檢測過的二進位檔與其目標的`$(TARGET_TEMP_DIR)/compilation-prefix-map.json`配對，後者將虛擬前綴映射回本機目錄。當啟用每專案映射時，請勿為每個二進位檔重複使用同一個目標的映射。

涵蓋率前綴設定會參與二進位快取和選擇性測試的雜湊，因為它們控制寫入涵蓋率產物的路徑。更改此選項或以不同方式設定`TUIST_COVERAGE_PREFIX_MAPPING`，即使對於普通建置也會使這些雜湊失效。如果開發人員和 CI 工作應該共用二進位快取和選擇性測試結果，請保持該值一致。

### 偵錯產生的專案{#debugging-generated-projects}

還原的原生模組需要連結的偵錯資訊以及存取編譯快取。Tuist 會使用 dSYM 和每個切片的原始碼身分元數據來暖身 Debug 和 Release 模組，然後在替換目標之前根據消費者宣告的原始碼驗證元數據。缺少或不兼容的元數據會保留該目標的原始碼。腳本產生的`.generated(...)`原始碼具有宣告指紋而非可驗證的內容總和檢查碼，因此這些目標保持原始碼建置狀態，不會發布到原生模組快取。具有實際內容總和檢查碼的產生資源存取器仍然符合資格。不支援的偵錯資訊會跳過受影響目標的發布，而不會阻塞不相關的產品；原始碼突變和取消仍然會導致暖身失敗。快取格式會改變，因此由較舊版本暖身的產物需要重新暖身。

對於已驗證的替換，Tuist 會在消費者擁有的 dSYM UUID plist 中準備原始碼重定位，並為靜態快取代碼連結僅供偵錯使用的伴侶。它不會重寫快取的二進位檔或在 LLDB 的持久全域原始碼地圖中安裝生產者原始碼路徑。明確的偵錯器初始化器和模組載入器設定仍然具有權威性。偵錯符號和原始碼重定位不會修復相對於原始碼的執行階段檔案存取或原生 Xcode 涵蓋率報告；涵蓋率變體選擇和 LLVM 匯出仍然是獨立的功能。

啟用`enableCaching: true`時，Tuist 會為 Run 和 Test 動作設定 LLDB 原始碼地圖。當某個動作有自訂的 LLDB 初始化器時，Tuist 會先寫入已解析的原始碼地圖，然後載入該自訂初始化器，以便它可以擴充或覆寫地圖。否則，它會在替換原始碼地圖之前，如果檔案存在則載入`~/.lldbinit-Xcode`，否則回退至`~/.lldbinit`。它只會載入一個主目錄檔案，在不重複載入的情況下恢復每位使用者的偵錯器設定。替換會移除先前執行中過時的映射，並優先於主目錄檔案的原始碼地圖；將應該保留的原始碼地圖項目放在動作的自訂初始化器中。其他主目錄設定會被保留。Tuist 的快取專用模組搜尋路徑、載入器設定和 Clang 標誌會在之後應用，並優先於這些設定的使用者值。主目錄檔案錯誤仍然可見，不會阻止後續命令載入，且命令不會被回顯。即使沒有`enableCaching`或在較早的 Xcode 版本上，當 Tuist 為從模組快取還原的二進位檔設定偵錯時，此初始化器保留機制也適用。

在 Xcode 27 及更高版本中，產生的專案會關閉 Xcode 的每個專案前綴映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`和`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`），除非專案明確設定它們。它們的前綴（例如`/^src`）在每個專案中指代不同的目錄，而 LLDB 僅針對被偵錯目標的專案來解析它們。原始碼會改為記錄在工作區範圍的前綴下：`/^root`代表 Tuist 根目錄，`/^spm`代表 Swift 套件暫存目錄，而`/^intermediates`和`/^products`代表建置輸出。每個前綴在所有專案中都指代相同的目錄，因此斷點可以解析工作區中任何專案的原始碼。

Tuist 根目錄之外的路徑不會被映射。根目錄之外專案的快取金鑰取決於其檢出位置，因此其他檢出和機器會錯過其快取。為了使其金鑰獨立於檢出位置，請在該專案的 manifest 中開啟每個專案的映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該`Project`。當你偵錯來自另一個專案的目標時，LLDB 將無法找到該專案的原始碼。Manifest 中的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

更改這些設定會改變編譯快取金鑰、二進位快取雜湊和選擇性測試雜湊，因此這些快取需要重新暖身。請在團隊中保持一致的選擇。

### 快取上傳策略{#cache-upload-policy}

預設情況下，快取服務會同時下載和上傳產物到遠端快取。你可以透過`Tuist.swift`檔案中的`xcodeCache`選項來控制此行為，以啟用唯讀模式，在該模式下產物會被下載但不會上傳：

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

一種常見的模式是僅從 CI 推送產物，因為那裡的建置是可重現的，同時保持本地環境為唯讀。你可以使用`Environment.isCI`來實現這一點，它會檢查大多數 CI 提供者設定的`CI`環境變數：

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

透過此設定，本地建置可以受益於快取產物而無須上傳，而 CI 建置則會為團隊的其他成員填充快取。

上傳策略會記錄在執行`tuist setup cache`的機器上，每個專案一份。要更改它，請更新`upload`並再次執行`tuist setup cache`，如果 Tuist 產生你的專案，也要執行`tuist generate`。之後的上傳將遵循新策略，無需在該機器上重新啟動快取。在同一台機器上同時執行的同一專案的工作共用其策略，因此最近的`tuist setup cache`決定所有工作的策略。

### 儲存大小限制{#store-size-limit}

編譯快取儲存會隨著每次建置而成長。為了限制專案的儲存，請在你的`Tuist.swift`檔案中設定`storeSizeLimit`：

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

當沒有建置正在執行時，Tuist 每 10 分鐘檢查一次專案的每個儲存。一旦較新的建置寫入了約一半的限制量，它就會刪除儲存中最舊的快取輸出，因此儲存會穩定在約限制的大小。在建置執行期間，儲存可能會大於限制，而當你設定限制時已經較大的儲存，一旦新建置寫入足夠的量就會縮小。當多個專案使用相同的儲存（如同其預設位置所做的那樣）時，適用其中最小的限制。該限制適用於你執行`tuist setup cache`的每台機器，因此在更改限制後請再次執行它。

### 模組快取雜湊{#module-cache-hashes}

編譯快取設定不屬於<.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link>。Tuist 會將每個 `COMPILATION_CACHE_*` 建置設定，以及每個帶有值的 `-cas-plugin-option` 旗標排除在雜湊之外。開啟或關閉 `enableCaching`，或更改上傳政策，會保留你目標的雜湊，因此你已經暖身的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔仍然有效。你可以針對同一個模組快取比較有和沒有 Xcode 快取的建置。

> [!NOTE]
> **前綴映射設定會被雜湊**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true`也會設定`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`以及`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`設定。這些設定是模組快取雜湊的一部分，因此在 Xcode 27 及更高版本中，開啟或關閉`enableCaching`會改變你目標的雜湊。

### 重用大型輸出的部分{#reusing-parts-of-large-outputs}

Xcode 快取可以透過內容定義分塊來減少傳輸量。它不會將每個大型輸出視為與早期版本無關，而是根據其內容在邊界處分割壓縮輸出。編輯後，即使偏移量已改變，也可以重用匹配的區塊。

上傳僅發送伺服器缺少的區塊。下載首先獲取確切的快取動作和輸出的區塊配方，然後重用儲存在本地機器上的已驗證區塊並獲取缺失的部分。完整的重建輸出在還原到編譯器快取之前會經過驗證。

傳輸區塊快取與`DerivedData`分開，因此其區塊可以在清理編譯快取或重新啟動本地快取服務後存活。它是可丟棄的，並且區塊負載最多限制為一 gibibyte，另有一個最多兩 mebibyte 的臨時暫存檔案。被驅逐或損壞的區塊在需要時會再次下載。保留編譯快取本身仍然比重建其內容更快。

用戶端僅在伺服器宣告支援相容性時才使用分塊傳輸。較舊的用戶端仍可讀取完整輸出，而連線到較舊或不支援伺服器的用戶端則保留一般傳輸。小型輸出仍沿用現有的完整輸出路徑。

這會減少傳輸位元組數，但不會減少編譯器失效。更改原始檔可能仍需編譯；分塊有助於發布或還原產生的輸出。節省量取決於輸出和編輯內容，而沒有匹配區塊的冷啟動機器必須下載所有輸出。

### 持續整合 {#continuous-integration}

若要在你的 CI 環境中啟用快取，你需要執行與本地環境相同的指令：`tuist setup cache`。

對於驗證，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>（建議用於支援的 CI 供應商）或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。

使用 OIDC 驗證的 GitHub Actions 工作流程範例：
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

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以获取更多範例，包括基於權杖的驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的編譯快取儲存區 {#compilation-cache-store-on-ci}

編譯快取儲存區是 Xcode 存放編譯輸出的本機目錄。`COMPILATION_CACHE_CAS_PATH` 建置設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存區 {#stateful-store}

若要在建置之間保留儲存區，請將 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存區大小限制](#store-size-limit) 限制其大小。

## 疑難排解 {#troubleshooting}

### 建置警告指出 Xcode 快取代理失敗 {#cas-proxy-failed}

如果建置顯示如下警告，Xcode 會根據哪個編譯首先遇到失敗，在其前面加上 `CAS error:` 或 `CAS operation failed:`：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

那麼編譯快取無法連接到 `tuist setup cache` 安裝的本機快取代理。建置仍然成功，但受影響的編譯沒有遠端快取命中，因此它的運行方式就像具有空快取的建置一樣。它們的上傳會保留在磁碟上，並在代理再次處理請求時發送：如果在同一個建置中及時恢復，則在該建置的稍後階段發送，否則在同一台機器的下一次建置期間發送。作業結束後被丟棄的 CI 機器會遺失這些資料。警告會在每次建置中出現一次，位於 Xcode 的問題導覽器和 `xcodebuild` 輸出中。

若要檢查代理是否正在運行，請查找監聽警告中命名之套接字的進程：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果指令沒有列印任何內容，請運行 `tuist setup cache` 以重新啟動代理。在 CI 上，請在每個作業中的任何 `xcodebuild` 調用之前運行 `tuist setup cache`。

### 建置極慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建置時間遠超預期，且 Xcode 建置日誌充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

那麼 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一個無人監聽的套接字，通常是 Tuist 早期版本設定的每個專案套接字 (`~/.local/state/tuist/<org>_<project>.sock`)。Tuist 不再提供該套接字服務。Xcode 會在每次編譯快取請求時重試連接，而不是快速失敗，這可能會使建置耗時一小時或更久，而 Tuist 無法更改此行為。

要修復它：

- **生成的專案**：再次運行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建置設定替換為 `tuist setup cache` 列印的設定，如 [設定 Xcode 建置設定](#configure-xcode-build-settings) 中所述。

如果你未使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建置設定並運行 `tuist teardown cache`。

### 即使上傳已禁用，`uploaded CAS output` 仍在本機出現 {#uploaded-cas-output-with-upload-disabled}

當設定 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定 `upload: Environment.isCI`）時，你仍可能在建置日誌中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法跳過這些調用，因此 Tuist 仍會接收它們，但它不會向 Tuist 伺服器發布任何內容。儀表板指標已考慮此情況，因此不會報告虛假的上傳流量。
