---
{
  "title": "Xcode 快取",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "透過 Tuist 嘅 Xcode 快取整合，加快本地同 CI 上嘅 Xcode 建構速度。"
}
---
# Xcode 快取 {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊可以善用建構系統的快取功能，共用編譯產物。

Xcode 快取於 Xcode 26 引入。你也可能看到它被稱為 Xcode 建構快取；它會根據輸入內容重用已鍵入的編譯產物，而 Tuist 的遠端快取讓這些產物可以在不同機器之間共用。

> [!TIP]
> **與模組快取搭配使用**
>
> Xcode 快取與<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>在不同粒度層級運作，並互相補足。模組快取在建構執行前以預先建置的`.xcframework`取代整個模組，而 Xcode 快取則在建構期間重用編譯輸出。

> [!TIP]
> **在開發者機器上清理時保留`CompilationCache.noindex`**
>
> 預設情況下，編譯快取儲存區位於`DerivedData`內，因此刪除`DerivedData`會連同建構產物一起清除。在開發者機器上，建議只刪除建構產物：重新建構時會從磁碟上的儲存區重放，無需抓取任何內容。

## 設定 {#setup}

如果你尚未擁有 Tuist 帳戶和專案，可以執行以下指令來建立：

```bash
tuist init
```

當你擁有參考你的`fullHandle`的`Tuist.swift`檔案後，可以執行以下指令為專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在啟動時執行本機快取服務，供 Swift [建構系統](https://github.com/swiftlang/swift-build)用來共用編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

若要在 CI 上設定快取，請確保你已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

### 更新快取元件 {#updating-the-cache-components}

快取代理程式使用穩定的啟動器，而非綁定到上次執行設定的 Tuist 安裝路徑。安裝後，`tuist setup cache`與啟用快取的`tuist generate`會將可用的目標推進至較新的 Tuist 版本。因此，綁定到較舊 Tuist 的專案不會降級共用的代理程式。產生作業只會更新現有的啟動器目標：它不會安裝服務、進行驗證、取代外掛程式或重新啟動代理程式。自訂的外掛程式、代理程式、通訊端或註冊表覆寫會跳過自動推進。

執行中的代理程式只會在至少 30 秒沒有快取請求、沒有進行中的請求或背景工作，且其發布佇列已排空後，才會採用新目標。然後它會退出，launchd 會啟動選定的 CLI，並保留服務的參數和憑證環境。只有實際採用目標的代理程式會以原子方式從其套件刷新磁碟上的外掛程式；在舊代理程式仍在排空時，設定不會安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒設定會重新啟動選定的代理程式以重試刷新。仍然只有一個代理程式擁有註冊表和佇列。目標不可用或上傳未排空會延遲切換，而不是中斷進行中的請求。憑證刷新會跟隨選定的 CLI，甚至在切換之前，因此移除較舊的 CLI 安裝不會導致等待排空的上傳被擱置。

在穩定啟動器之前建立的現有安裝需要一次明確的遷移。在沒有建構執行時執行以下指令：

```bash
tuist setup cache
```

遷移後，更新 Tuist 並執行你慣用的`tuist generate`就足以推進代理程式和已安裝的外掛程式；你不需要為每個 CLI 版本重新執行設定。若要選擇不同的 Xcode（包括在同一路徑更新的 Xcode），仍需要明確設定。當設定變更時，設定可以取代共用服務，因此請先等待機器上的所有建構完成。代理程式同時支援先前和目前的外掛程式協定，因此已在 Xcode 中載入的相容外掛程式在代理程式升級後仍可繼續運作。完全退出並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更產生的建構設定時，請重新產生專案。

保持所選的 Tuist 安裝可用：啟動器會使用它進行啟動、設定和憑證刷新。一旦啟動器已推進，就可以移除較舊的安裝。如果所選的可執行檔已被刪除或不再可執行，`tuist setup cache`可以使用可用的安裝（甚至是較舊的版本）修復目標，而無需先拆除快取。穩定的可執行檔別名在套件管理器升級期間會保留；符號連結僅在比較安裝身份時才會解析。在啟動時，代理程式會記錄實際啟動的版本，包括就地更新或刻意回滾，同時保留使用的最高版本，以防止無關的舊檢出切換可用的安裝。

沒有發行版本且明確設定`TUIST_CAS_PLUGIN_PATH`或`TUIST_CAS_PROXY_PATH`的原始碼建構 CLI 會使用明確的啟動設定，而非自動版本選擇。重建這些元件後請重新執行設定。設定會檢查它們的新鮮度，並僅在其替換準備就緒後才停用受管理的目標推進。

`tuist teardown cache`會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可供重新啟動和再次嘗試拆除。成功拆除後，產生作業無法重新建立服務。

### 設定 Xcode 建構設定 {#configure-xcode-build-settings}

對於現有的 Xcode 專案，請將`tuist setup cache`輸出的建構設定複製到專案的「Build Settings」或現有的`.xcconfig`檔案中。該指令會輸出你帳戶的設定；它不會產生設定檔或編輯你的 Xcode 專案。在擴充`OTHER_SWIFT_FLAGS`時請保留`$(inherited)`，以便保留其他編譯器選項。

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

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`和`COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`需要作為**使用者定義的建構設定**新增，因為它們未在 Xcode 的建構設定 UI 中直接公開。

> [!NOTE]
> **外掛程式路徑**
>
> `libtuist_cas_plugin.dylib`是隨 Tuist 一起提供的編譯快取外掛程式，位於`tuist`可執行檔旁邊。`tuist setup cache`將其複製到`$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而`COMPILATION_CACHE_PLUGIN_PATH`指向該副本。該路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與專案一起提交。設定和新啟動的代理程式會從所選的 Tuist 套件刷新副本；從較舊的檢出執行設定不會降級較新的外掛程式。

> [!NOTE]
> **每個專案使用同一個 Socket**
>
> `tuist setup cache`在每台機器上安裝單一快取代理程式，因此每個專案都使用相同的`COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance`外掛程式選項用於識別專案。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`負責共用 C 和 Objective-C**
>
> 很容易將此設定解讀為「快取服務所在位置」並視為可選。它也是決定是否共用 C、Objective-C、預編譯模組和預編譯標頭檔的開關：只有在設定遠端快取服務時，建構系統才會對這些項目執行快取。省略它仍然可以共用 Swift 編譯，但在任何尚未建構過該專案的機器上，每個 C/Objective-C 檔案和每個模組都會重新編譯。

> [!NOTE]
> **並行快取查詢**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`會在建構期間同時執行建構系統為每次編譯發出的遠端快取查詢，而不是在建構的執行通道上分批進行。從遠端快取錯過或還原大量編譯的建構會更快完成。

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
> **Xcode 27 及更高版本的前綴映射**
>
> 在 Xcode 27 及更高版本中，`tuist setup cache`還會輸出`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`和`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它們使編譯快取金鑰獨立於專案和`DerivedData`的位置。將它們新增為使用者定義的建構設定。啟用它們會改變每個快取金鑰，因此下一次建構會再次填充快取。當`enableCaching`開啟時，`tuist generate`會為你設定它們。
>
> 編譯器也會將映射路徑寫入程式碼涵蓋率資料中，而 Xcode 無法解析它們，因此涵蓋率報告會遺漏所有使用前綴映射編譯的原始碼。輸出的設定以及`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`設定會在收集程式碼涵蓋率的建構中關閉前綴映射。`tuist generate`也會執行相同操作。這些建構仍然使用編譯快取，但其快取金鑰取決於專案和`DerivedData`路徑。
>
> 當你在命令列將這些設定傳遞給`xcodebuild`時，請用單引號括住包含`$(...)`的值，如同上面的`OTHER_SWIFT_FLAGS`。否則 Shell 會將它們展開為空字串，從而關閉前綴映射：
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
> 如果你的專案由 Tuist 產生，則無需手動設定這些設定。
>
> 在這種情況下，你只需在`Tuist.swift`檔案中新增`enableCaching: true`：
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

### 帶前綴映射的涵蓋率 {#coverage-with-prefix-mapping}

預設情況下，產生的專案會為涵蓋率建構停用前綴映射，以保持 Xcode 的涵蓋率報告和`xccov`正常運作。你可以啟用它，以便在不同檢出之間共用涵蓋率編譯：

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

`TUIST_COVERAGE_PREFIX_MAPPING`環境變數（`1`或`0`）優先於`prefixMapping`。此選項適用於 Xcode 27 及更高版本，且需要`enableCaching`。涵蓋率`tuist test`上傳支援此功能：Tuist 使用`llvm-cov`測量執行過程，它會讀取帶有映射路徑的原始碼，並將它們與你的儲存庫檔案關聯起來。Xcode 自身的涵蓋率報告和`xccov`仍可能遺漏這些原始碼，如果`llvm-cov`匯出失敗，回退到結果套件的`xccov`報告的上傳也可能遺漏它們。映射的`#filePath`值也可能影響相對於原始碼檔案定位測試夾具的測試；請改為透過明確的執行階段檢出路徑解析夾具。如果你自行處理涵蓋率，請將每個檢測過的二進位檔與其目標的`$(TARGET_TEMP_DIR)/compilation-prefix-map.json`配對，後者將虛擬前綴映射回本機目錄。當啟用每專案映射時，請勿為每個二進位檔重複使用同一個目標的映射。

涵蓋率前綴設定會參與二進位快取和選擇性測試的雜湊計算，因為它們控制寫入涵蓋率產物的路徑。更改此選項或以不同方式設定`TUIST_COVERAGE_PREFIX_MAPPING`會使這些雜湊失效，即使是普通建構也是如此。如果開發者和 CI 工作應該共用二進位快取和選擇性測試結果，請保持該值一致。

### 偵錯產生的專案 {#debugging-generated-projects}

還原的原生模組需要連結的偵錯資訊以及存取編譯快取的權限。Tuist 會使用 dSYM 和每個切片來源身份元數據來暖化 Debug 和 Release 模組，然後在替換目標之前根據消費者聲明的來源驗證元數據。缺少或不兼容的元數據會保留該目標的來源。腳本產生的`.generated(...)`來源具有宣告指紋而非可驗證的內容校驗和，因此這些目標保持來源建構狀態，不會發布到原生模組快取。具有實際內容校驗和的產生資源存取器仍然符合資格。不支援的偵錯資訊會跳過受影響目標的發布，而不會阻擋無關的產品；來源變異和取消仍會導致暖化失敗。快取格式已變更，因此由較舊版本暖化的產物需要重新暖化。

對於已驗證的替換，Tuist 會在消費者擁有的 dSYM UUID plist 中準備來源重定位，並為靜態快取代碼連結僅偵錯用的伴隨檔案。它不會重寫快取的二進位檔或在 LLDB 的持久全域來源地圖中安裝生產者來源路徑。明確的偵錯器初始化器和模組載入器設定仍然具有權威性。偵錯符號和來源重定位不會修復相對於來源的執行階段檔案存取或原生 Xcode 涵蓋率報告；涵蓋率變體選擇和 LLVM 匯出仍然是獨立的功能。

啟用`enableCaching: true`後，Tuist 會為 Run 和 Test 動作設定 LLDB 來源地圖。如果某個動作有自訂的 LLDB 初始化器，Tuist 會先寫入已解析的來源地圖，然後載入該自訂初始化器，以便擴充或覆寫地圖。否則，它會在替換來源地圖之前，先載入`~/.lldbinit-Xcode`（如果檔案存在），並回退到`~/.lldbinit`。它只載入一個主目錄檔案，恢復每個使用者的偵錯器設定，避免重複載入。替換操作會移除先前執行留下的過時映射，並優先於主目錄檔案中的來源地圖；將需要保留的來源地圖條目放在動作的自訂初始化器中。其他主目錄設定會被保留。Tuist 的快取專用模組搜尋路徑、載入器設定和 Clang 旗標會在之後應用，並優先於這些設定的使用者值。主目錄檔案錯誤仍然可見，不會阻止後續命令載入，且命令不會被回顯。即使沒有`enableCaching`或在較早版本的 Xcode 上，當 Tuist 為從模組快取還原的二進位檔設定偵錯時，此初始化器保留機制同樣適用。

在 Xcode 27 及更高版本中，產生的專案會關閉 Xcode 的每個專案前綴映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`和`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`），除非專案明確設定它們。它們的前綴（例如`/^src`）在每個專案中指代不同的目錄，而 LLDB 僅針對被偵錯目標所屬的專案來解析它們。相反，來源會記錄在工作區範圍的前綴下：`/^root`代表 Tuist 根目錄，`/^spm`代表 Swift 套件暫存目錄，而`/^intermediates`和`/^products`代表建構輸出。每個前綴在所有專案中都指向同一個目錄，因此斷點可以解析工作區中任何專案的來源。

Tuist 根目錄之外的路徑不會被映射。根目錄外專案的快取鍵取決於其檢出位置，因此其他檢出位置和機器無法命中其快取。若要使其鍵獨立於檢出位置，請在該專案的 manifest 中開啟每個專案的映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該`Project`。當你偵錯來自另一個專案的目標時，LLDB 將無法找到該專案的來源。Manifest 中的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

更改這些設定會改變編譯快取鍵、二進位快取雜湊和選擇性測試雜湊，因此這些快取需要重新暖化。請在團隊中保持此選擇一致。

### 快取上傳策略 {#cache-upload-policy}

預設情況下，快取服務會同時下載和上傳產物到遠端快取。你可以透過`Tuist.swift`檔案中的`xcodeCache`選項來控制此行為，以啟用唯讀模式，在該模式下只會下載產物而不會上傳：

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

常見的做法是僅從 CI 推送產物，因為那裡的建構是可重現的，同時保持本地環境為唯讀。你可以使用`Environment.isCI`來實現這一點，它會檢查大多數 CI 提供者設定的`CI`環境變數：

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

透過此設定，本地建構可以受益於快取產物而無需上傳，而 CI 建構則會為團隊其他成員填充快取。

上傳策略會記錄在執行`tuist setup cache`的機器上，按專案區分。若要更改它，請更新`upload`並再次執行`tuist setup cache`，如果 Tuist 產生你的專案，也請執行`tuist generate`。之後的上傳將遵循新策略，無需重新啟動該機器上的快取。在同一台機器上同時運行的同一專案的工作共享其策略，因此最近的`tuist setup cache`決定所有工作的策略。

### 儲存大小限制 {#store-size-limit}

編譯快取儲存會隨著每次建構而增長。若要限制專案的儲存大小，請在`Tuist.swift`檔案中設定`storeSizeLimit`：

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

當沒有建構運行時，Tuist 每 10 分鐘檢查一次專案的每個儲存。一旦較新的建構寫入了約一半的限制容量，它就會刪除儲存中最舊的快取輸出，使儲存穩定在限制大小附近。在建構運行期間，儲存可能會超過限制；如果你在設定限制時儲存已經較大，一旦新建構寫入足夠多的數據，儲存就會縮小。當多個專案使用同一個儲存（如預設位置那樣）時，適用最小的限制。該限制適用於你執行`tuist setup cache`的每台機器，因此在更改限制後請再次執行它。

### 模組快取雜湊 {#module-cache-hashes}

編譯快取設定不屬於<.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link>的一部分。Tuist 會將每個 `COMPILATION_CACHE_*` 建置設定，以及每個帶有值的 `-cas-plugin-option` 旗標，排除在雜湊計算之外。開啟或關閉 `enableCaching`，或更改上傳政策，都會保留你目標的雜湊值，因此你已經暖化的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>二進位檔仍然有效。你可以針對相同的模組快取，比較有和沒有 Xcode 快取的建構結果。

> [!NOTE]
> **前綴映射設定會被雜湊**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true`還會設定`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`以及`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`設定。這些設定是模組快取雜湊的一部分，因此在 Xcode 27 及更高版本中，開啟或關閉`enableCaching`會改變你目標的雜湊。

### 重用大型輸出的部分內容 {#reusing-parts-of-large-outputs}

Xcode 快取可以透過內容定義的分塊來減少傳輸量。它不會將每個大型輸出視為與早期版本無關，而是根據其內容在邊界處分割壓縮後的輸出。編輯後，即使偏移量發生變化，匹配的區塊也可以被重用。

上傳僅發送伺服器缺少的區塊。下載首先獲取精確的快取動作和輸出的區塊配方，然後重用儲存在本地機器上的已驗證區塊並獲取缺失的部分。完整的重建輸出在還原到編譯器快取之前會經過驗證。

傳輸區塊快取與`DerivedData`分開，因此其區塊可以在清理編譯快取或重新啟動本地快取服務後仍然存在。它是可丟棄的，區塊負載上限為 1 GiB，另有一個最多 2 MiB 的臨時暫存檔案。被驅逐或損壞的區塊會在需要時重新下載。保留編譯快取本身仍然比重建其內容更快。

用戶端僅在伺服器宣告支援相容功能時，才會使用分塊傳輸。較舊的用戶端仍可讀取完整輸出，而連線至較舊或不支援伺服器的用戶端則保留一般傳輸。小型輸出仍沿用現有的完整輸出路徑。

這會減少傳輸位元組數，但不會減少編譯器失效。更改原始碼檔案可能仍需編譯；分塊有助於發布或還原產生的輸出。節省量取決於輸出內容和編輯情況，而沒有匹配區塊的全新機器必須下載所有輸出。

### 持續整合 {#continuous-integration}

若要在 CI 環境中啟用快取，你需要執行與本地環境相同的指令：`tuist setup cache`。

對於驗證，你可以使用<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>（建議用於支援的 CI 供應商），或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。

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

請參閱<.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link>以查看更多範例，包括基於權杖的驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的編譯快取儲存區 {#compilation-cache-store-on-ci}

編譯快取儲存區是 Xcode 存放編譯輸出的本機目錄。`COMPILATION_CACHE_CAS_PATH` 建置設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存區 {#stateful-store}

若要在建構之間保留儲存區，請將 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存區大小限制](#store-size-limit) 來限制其大小。

## 疑難排解 {#troubleshooting}

### 建構警告指出 Xcode 快取代理失敗 {#cas-proxy-failed}

如果建構顯示如下警告，Xcode 會根據哪個編譯最先遇到失敗，在前方加上 `CAS error:` 或 `CAS operation failed:` 前綴：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

這表示編譯快取無法連線到由 `tuist setup cache` 安裝的本機快取代理。建構仍然成功，但受影響的編譯無法獲得遠端快取命中，因此其運作方式如同空快取的建構。它們的上傳內容會保留在磁碟上，並在代理再次處理請求時發送：如果在同一建構期間及時恢復，則在該建構稍後階段發送；否則會在同一機器的下一次建構期間發送。作業結束後被丟棄的 CI 機器會遺失這些資料。警告會在每次建構中出現一次，顯示在 Xcode 的問題導覽器和 `xcodebuild` 輸出中。

若要檢查代理是否正在執行，請尋找監聽警告中所述 Socket 的處理程序：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果指令沒有輸出任何內容，請執行 `tuist setup cache` 以重新啟動代理。在 CI 上，請在每個作業中的任何 `xcodebuild` 呼叫之前執行 `tuist setup cache`。

### 建構速度極慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建構時間遠超預期，且 Xcode 建構日誌充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

這表示 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一個無人監聽的 Socket，通常是早期版本的 Tuist 設定的每個專案 Socket（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供該 Socket 服務。Xcode 會在每次編譯快取請求時重試連線，而不是快速失敗，這可能導致建構耗時一小時或更久，而 Tuist 無法更改此行為。

要修復此問題：

- **產生的專案**：再次執行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建置設定替換為 `tuist setup cache` 印出的設定，如 [設定 Xcode 建置設定](#configure-xcode-build-settings) 中所述。

如果你沒有使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建置設定並執行 `tuist teardown cache`。

### 即使已停用上傳，本地仍出現 `uploaded CAS output` {#uploaded-cas-output-with-upload-disabled}

當設定 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定 `upload: Environment.isCI`）時，你仍可能在建構日誌中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法跳過這些呼叫，因此 Tuist 仍會接收它們，但不會向 Tuist 伺服器發布任何內容。儀表板指標已考慮此情況，因此不會報告虛假的上傳流量。
