---
{
  "title": "Xcode 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的 Xcode 快取整合，加速本機與 CI 上的 Xcode 建置。"
}
---
# Xcode 快取 {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊能利用建置系統的快取能力，共享編譯產物。

Xcode 快取於 Xcode 26 引入。你也可能看到它被稱為 Xcode 建置快取；它會根據輸入內容鍵入並重複使用編譯產物，而 Tuist 的遠端快取讓這些產物能在不同機器間共享。若要了解它與 DerivedData 和 Clang 模組快取的關係，請參閱 <.localized_link href="/references/concepts/build-cache#xcode">什麼是 Xcode 快取？</.localized_link>。若要找出快取能消除慢速建置的哪個部分，以及專案中應優先修正的事項，請參閱 [慢速建置](https://tuist.dev/solutions/slow-builds)。

> [!TIP]
> **與模組快取搭配使用**
>
> Xcode 快取與 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 在不同粒度層級運作，並互為補充。模組快取在建置執行前，以預先建置的 `.xcframework` 取代整個模組；而 Xcode 快取則在建置期間重複使用編譯輸出。

> [!TIP]
> **在開發者機器上清理時，保留 `CompilationCache.noindex`**
>
> 預設情況下，編譯快取儲存區位於 `DerivedData` 內，因此刪除 `DerivedData` 會連同建置產物一併移除。在開發者機器上，建議僅刪除建置產物：重新建置時會從磁碟上的儲存區重放，無需抓取任何資料。

## 設定 {#setup}

如果你尚未擁有 Tuist 帳號與專案，可以執行以下指令來建立：

```bash
tuist init
```

一旦你擁有參考你的 `fullHandle` 的 `Tuist.swift` 檔案，就可以執行以下指令為專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在啟動時執行本機快取服務，供 Swift [建置系統](https://github.com/swiftlang/swift-build) 用來共享編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

若要在 CI 上設定快取，請確保你已 <.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

### 更新快取元件 {#updating-the-cache-components}

快取代理程式使用穩定的啟動器，而非綁定至最後一次執行設定的 Tuist 安裝路徑。安裝後，`tuist setup cache` 與啟用快取的 `tuist generate` 會將可用的目標推進至較新的 Tuist 版本。因此，綁定至較舊 Tuist 的專案不會降級共享的代理程式。產生作業僅更新現有的啟動器目標：它不會安裝服務、進行驗證、取代外掛程式，或重新啟動代理程式。自訂的外掛程式、代理程式、Socket 或 Registry 覆寫會略過自動推進。

執行中的代理程式僅在至少 30 秒內沒有快取請求、沒有進行中的請求或背景工作，且其發布佇列已排空後，才會採用新目標。隨後它會退出，launchd 會啟動所選的 CLI，並保留服務的引數與憑證環境。只有實際採用目標的代理程式會以原子方式從其套件刷新磁碟上的外掛程式；在較舊的代理程式仍在排空期間，設定不會安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒設定會重新啟動所選的代理程式以重試刷新。仍然只有一個代理程式擁有 Registry 與佇列。目標不可用或未排空的上傳會延遲切換，而非中斷進行中的請求。憑證刷新會在切換之前就跟随所選的 CLI，因此移除較舊的 CLI 安裝不會使等待排空的上傳陷入孤立。

在穩定啟動器之前建立的現有安裝需要一次明確的遷移。在沒有建置執行時執行以下指令：

```bash
tuist setup cache
```

完成該遷移後，更新 Tuist 並執行你慣用的 `tuist generate` 就足以推進代理程式與已安裝的外掛程式；你不需要為每個 CLI 版本重新執行設定。若要選擇不同的 Xcode（包括在同一路徑更新的 Xcode），仍需要明確設定。當共用服務的設定變更時，設定可以取代該服務，因此請先等待機器上的所有建置完成。代理程式同時支援先前的外掛程式協定與目前的協定，因此已在 Xcode 中載入的相容外掛程式在代理程式升級後仍可繼續運作。完全關閉並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更產生的建置設定時，請重新產生專案。

保持所選的 Tuist 安裝可用：啟動器會使用它來進行啟動、設定與憑證刷新。一旦啟動器已推進，即可移除較舊的安裝。如果所選的可執行檔已被刪除或不再可執行，`tuist setup cache` 可以使用可用的安裝（即使是較舊的版本）修復目標，而無需先拆除快取。穩定的可執行檔別名在套件管理器升級期間會保留；僅在比較安裝身分時才會解析符號連結。在啟動時，代理程式會記錄實際啟動的版本，包括就地更新或刻意回滾，同時保留最高版本，以防止不相關的較舊檢出切換至可用的安裝。

沒有發行版本且明確設定 `TUIST_CAS_PLUGIN_PATH` 或 `TUIST_CAS_PROXY_PATH` 的原始碼建置 CLI 會使用明確的啟動設定，而非自動版本選擇。在重建這些元件後，請重新執行設定。設定會檢查它們的新鮮度，並僅在其替代品就緒後才停用受管理的目標推進。

`tuist teardown cache` 會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可供重新啟動與再次嘗試拆除。成功拆除後，產生作業無法重新建立服務。

### 設定 Xcode 建置設定 {#configure-xcode-build-settings}

對於現有的 Xcode 專案，請將 `tuist setup cache` 印出的建置設定複製到專案的「Build Settings」或現有的 `.xcconfig` 檔案中。該指令會印出你帳號的設定；它不會產生設定檔或編輯你的 Xcode 專案。在擴充 `OTHER_SWIFT_FLAGS` 時請保留 `$(inherited)`，以確保其他編譯器選項得以保留。

設定包含：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 與 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 需要作為 **使用者定義的建置設定** 加入，因為它們並未直接在 Xcode 的建置設定 UI 中公開。

> [!NOTE]
> **外掛程式路徑**
>
> `libtuist_cas_plugin.dylib` 是隨 Tuist 附送的編譯快取外掛程式，位於 `tuist` 可執行檔旁。`tuist setup cache` 會將其複製到 `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而 `COMPILATION_CACHE_PLUGIN_PATH` 則指向該副本。此路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與專案一起提交。設定程序與新啟動的代理程式會從所選的 Tuist 套件刷新該副本；從較舊的檢出版本執行設定不會降級較新的外掛程式。

> [!NOTE]
> **每個專案使用一個 Socket**
>
> `tuist setup cache` 會在每台機器上安裝單一快取代理程式，因此每個專案都使用相同的 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance` 外掛程式選項用於識別專案。
>
> Xcode 僅將 `OTHER_SWIFT_FLAGS` 傳遞給 Swift 編譯器，不會傳遞給其建置系統自行執行的快取查詢。這些查詢會從同一建置中的 Swift 編譯器選項得知專案資訊。`tuist build`、`tuist test` 與 `tuist xcodebuild` 也會直接將專案傳遞給它們。若專案不含 Swift 程式碼且採用其他方式建置（例如直接使用 `xcodebuild` 或 Xcode App），可以在 Socket 路徑後方加入專案：`COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock?tuist-instance=your-org/your-project`。否則，在快取代理程式尚未見過該專案的機器上（例如在作業之間重設的 CI 機器），首次建置可能會重新編譯部分已快取的檔案。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 負責共用 C 與 Objective-C**
>
> 很容易將此設定解讀為「快取服務的位置」並視為可選。它也是決定是否共用 C、Objective-C、預先編譯模組與預先編譯標頭檔的開關：只有在設定遠端快取服務時，建置系統才會對這些項目執行快取。若不設定，Swift 編譯仍會共用，但在任何尚未建置過該專案的機器上，每個 C/Objective-C 檔案與每個模組都會重新編譯。

> [!NOTE]
> **並行快取查詢**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會讓建置系統針對每次編譯執行的遠端快取查詢與其餘建置作業並行執行，而非在建置的執行通道上一次只處理少數查詢。當大量編譯從未命中或從遠端快取還原時，建置會更快完成。

你也可以在執行 `xcodebuild` 時透過加入下列旗標來指定這些設定，例如：

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
> **Xcode 27 及更新版本的前綴對應**
>
> 在 Xcode 27 及更新版本中，`tuist setup cache` 也會印出 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING` 與 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它們讓編譯快取金鑰獨立於專案與 `DerivedData` 所在的路徑。請將它們新增為使用者定義的建置設定。啟用它們會改變每個快取金鑰，因此下一次建置會再次填充快取。當 `enableCaching` 開啟時，`tuist generate` 會為你設定這些值。
>
> 編譯器也會將對應後的路徑寫入程式碼涵蓋率資料中，而 Xcode 無法解析這些路徑，因此涵蓋率報告會省略所有使用前綴對應編譯的原始碼。印出的設定以及 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 相關設定，會在收集程式碼涵蓋率的建置中關閉前綴對應。`tuist generate` 也會執行相同操作。這些建置仍會使用編譯快取，但其快取金鑰取決於專案與 `DerivedData` 路徑。
>
> 當你在命令列將這些設定傳遞給 `xcodebuild` 時，請對包含 `$(...)` 的值使用單引號括住，如同上方的 `OTHER_SWIFT_FLAGS`。否則 Shell 會將它們展開為空字串，導致前綴對應被關閉：
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
> 若你的專案由 Tuist 產生，則無需手動設定這些設定。
>
> 在此情況下，你只需在 `Tuist.swift` 檔案中加入 `enableCaching: true`：
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

### 使用前綴對應的涵蓋率 {#coverage-with-prefix-mapping}

預設情況下，產生的專案會為涵蓋率建置停用前綴對應，以確保 Xcode 的涵蓋率報告與 `xccov` 正常運作。你可以啟用它，讓涵蓋率編譯在不同檢出之間可共用：

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

`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）優先於 `prefixMapping`。此選項適用於 Xcode 27 及更新版本，且需要 `enableCaching`。涵蓋率 `tuist test` 上傳支援此功能：Tuist 使用 `llvm-cov` 測量執行結果，它會讀取具有對應路徑的原始碼，並將其綁定回你儲存庫中的檔案。Xcode 自身的涵蓋率報告與 `xccov` 仍可能省略這些原始碼；若 `llvm-cov` 匯出失敗而上傳退回至結果套件的 `xccov` 報告，也可能省略這些原始碼。對應後的 `#filePath` 值也可能影響相對於原始碼檔案定位測試固定資料的測試；請改為透過明確的執行期檢出路徑來解析固定資料。若你自行處理涵蓋率，請將每個插樁二進位檔與其目標的 `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` 配對，該檔案會將虛擬前綴對應回本機目錄。當啟用每專案對應時，請勿將單一目標的對應表重複用於每個二進位檔。

涵蓋率前綴設定會參與二進位快取與選擇性測試的雜湊計算，因為它們控制寫入涵蓋率產物的路徑。變更此選項或以不同方式設定 `TUIST_COVERAGE_PREFIX_MAPPING`，即使對於一般建置也會使這些雜湊失效。若開發人員與 CI 作業應共用二進位快取與選擇性測試結果，請保持該值一致。

### 偵錯產生的專案 {#debugging-generated-projects}

還原的原生模組需要連結的除錯資訊以及存取編譯快取。Tuist 會使用 dSYM 與每切片原始碼身分中繼資料來暖身 Debug 與 Release 模組，然後在取代目標之前，根據消費者宣告的原始碼驗證中繼資料。若缺少或不相容的中繼資料，則會保留該目標的原始碼。指令碼產生的 `.generated(...)` 原始碼具有宣告指紋，而非可驗證的內容雜湊，因此這些目標會保持從原始碼建置，且不會發布至原生模組快取。具有實際內容雜湊的產生資源存取子仍符合資格。不支援的除錯資訊會跳過受影響目標的發布，而不會封鎖無關的產品；原始碼突變與取消仍會導致暖身失敗。快取格式已變更，因此由較舊版本暖身的產物需要重新暖身。

針對已驗證的取代，Tuist 會在消費者擁有的 dSYM UUID plist 中準備原始碼重新定位，並為靜態快取程式碼連結僅供除錯使用的伴隨檔案。它不會重寫快取的二進位檔，也不會在 LLDB 的持久全域原始碼對應表中安裝生產者原始碼路徑。明確的除錯器初始化器與模組載入器設定仍具有最高優先權。在 CI 環境中（當設定 `CI` 或 `JENKINS_URL` 時），執行此操作的方案預先動作會直接結束且不進行任何變更，因為在該環境中沒有除錯器附加至測試。除錯符號與原始碼重新定位無法修復相對於原始碼的執行時期檔案存取或原生 Xcode 涵蓋率報告；涵蓋率變體選擇與 LLVM 匯出仍是獨立的功能。

使用 `enableCaching: true` 時，Tuist 會為「執行」與「測試」動作設定 LLDB 原始碼對應表。當某個動作擁有自訂 LLDB 初始化器時，Tuist 會先寫入其解析後的原始碼對應表，然後載入自訂初始化器，使其能夠擴充或覆寫該對應表。否則，它會在取代原始碼對應表之前，若檔案存在則載入 `~/.lldbinit-Xcode`，否則回退至 `~/.lldbinit`。它僅載入一個主目錄檔案，以恢復每位使用者的除錯器設定，避免重複載入。此取代會移除先前執行留下的過時對應，並優先於主目錄檔案中的原始碼對應；請將需要保留的原始碼對應項目放在動作的自訂初始化器中。其他主目錄設定則會保留。Tuist 的快取專用模組搜尋路徑、載入器設定與 Clang 旗標隨後套用，並優先於使用者對這些設定的值。主目錄檔案的錯誤仍會顯示，但不會阻止後續命令載入，且命令不會被回顯。即使未使用 `enableCaching` 或在較舊的 Xcode 版本上，當 Tuist 為從模組快取還原的二進位檔設定除錯時，此初始化器保留機制同樣適用。

在 Xcode 27 及更新版本中，除非專案明確設定，否則產生的專案會關閉 Xcode 的每專案前綴對應（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 與 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`）。它們的前綴（例如 `/^src`）在每個專案中指向不同的目錄，而 LLDB 僅針對被除錯目標所屬的專案來解析它們。相反地，原始碼會記錄在工作區範圍的前綴之下：`/^root` 代表 Tuist 根目錄，`/^spm` 代表 Swift 套件暫存目錄，而 `/^intermediates` 與 `/^products` 則代表建置產物。由於每個前綴在所有專案中都指向相同的目錄，因此中斷點可以正確解析工作區中任何專案的原始碼。

Tuist 根目錄之外的路徑不會被對應。位於根目錄之外的專案，其快取金鑰取決於檢出位置，因此其他檢出版本與機器將無法命中該專案的快取。若要使其金鑰獨立於檢出位置，請在該專案的 manifest 中開啟每專案對應：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該 `Project`。當你除錯來自另一個專案的目標時，LLDB 將無法找到該專案的原始碼。Manifest 中的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

變更這些設定會改變編譯快取金鑰、二進位快取雜湊與選擇性測試雜湊，因此這些快取需要重新暖身。請在團隊中保持一致的選擇。

### 快取上傳政策 {#cache-upload-policy}

預設情況下，快取服務會同時下載與上傳產物至遠端快取。你可以透過 `Tuist.swift` 檔案中的 `xcodeCache` 選項來控制此行為，以啟用唯讀模式，在此模式下會下載產物但絕不上傳：

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

常見的做法是僅從 CI 推送產物，因為那裡的建置是可複現的，同時保持本地環境為唯讀。你可以使用 `Environment.isCI` 來達成此目的，它會檢查大多數 CI 供應商設定的 `CI` 環境變數：

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

透過此設定，本地建置可以受益於快取產物而無須上傳，同時 CI 建置會為團隊其他成員填充快取。

上傳政策會記錄在執行 `tuist setup cache` 的機器上，並以專案為單位。若要變更它，請更新 `upload` 並再次執行 `tuist setup cache`，如果 Tuist 會產生你的專案，也請執行 `tuist generate`。之後的上傳將遵循新政策，無須在該機器上重新啟動快取。在同一台機器上同時執行的同一專案作業會共用其政策，因此最近的 `tuist setup cache` 會為所有作業決定該政策。

### 儲存空間大小限制 {#store-size-limit}

編譯快取儲存空間會隨著每次建置而成長。若要限制專案的儲存空間，請在你的 `Tuist.swift` 檔案中設定 `storeSizeLimit`：

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

Tuist 會在快取代理啟動時（在任何建置使用它們之前）檢查專案的每個儲存空間，並在沒有建置執行期間每 10 分鐘檢查一次。`tuist setup cache` 會在代理未執行時啟動它，因此若在建置前執行 `tuist setup cache` 並在之後執行 `tuist teardown cache` 的 CI 作業，會在每個作業開始時限制長期存在之執行器的儲存空間。當較新的建置寫入約一半的限制容量後，它會刪除儲存空間中最舊的快取產物，使儲存空間穩定在接近限制的大小。在建置執行期間，儲存空間可能會超過限制；而當你在設定限制時儲存空間已經較大，一旦新建置寫入足夠多的資料，它就會縮小。當多個專案共用同一個儲存空間（如同其預設位置的情況），則適用其中最小的限制。該限制適用於你執行 `tuist setup cache` 的每一台機器，因此在變更限制後請再次執行它。已經執行的快取代理會繼續執行，並在其下次檢查時套用新限制。

### 模組快取雜湊 {#module-cache-hashes}

編譯快取設定不屬於 <.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link> 的一部分。Tuist 會將每個 `COMPILATION_CACHE_*` 建置設定，以及每個帶有值的 `-cas-plugin-option` 旗標排除在雜湊之外。開啟或關閉 `enableCaching`，或變更上傳政策，會保留你目標的雜湊，因此你已經暖身的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔仍然有效。你可以針對相同的模組快取，比較有與沒有 Xcode 快取的建置。

> [!NOTE]
> **前綴對應設定會被雜湊化**
>
> 在 Xcode 27 及更新版本中，`enableCaching: true` 也會設定 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 以及 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定。這些設定屬於模組快取雜湊的一部分，因此在 Xcode 27 及更新版本中，開啟或關閉 `enableCaching` 會改變你目標的雜湊。

### 重用大型產物的部分內容 {#reusing-parts-of-large-outputs}

當伺服器支援時，Xcode 快取會以區塊方式傳輸大型產物，並僅傳送或抓取自先前版本以來變更的區塊。這些區塊儲存在一個小型本機快取中，與 `DerivedData` 分開，因此即使在清理編譯快取後仍會保留。小型產物、較舊的伺服器以及較舊的用戶端則使用一般的完整產物傳輸。

這能減少下載和上傳的資料量，而非減少重新編譯的量。一台沒有相符區塊的冷啟動機器仍然會下載整個產物。

### 持續整合 {#continuous-integration}

若要在你的 CI 環境中啟用快取，你需要執行與本機環境相同的指令：`tuist setup cache`。

對於身分驗證，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 驗證</.localized_link>（建議用於支援的 CI 供應商）或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。

以下是使用 OIDC 驗證的 GitHub Actions 工作流程範例：
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

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得更多範例，包括基於權杖的驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的編譯快取儲存空間 {#compilation-cache-store-on-ci}

編譯快取儲存空間是 Xcode 存放編譯產物的本機目錄。`COMPILATION_CACHE_CAS_PATH` 建置設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存空間 {#stateful-store}

若要在建置之間保留儲存空間，請將 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存空間大小限制](#store-size-limit) 來限制其大小。

## 疑難排解 {#troubleshooting}

### 建置警告指出 Xcode 快取代理失敗 {#cas-proxy-failed}

如果建置顯示如下警告，Xcode 會根據哪個編譯首先遇到失敗，在其前方加上 `CAS error:` 或 `CAS operation failed:` 前綴：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

這表示編譯快取無法連線到由 `tuist setup cache` 安裝的本機快取代理。建置仍然成功，但受影響的編譯無法命中遠端快取，因此其行為如同使用空快取的建置。它們的上傳內容會保留在磁碟上，並在代理再次處理請求時發送：如果在同一個建置期間及時恢復，則會在該建置稍後階段發送；否則會在同一台機器的下一次建置期間發送。作業結束後被丟棄的 CI 機器將會遺失這些資料。該警告在每次建置中出現一次，顯示於 Xcode 的問題導覽器和 `xcodebuild` 輸出中。

若要檢查代理是否正在執行，請尋找監聽警告中所述 Socket 的程序：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果該指令沒有印出任何內容，請執行 `tuist setup cache` 以重新啟動代理。在 CI 上，請在每個作業中的任何 `xcodebuild` 呼叫之前執行 `tuist setup cache`。

### 建置極度緩慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建置花費的時間遠超過預期，且 Xcode 建置記錄充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

這表示 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一個無人監聽的 Socket，通常是 Tuist 早期版本設定的每個專案 Socket（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供該 Socket。Xcode 會在每次編譯快取請求時重試連線，而不是快速失敗，這可能導致建置耗時一小時或更久，而 Tuist 無法改變此行為。

若要修正此問題：

- **產生的專案**：再次執行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建置設定替換為 `tuist setup cache` 所印出的設定，如 [設定 Xcode 建置設定](#configure-xcode-build-settings) 中所述。

如果你未使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建置設定並執行 `tuist teardown cache`。

### `uploaded CAS output` 在本機出現，即使已停用上傳 {#uploaded-cas-output-with-upload-disabled}

當設定 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定 `upload: Environment.isCI`）時，你仍可能在建置記錄中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法略過這些呼叫，因此 Tuist 仍然會接收它們，但不會將任何內容發布至 Tuist 伺服器。儀表板指標已考慮此情況，因此不會報告虛假的上傳流量。

## 相關資訊 {#related}

探索 [Tuist 的共用快取](https://tuist.dev/cache)，了解工程團隊和編碼代理如何重用建置產物。
