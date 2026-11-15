---
{
  "title": "Xcode 快取",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "透過 Tuist 嘅 Xcode 快取整合，加快本地同 CI 上嘅 Xcode 建構速度。"
}
---
# Xcode cache {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊可以善用建構系統的快取功能來共用編譯產物。

Xcode cache 於 Xcode 26 引入。你可能也會看到它被稱為 Xcode build cache；它會根據輸入內容重用編譯產物，而 Tuist 的遠端快取則讓這些產物可以在不同機器之間共用。要了解快取移除了緩慢建構中的哪些部分，以及應該優先修正專案中的什麼問題，請參閱 [Slow builds](https://tuist.dev/solutions/slow-builds)。

> [!TIP]
> **與 module cache 搭配使用**
>
> Xcode cache 和 <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> 在不同的粒度層級運作，並互為補充。module cache 在建構執行前，以預先建置好的 `.xcframework` 取代整個模組；而 Xcode cache 則在建構期間重用編譯輸出。

> [!TIP]
> **在開發者機器上清理時，保留 `CompilationCache.noindex`**
>
> 預設情況下，編譯快取儲存區位於 `DerivedData` 內，因此刪除 `DerivedData` 會連同建構產物一併清除。在開發者機器上，建議只刪除建構產物：這樣重建時會從磁碟上的儲存區重放，無需抓取任何資料。

## Setup {#setup}

如果你還沒有 Tuist 帳戶和專案，可以執行以下指令來建立：

```bash
tuist init
```

當你擁有參考你 `fullHandle` 的 `Tuist.swift` 檔案後，可以執行以下指令來為你的專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在啟動時執行本機快取服務，供 Swift [build system](https://github.com/swiftlang/swift-build) 用來共用編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

若要在 CI 上設定快取，請確保你已<.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

### Updating the cache components {#updating-the-cache-components}

快取 proxy 使用穩定的啟動器，而非綁定到最後一次執行 setup 的 Tuist 安裝路徑。安裝後，`tuist setup cache` 和啟用快取的 `tuist generate` 會將可用的目標推進到較新的 Tuist 版本。因此，綁定到較舊 Tuist 的專案不會降級共用的 proxy。Generate 只會更新現有的啟動器目標：它不會安裝服務、進行驗證、替換外掛程式或重新啟動 proxy。自訂的外掛程式、proxy、socket 或 registry 覆寫會跳過自動推進。

運行中的 proxy 只有在至少 30 秒沒有快取請求、沒有進行中的請求或背景工作，且其發布佇列已清空的情況下，才會採用新目標。然後它會退出，launchd 會啟動選定的 CLI，保留服務的參數和憑證環境。只有實際採用目標的 proxy 才會原子性地從其 bundle 刷新磁碟上的外掛程式；setup 不會在舊 proxy 仍在清空時安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒 setup 會重新啟動選定的 proxy 以重試刷新。仍然只有一個 proxy 擁有 registry 和佇列。不可用的目標或未清空的上傳會延遲切換，而不是中斷活動請求。憑證刷新會跟隨選定的 CLI，即使在切換之前也是如此，因此移除較舊的 CLI 安裝不會導致等待清空的上傳被擱置。

在穩定啟動器之前建立的現有安裝需要一次明確的遷移。在沒有建構運行時執行以下操作：

```bash
tuist setup cache
```

遷移後，更新 Tuist 並運行你慣用的 `tuist generate` 就足以推進 proxy 和已安裝的外掛程式；你不需要為每個 CLI 版本重新運行 setup。若要選擇不同的 Xcode（包括在同一個路徑更新的 Xcode），仍然需要明確的 setup。當共享服務的配置變更時，setup 可以替換該服務，因此請先等待機器上的所有建構完成。proxy 支援之前的外掛程式協議以及當前的協議，因此已在 Xcode 中載入的相容外掛程式在 proxy 升級後仍可繼續運作。完全退出並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更生成的建構設定時，請重新生成專案。

保持選定的 Tuist 安裝可用：啟動器會使用它來進行啟動、配置和憑證刷新。一旦啟動器推進後，就可以移除較舊的安裝。如果選定的可執行檔已被刪除或不再可執行，`tuist setup cache` 可以使用可用的安裝（即使是較舊的版本）來修復目標，而無需先拆除快取。穩定的可執行檔別名在套件管理器升級期間會保留；只有在比較安裝身份時才會解析符號連結。在啟動時，proxy 會記錄實際啟動的版本，包括就地更新或故意回滾，同時保留使用的最高版本，以防止不相關的舊簽出切換可用的安裝。

沒有發行版本的原始碼建構 CLI 以及明確的 `TUIST_CAS_PLUGIN_PATH` 或 `TUIST_CAS_PROXY_PATH` 設定會使用明確的啟動配置，而不是自動版本選擇。在重建這些元件後重新運行 setup。Setup 會檢查它們的新鮮度，並僅在其替換準備好後才停用受管理的目標推進。

`tuist teardown cache` 會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可用於重新啟動和再次嘗試拆除。成功拆除後，Generate 無法重新建立服務。

### Configure Xcode Build Settings {#configure-xcode-build-settings}

對於現有的 Xcode 專案，將 `tuist setup cache` 列印的建構設定複製到專案的 Build Settings 或現有的 `.xcconfig` 檔案中。該指令會列印你帳戶的配置；它不會生成配置文件或編輯你的 Xcode 專案。在擴展 `OTHER_SWIFT_FLAGS` 時保留 `$(inherited)`，以便保留其他編譯器選項。

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

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 和 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 需要作為 **user-defined build settings** 添加，因為它們並未直接在 Xcode 的建構設定 UI 中公開。

> [!NOTE]
> **Plugin path**
>
> `libtuist_cas_plugin.dylib` 是隨 Tuist 一併提供的編譯快取外掛程式，位於 `tuist` 可執行檔旁邊。`tuist setup cache` 會將其複製到 `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而 `COMPILATION_CACHE_PLUGIN_PATH` 則指向該副本。此路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與專案一同提交。Setup 和新啟動的 proxy 會從選定的 Tuist bundle 刷新副本；從較舊的簽出運行 setup 不會降級較新的外掛程式。

> [!NOTE]
> **每個專案使用同一個 socket**
>
> `tuist setup cache` 會在每台機器上安裝單一快取 proxy，因此每個專案都使用相同的 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance` 外掛程式選項用於識別專案。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 是用來共用 C 和 Objective-C 的設定**
>
> 很容易將此設定解讀為「快取服務的位置」並視為可選。它也是決定是否共用 C、Objective-C、預編譯模組和預編譯標頭檔的開關：只有在配置了遠端快取服務時，建構系統才會對這些內容執行快取。如果省略此設定，Swift 編譯仍會共用，但在任何未曾建構過該專案的機器上，每個 C/Objective-C 檔案和每個模組都會重新編譯。

> [!NOTE]
> **並行快取查詢**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會讓建構系統為每次編譯執行的遠端快取查詢與其餘建構工作並行執行，而不是在建構的執行通道上一次只處理少數幾個。對於從遠端快取錯過或還原大量編譯的建構，完成時間會更短。

你也可以在運行 `xcodebuild` 時透過添加以下標誌來指定這些設定，例如：

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
> 在 Xcode 27 及更高版本中，`tuist setup cache` 還會列印 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING` 和 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它們使編譯快取鍵值獨立於專案和 `DerivedData` 所在的位置。將它們添加為 user-defined build settings。啟用它們會改變每個快取鍵值，因此下一次建構會再次填充快取。當 `enableCaching` 開啟時，`tuist generate` 會為你設定這些值。
>
> 編譯器還會將映射後的路徑寫入程式碼涵蓋率資料中，而 Xcode 無法解析這些路徑，因此涵蓋率報告會遺漏所有使用前綴映射編譯的原始碼。列印的設定以及 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 相關設定，會在收集程式碼涵蓋率的建構中關閉前綴映射。`tuist generate` 也會執行相同操作。這些建構仍會使用編譯快取，但其快取鍵值取決於專案和 `DerivedData` 路徑。
>
> 當你在命令列將這些設定傳遞給 `xcodebuild` 時，請對包含 `$(...)` 的值使用單引號，如同上面的 `OTHER_SWIFT_FLAGS` 一樣。否則 shell 會將它們擴展為空字串，導致前綴映射被關閉：
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
> **生成的專案**
>
> 如果你的專案是由 Tuist 生成的，則無需手動設定這些設定。
>
> 在這種情況下，你只需在 `Tuist.swift` 檔案中添加 `enableCaching: true`：
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

預設情況下，生成的專案會為涵蓋率建構禁用前綴映射，以保持 Xcode 的涵蓋率報告和 `xccov` 正常運作。你可以啟用它，以便在不同簽出之間共用涵蓋率編譯：

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

`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）的優先級高於 `prefixMapping`。此選項適用於 Xcode 27 及更高版本，且需要 `enableCaching`。涵蓋率 `tuist test` 上傳支援此功能：Tuist 使用 `llvm-cov` 測量運行情況，后者讀取具有映射路徑的原始碼，並將它們關聯回你儲存庫中的檔案。Xcode 自身的涵蓋率報告和 `xccov` 仍可能遺漏這些原始碼，如果 `llvm-cov` 匯出失敗，回落至結果 bundle 的 `xccov` 報告的上傳也可能遺漏它們。映射的 `#filePath` 值也可能影響相對於原始碼檔案定位 fixture 的測試；請改為透過明確的運行時簽出路徑來解析 fixture。如果你自行處理涵蓋率，請將每個插樁後的二進位檔與其目標的 `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` 配對，后者將虛擬前綴映射回本地目錄。當啟用每專案映射時，請勿對每個二進位檔重複使用同一個目標的映射。

涵蓋率前綴設定會參與二進位快取和選擇性測試的雜湊計算，因為它們控制寫入涵蓋率產物的路徑。更改此選項或以不同方式設定 `TUIST_COVERAGE_PREFIX_MAPPING`，即使對於普通建構也會使這些雜湊無效。如果開發者和 CI 工作應共用二進位快取和選擇性測試結果，請保持該值一致。

### 除錯生成的專案 {#debugging-generated-projects}

還原的原生模組需要連結的除錯資訊以及對編譯快取的存取權限。Tuist 會使用 dSYM 和每切片原始碼身份元數據來預熱 Debug 和 Release 模組，然后在替換目標之前，根據消費者聲明的原始碼驗證元數據。缺少或不兼容的元數據會保留該目標的原始碼。腳本生成的 `.generated(...)` 原始碼擁有聲明指紋而非可驗證的內容雜湊，因此這些目標保持原始碼建構狀態，且不會發布到原生模組快取。具有實際內容雜湊的生成資源訪問器仍然符合資格。不受支援的除錯資訊會跳過受影響目標的發布，而不會阻塞不相關的產品；原始碼變異和取消仍會導致預熱失敗。快取格式已更改，因此由較舊版本預熱的產物需要重新預熱。

對於已驗證的替換，Tuist 會在消費者擁有的 dSYM UUID plists 中準備原始碼重定位，並為靜態快取代碼連結僅除錯用的 companion。它不會重寫快取的二進位檔，也不會在 LLDB 的持久全域原始碼地圖中安裝生產者原始碼路徑。明確的除錯器初始化器和模組載入器設定仍然具有權威性。除錯符號和原始碼重定位不會修復相對於原始碼的運行時檔案訪問或原生 Xcode 涵蓋率報告；涵蓋率變體選擇和 LLVM 匯出仍然是獨立的功能。

啟用 `enableCaching: true` 時，Tuist 會為 Run 和 Test 動作設定 LLDB 原始碼地圖。如果某個動作有自訂的 LLDB 初始化器，Tuist 會先寫入已解析的原始碼地圖，然後載入該自訂初始化器，以便它可以擴展或覆蓋地圖。否則，它會在替換原始碼地圖之前載入 `~/.lldbinit-Xcode`（如果檔案存在），否則回退到 `~/.lldbinit`。它只載入一個主目錄檔案，恢復每個用戶的除錯器設定而不會重複載入。替換會移除先前運行中的過時映射，並優先於主目錄檔案的原始碼地圖；將應該保留的原始碼地圖條目放在動作的自訂初始化器中。其他主目錄設定會被保留。Tuist 的快取特定模組搜尋路徑、載入器設定和 Clang 標誌隨後應用，並優先於這些設定的用戶值。主目錄檔案錯誤仍然可見，不會阻止後續命令載入，且命令不會被回顯。這種初始化器保留也適用於 Tuist 為從模組快取還原的二進位檔設定除錯時，即使沒有 `enableCaching` 或在較早的 Xcode 版本上也是如此。

在 Xcode 27 及更高版本中，生成的專案會關閉 Xcode 的每專案前綴映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 和 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`），除非專案明確設定它們。它們的前綴（例如 `/^src`）在每個專案中命名不同的目錄，而 LLDB 僅針對被除錯目標的專案解析它們。原始碼改為記錄在工作區範圍的前綴下：`/^root` 代表 Tuist 根目錄，`/^spm` 代表 Swift 套件暫存目錄，`/^intermediates` 和 `/^products` 代表建構輸出。每個前綴在所有專案中都指向同一個目錄，因此斷點可以解析工作區中任何專案的原始碼。

Tuist 根目錄之外的路徑不會被映射。根目錄外專案的快取鍵取決於其檢出位置，因此其他檢出和機器會錯過其快取。為了使其鍵獨立於檢出位置，請在該專案的 manifest 中開啟每專案映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該 `Project`。當你除錯來自另一個專案的目標時，LLDB 將無法找到該專案的原始碼。Manifest 的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

更改這些設定會改變編譯快取鍵、二進位快取雜湊和選擇性測試雜湊，因此這些快取需要重新預熱。請在團隊中保持此選擇一致。

### 快取上傳策略 {#cache-upload-policy}

預設情況下，快取服務既下載又上傳產物到遠端快取。你可以透過 `Tuist.swift` 檔案中的 `xcodeCache` 選項來控制此行為，以啟用唯讀模式，在此模式下產物會被下載但不會上傳：

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

常見的模式是僅從 CI 推送產物，因為那裡的建構是可重現的，同時保持本地環境為唯讀。你可以使用 `Environment.isCI` 來實現這一點，它會檢查大多數 CI 提供者設定的 `CI` 環境變數：

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

透過此設定，本地建構可以受益於快取產物而無需上傳，而 CI 建構則為團隊的其他成員填充快取。

上傳策略記錄在執行 `tuist setup cache` 的機器上，按專案區分。要更改它，請更新 `upload` 並再次執行 `tuist setup cache`，如果 Tuist 生成你的專案，也要執行 `tuist generate`。之後的上傳將遵循新策略，無需重新啟動該機器上的快取。在同一台機器上同時運行的相同專案的工作共用其策略，因此最近的 `tuist setup cache` 決定所有工作的策略。

### 儲存大小限制 {#store-size-limit}

編譯快取儲存會隨著每次建構而增長。要限制專案的儲存，請在你的 `Tuist.swift` 檔案中設定 `storeSizeLimit`：

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

Tuist 在其快取代理啟動時檢查專案的每個儲存（在任何建構使用它們之前），並且在沒有建構運行時每 10 分鐘檢查一次。`tuist setup cache` 會在代理未運行時啟動它，因此在建構之前執行 `tuist setup cache` 並在之後執行 `tuist teardown cache` 的 CI 工作會在每個工作開始時限制長期運行者的儲存。一旦較新的建構寫入了大約一半的限制容量，它就會刪除儲存中最舊的快取輸出，因此儲存會穩定在大約限制的大小。在建構運行期間，儲存可能會大於限制，而當你設定限制時已經較大的儲存會在新建構寫入那麼多容量後縮小。當多個專案使用同一個儲存（如預設位置那樣）時，適用其中最小的限制。該限制適用於你執行 `tuist setup cache` 的每台機器，因此在更改限制後請再次執行它。已經運行的快取代理會繼續運行，并在下次檢查時應用新限制。

### 模組快取雜湊 {#module-cache-hashes}

編譯快取設定不屬於 <.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link> 的一部分。Tuist 將每個 `COMPILATION_CACHE_*` 建構設定以及每個帶有值的 `-cas-plugin-option` 標誌排除在雜湊之外。開啟或關閉 `enableCaching`，或更改上傳策略，會保持你目標的雜湊不變，因此你已經預熱的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔仍然有效。你可以針對相同的模組快取比較有和沒有 Xcode 快取的建構。

> [!NOTE]
> **前綴映射設定會被雜湊**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true` 還會設定 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 和 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定。這些設定是模組快取雜湊的一部分，因此在 Xcode 27 及更高版本中，開啟或關閉 `enableCaching` 會改變你目標的雜湊。

### 重用大型輸出的部分 {#reusing-parts-of-large-outputs}

當伺服器支援時，Xcode 快取會以塊為單位傳輸大型輸出，並且只發送或獲取自早期版本以來發生變化的塊。塊保存在一個小型本地快取中，與 `DerivedData` 分開，因此它們在清理編譯快取後仍然存在。小型輸出、較舊的伺服器和較舊的客戶端使用普通的完整輸出傳輸。

這減少了下載和上傳的量，而不是重新編譯的量。沒有匹配塊的冷機器仍然會下載整個輸出。

### 持續整合 {#continuous-integration}

要在你的 CI 環境中啟用快取，你需要運行與本地環境相同的命令：`tuist setup cache`。

進行身份驗證時，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份驗證</.localized_link>（推薦用於支援的 CI 供應商）或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。

以下是使用 OIDC 身份驗證的 GitHub Actions 工作流程範例：
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

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以查看更多範例，包括基於令牌的身份驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的編譯快取儲存 {#compilation-cache-store-on-ci}

編譯快取儲存是 Xcode 存放編譯輸出的本地目錄。`COMPILATION_CACHE_CAS_PATH` 建構設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存 {#stateful-store}

若要在建構之間保留儲存，請將 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存大小限制](#store-size-limit) 來限制其大小。

## 疑難排解 {#troubleshooting}

### 建構警告指出 Xcode 快取代理失敗 {#cas-proxy-failed}

如果建構顯示如下警告，Xcode 會根據哪個編譯首先遇到失敗，在其前面加上 `CAS error:` 或 `CAS operation failed:`：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

這表示編譯快取無法連接到由 `tuist setup cache` 安裝的本地快取代理。建構仍然成功，但受影響的編譯沒有獲得遠端快取命中，因此其運行方式如同空快取的建構。它們的上傳內容會保留在磁碟上，並在代理再次處理請求時發送：如果在同一建構中及時恢復，則在該建構的稍後階段發送；否則在下一台相同機器上的建構期間發送。作業結束後被丟棄的 CI 機器會遺失這些內容。警告會在每次建構中出現一次，位於 Xcode 的問題導航器和 `xcodebuild` 輸出中。

要檢查代理是否正在運行，請查找監聽警告中命名套接字的進程：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果命令沒有輸出任何內容，請運行 `tuist setup cache` 以重新啟動代理。在 CI 上，請在每個作業中的任何 `xcodebuild` 調用之前運行 `tuist setup cache`。

### 建構極慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建構花費的時間遠超預期，且 Xcode 建構日誌充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

這表示 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向了一個無人監聽的套接字，通常是 Tuist 早期版本配置的每專案套接字（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供該套接字服務。Xcode 會在每次編譯快取請求時重試連接，而不是快速失敗，這可能導致建構耗時一小時或更久，而 Tuist 無法改變此行為。

要修復此問題：

- **生成的專案**：再次運行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建構設定替換為 `tuist setup cache` 打印的設定，如 [配置 Xcode 建構設定](#configure-xcode-build-settings) 中所述。

如果你未使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建構設定並運行 `tuist teardown cache`。

### `uploaded CAS output` 在本地出現，儘管上傳已禁用 {#uploaded-cas-output-with-upload-disabled}

當設定 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定 `upload: Environment.isCI`）時，你仍可能在建構日誌中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法跳過這些調用，因此 Tuist 仍然會接收它們，但不會向 Tuist 伺服器發布任何內容。儀表板指標已考慮此情況，因此不會報告虛假的上傳流量。

## 相關 {#related}

探索 [Tuist 的共享快取](https://tuist.dev/cache)，了解工程團隊和編碼代理如何重用建構產物。
