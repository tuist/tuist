---
{
  "title": "Xcode 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 Xcode 快取整合，加快本地同 CI 上嘅 Xcode 建置速度。"
}
---
# Xcode 快取 {#xcode-cache}

Tuist 支援 Xcode 編譯快取，讓團隊可以利用建置系統的快取功能共用編譯產物。

Xcode 快取於 Xcode 26 引入。你也可能見到它被稱為 Xcode 建置快取；它會根據輸入鍵重用編譯產物，而 Tuist 的遠端快取讓這些產物可以在不同機器之間共用。要了解它與 DerivedData 和 Clang 模組快取的關係，請參閱 <.localized_link href="/references/concepts/build-cache#xcode">什麼是 Xcode 快取？</.localized_link>。要找出快取能消除緩慢建置中的哪一部分，以及應該優先修復專案中的什麼問題，請參閱 [緩慢建置](https://tuist.dev/solutions/slow-builds)。

> [!TIP]
> **與模組快取搭配使用**
>
> Xcode 快取和 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 在不同的粒度層級運作並互補。模組快取在建置執行前以預建的 `.xcframework` 取代整個模組，而 Xcode 快取則在建置期間重用編譯輸出。

> [!TIP]
> **在開發者機器上清理時保留 `CompilationCache.noindex`**
>
> 預設情況下，編譯快取儲存區位於 `DerivedData` 內，因此刪除 `DerivedData` 會連同建置產物一起將其移除。在開發者機器上，建議只刪除建置產物：這樣重建時會從磁碟上的儲存區重放，無需抓取任何內容。

## 設定 {#setup}

如果你還沒有 Tuist 帳戶和專案，可以透過執行以下指令來建立：

```bash
tuist init
```

一旦你擁有引用你的 `fullHandle` 的 `Tuist.swift` 檔案，就可以透過執行以下指令為你的專案設定快取：

```bash
tuist setup cache
```

此指令會建立一個 [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在啟動時執行本機快取服務，供 Swift [建置系統](https://github.com/swiftlang/swift-build) 用來共用編譯產物。請先在開發者機器上執行，並作為每個 CI 工作設定的一部分。

要在 CI 上設定快取，請確保你已 <.localized_link href="/guides/server/authentication#continuous-integration">通過驗證</.localized_link>。

### 更新快取元件 {#updating-the-cache-components}

快取代理使用穩定的啟動器，而非綁定到最後一次執行設定的 Tuist 安裝路徑。安裝後，`tuist setup cache` 和啟用快取的 `tuist generate` 會將可用目標推進到較新的 Tuist 版本。因此，綁定到較舊 Tuist 的專案不會降級共用的代理。產生僅更新現有的啟動器目標：它不會安裝服務、進行驗證、替換外掛程式或重新啟動代理。自訂外掛程式、代理、套接字或註冊表覆蓋會跳過自動推進。

運行中的代理只有在至少 30 秒沒有快取請求、沒有正在進行的請求或背景工作且其發布緩衝區已排空的情況下，才會採用新目標。然後它會退出，launchd 會啟動選定的 CLI，保留服務的參數和憑證環境。只有實際採用目標的代理會原子性地從其套件刷新磁碟上的外掛程式；當較舊的代理仍在排空時，設定不會安裝較新的外掛程式。如果已安裝的外掛程式遺失，明確的空閒設定會重新啟動選定的代理以重試刷新。仍然只有一個代理擁有註冊表和緩衝區。不可用的目標或未排空的上傳會延遲切換，而不是中斷活動請求。憑證刷新會在切換之前就跟隨選定的 CLI，因此移除較舊的 CLI 安裝不會使等待排空的上傳孤立無援。

在穩定啟動器之前建立的現有安裝需要一次明確的遷移。在沒有建置運行時執行以下操作：

```bash
tuist setup cache
```

遷移後，更新 Tuist 並運行你慣常的 `tuist generate` 就足以推進代理和已安裝的外掛程式；你不需要為每個 CLI 版本重新運行設定。若要選擇不同的 Xcode（包括在同一路徑更新的 Xcode），仍需要明確設定。當共用服務的配置變更時，設定可以替換該服務，因此請先等待機器上的所有建置完成。代理同時支援先前和當前的外掛程式協議，因此已在 Xcode 中載入的相容外掛程式在代理升級後仍可繼續運作。完全退出並重新開啟 Xcode 以載入最新的外掛程式，但已載入的相容外掛程式不需要立即重新啟動。當版本變更產生的建置設定時，請重新產生專案。

保持所選的 Tuist 安裝可用：啟動器會使用它來進行啟動、配置和憑證刷新。一旦啟動器已推進，就可以移除較舊的安裝。如果所選的可執行檔已被刪除或不再可執行，`tuist setup cache` 可以使用可用的安裝（即使是較舊的版本）修復目標，而無需先拆除快取。穩定的可執行檔別名在套件管理器升級期間會保留；僅在比較安裝身份時才會解析符號連結。在啟動時，代理會記錄實際啟動的版本，包括就地更新或故意回滾，同時保留使用的最高版本，以防止不相關的舊簽出切換可用的安裝。

沒有發行版本且明確設定 `TUIST_CAS_PLUGIN_PATH` 或 `TUIST_CAS_PROXY_PATH` 的原始碼建置 CLI 會使用明確的啟動配置，而非自動版本選擇。在重建這些元件後重新運行設定。設定會檢查它們的新鮮度，僅在其替換準備好後才停用受管理的目標推進。

`tuist teardown cache` 會在移除啟動器目標之前停止服務，同時為現有專案保留穩定的外掛程式。如果停止服務失敗，其啟動器仍可用於重新啟動和再次嘗試拆除。成功拆除後，產生無法重新建立服務。

### 配置 Xcode 建置設定 {#configure-xcode-build-settings}

對於現有的 Xcode 專案，將 `tuist setup cache` 輸出的建置設定複製到專案的「Build Settings」或現有的 `.xcconfig` 檔案中。該指令會輸出你帳戶的配置；它不會產生配置檔案或編輯你的 Xcode 專案。在擴展 `OTHER_SWIFT_FLAGS` 時保留 `$(inherited)`，以便保留其他編譯器選項。

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

請注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 和 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 需要作為 **使用者定義的建置設定** 添加，因為它們並未直接在 Xcode 的建置設定 UI 中公開。

> [!NOTE]
> **外掛程式路徑**
>
> `libtuist_cas_plugin.dylib` 是隨 Tuist 一起提供的編譯快取外掛程式，位於 `tuist` 可執行檔旁邊。`tuist setup cache` 會將其複製到 `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而 `COMPILATION_CACHE_PLUGIN_PATH` 指向該副本。該路徑在每台機器上都相同，且在更新 Tuist 時不會改變，因此你可以將此設定與專案一起提交。設定和新啟動的代理會從所選的 Tuist 套件刷新副本；從較舊的簽出運行設定不會降級較新的外掛程式。

> [!NOTE]
> **每個專案使用同一個 Socket**
>
> `tuist setup cache` 在每台機器上安裝單一的快取代理，因此每個專案都使用相同的 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance` 外掛程式選項用於識別專案。
>
> Xcode 僅將 `OTHER_SWIFT_FLAGS` 傳遞給 Swift 編譯器，而不傳遞給其建置系統自行執行的快取查找。這些查找會從同一建置中 Swift 編譯器的選項獲取專案資訊。`tuist build`、`tuist test` 和 `tuist xcodebuild` 也會直接將專案傳遞給它們。對於沒有 Swift 程式碼且透過其他方式（例如純 `xcodebuild` 或 Xcode 應用程式）建置的專案，可以在 Socket 路徑後添加專案：`COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock?tuist-instance=your-org/your-project`。否則，在快取代理尚未見過該專案的機器上（例如在作業之間重置的 CI 機器），第一次建置可能會重新編譯一些已快取的檔案。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` 是用來共用 C 和 Objective-C 的設定**
>
> 人們很容易將此設定解讀為「快取服務的位置」並視為可選。它也是決定是否共用 C、Objective-C、預編譯模組和預編譯標頭檔的開關：只有在配置了遠端快取服務時，建置系統才會為這些內容運行快取。如果省略它，你仍然可以共用 Swift 編譯，但在任何尚未建置過該專案的機器上，每個 C/Objective-C 檔案和每個模組都會被重新編譯。

> [!NOTE]
> **並行快取查找**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 會讓建置系統為每次編譯執行的遠端快取查找與其餘建置並行運行，而不是在建置的執行通道上一次只運行幾個。對於從遠端快取錯過或還原許多編譯的建置，完成時間會更短。

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
> 在 Xcode 27 及更高版本中，`tuist setup cache` 還會輸出 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING` 和 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它們使編譯快取金鑰獨立於專案和 `DerivedData` 所在的位置。將它們添加為使用者定義的建置設定。啟用它們會改變每個快取金鑰，因此下一次建置會再次填充快取。當 `enableCaching` 開啟時，`tuist generate` 會為你設定它們。
>
> 編譯器還會將映射的路徑寫入程式碼涵蓋率數據中，而 Xcode 無法解析它們，因此涵蓋率報告會遺漏所有使用前綴映射編譯的原始碼。輸出的設定以及 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定會在收集程式碼涵蓋率的建置中關閉前綴映射。`tuist generate` 也是如此。這些建置仍然使用編譯快取，但其快取金鑰取決於專案和 `DerivedData` 路徑。
>
> 當你在命令列將這些設定傳遞給 `xcodebuild` 時，請對包含 `$(...)` 的值使用單引號，如同上面的 `OTHER_SWIFT_FLAGS` 一樣。否則，Shell 會將它們擴展為空字串，從而關閉前綴映射：
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

### 帶前綴映射的涵蓋率 {#coverage-with-prefix-mapping}

預設情況下，產生的專案會為涵蓋率建置禁用前綴映射，以保持 Xcode 的涵蓋率報告和 `xccov` 正常運作。你可以啟用它，以使涵蓋率編譯在不同簽出之間可共用：

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

`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）優先於 `prefixMapping`。此選項適用於 Xcode 27 及更高版本，並且需要 `enableCaching`。涵蓋率 `tuist test` 上傳支援它：Tuist 使用 `llvm-cov` 測量運行，它讀取帶有映射路徑的原始碼，並將它們與你的儲存庫檔案關聯起來。Xcode 自身的涵蓋率報告和 `xccov` 仍然可能遺漏這些原始碼，如果 `llvm-cov` 匯出失敗，回退到結果套件的 `xccov` 報告的上傳也可能遺漏它們。映射的 `#filePath` 值也可能影響相對於原始碼檔案定位測試夾具的測試；請改為透過明確的運行時簽出路徑解析夾具。如果你自行處理涵蓋率，請將每個檢測過的二進位檔與其目標的 `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` 配對，後者將虛擬前綴映射回本機目錄。當啟用每專案映射時，不要為每個二進位檔重複使用同一個目標的映射。

涵蓋率前綴設定參與二進位快取和選擇性測試的雜湊計算，因為它們控制寫入涵蓋率產物的路徑。更改此選項或以不同方式設定 `TUIST_COVERAGE_PREFIX_MAPPING` 會使這些雜湊無效，即使是普通建置也是如此。如果開發人員和 CI 作業應該共用二進位快取和選擇性測試結果，請保持該值一致。

### 除錯產生的專案 {#debugging-generated-projects}

還原的原生模組需要連結的除錯資訊以及對編譯快取的存取權限。Tuist 會使用 dSYM 和每切片原始碼身份元數據預熱 Debug 和 Release 模組，然後在替換目標之前根據消費者聲明的原始碼驗證元數據。缺少或不兼容的元數據會保留該目標的原始碼。腳本產生的 `.generated(...)` 原始碼具有宣告指紋，而非可驗證的內容校驗和，因此這些目標保持原始碼建置狀態，不會發布到原生模組快取。具有實際內容校驗和的產生資源存取器仍然符合資格。不支援的除錯資訊會跳過受影響目標的發布，而不會阻塞無關的產品；原始碼變異和取消仍然會導致預熱失敗。快取格式已更改，因此由較舊版本預熱的產物需要重新預熱。

對於已驗證的替換，Tuist 會在消費者擁有的 dSYM UUID plist 中準備原始碼重新定位，並為靜態快取程式碼連結僅供除錯使用的輔助檔案。它不會重寫快取的二進位檔，也不會在 LLDB 的持久全域原始碼地圖中安裝生產者原始碼路徑。明確的除錯器初始化器和模組載入器設定仍然具有權威性。在 CI 環境中（當設定了 `CI` 或 `JENKINS_URL` 時），執行此操作的 Scheme 預先動作會不作任何變更就退出，因為那裡沒有除錯器附加到測試上。除錯符號和原始碼重新定位不會修復相對於原始碼的執行時檔案存取或原生 Xcode 涵蓋率報告；涵蓋率變體選擇和 LLVM 匯出仍然是獨立的功能。

使用 `enableCaching: true` 時，Tuist 會為「執行」和「測試」動作設定 LLDB 原始碼地圖。當某個動作擁有自訂 LLDB 初始化器時，Tuist 會先寫入其解析後的原始碼地圖，然後載入該自訂初始化器，以便它可以擴展或覆蓋地圖。否則，它會在替換原始碼地圖之前載入 `~/.lldbinit-Xcode`（如果檔案存在），若不存在則回退至 `~/.lldbinit`。它只載入一個主目錄檔案，恢復每位使用者的除錯器設定而不會重複載入。替換操作會移除先前執行留下的過時映射，並優先於主目錄檔案中的原始碼地圖；請將需要保留的原始碼地圖條目放入動作的自訂初始化器中。其他主目錄設定會被保留。Tuist 專用於快取的模組搜尋路徑、載入器設定和 Clang 標誌隨後應用，並優先於使用者對這些設定的值。主目錄檔案錯誤仍然可見，不會阻止後續命令載入，且命令不會被回顯。即使沒有 `enableCaching` 以及在較早版本的 Xcode 上，當 Tuist 為從模組快取還原的二進位檔設定除錯時，這種初始化器保留機制也同樣適用。

在 Xcode 27 及更高版本中，產生的專案會關閉 Xcode 的每專案前綴映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 和 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`），除非專案明確設定了它們。它們的前綴（例如 `/^src`）在每個專案中指向不同的目錄，而 LLDB 僅針對被除錯目標所屬的專案來解析它們。相反，原始碼會記錄在工作區範圍的前綴下：`/^root` 代表 Tuist 根目錄，`/^spm` 代表 Swift 套件暫存目錄，而 `/^intermediates` 和 `/^products` 代表建置產物。每個前綴在所有專案中都指向同一個目錄，因此斷點可以解析工作區中任何專案的原始碼。

Tuist 根目錄之外的路徑不會被映射。根目錄之外專案的快取鍵取決於其檢出位置，因此其他檢出位置和機器會錯過該專案的快取。為了使其鍵獨立於檢出位置，請在該專案的 manifest 中開啟每專案映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

將這些設定傳遞給該 `Project`。當你除錯來自另一個專案的目標時，LLDB 將無法找到該專案的原始碼。Manifest 中的專案基礎設定優先於專案層級的 xcconfig 值，因此請直接在 manifest 中設定它們。

更改這些設定會改變編譯快取鍵、二進位快取雜湊和選擇性測試雜湊，因此這些快取需要重新預熱。請在團隊中保持此選擇一致。

### 快取上傳政策 {#cache-upload-policy}

預設情況下，快取服務會同時下載和上傳產物到遠端快取。你可以透過 `Tuist.swift` 檔案中的 `xcodeCache` 選項來控制此行為，以啟用唯讀模式，即在該模式下會下載產物但從不上傳：

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

一種常見的模式是僅從 CI 推送產物，因為那裡的建置是可重現的，同時保持本地環境為唯讀。你可以使用 `Environment.isCI` 來實現這一點，它會檢查大多數 CI 提供者設定的 `CI` 環境變數：

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

透過此設定，本地建置可以受益於快取產物而無需上傳，同時 CI 建置會為團隊的其他成員填充快取。

上傳政策會記錄在執行 `tuist setup cache` 的機器上，按專案區分。若要更改它，請更新 `upload` 並再次執行 `tuist setup cache`，如果 Tuist 產生你的專案，也要執行 `tuist generate`。之後的上傳將遵循新政策，無需重新啟動該機器上的快取。在同一台機器上同時執行的同一專案作業共用其政策，因此最近的 `tuist setup cache` 決定所有作業的政策。

### 儲存空間大小限制 {#store-size-limit}

編譯快取儲存空間會隨著每次建置而增長。為了限制專案的儲存空間，請在你的 `Tuist.swift` 檔案中設定 `storeSizeLimit`：

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

Tuist 會在快取代理啟動時（在任何建置使用它們之前）以及每 10 分鐘（當沒有建置運行時）檢查專案的每個儲存空間。`tuist setup cache` 會在代理未運行時啟動它，因此一個在建置前執行 `tuist setup cache` 並在建置後執行 `tuist teardown cache` 的 CI 作業，會在每個作業開始時限制長期運行的 Runner 的儲存空間。當較新的建置寫入了約一半的限制容量時，它會刪除儲存空間中最舊的快取產物，使儲存空間穩定在限制附近。在建置運行期間，儲存空間可能會超過限制；而在你設定限制時已經超過限制的儲存空間，會在新建置寫入足夠數據後縮小。當多個專案使用同一個儲存空間（如同其預設位置那樣）時，適用其中最小的限制。該限制適用於你執行 `tuist setup cache` 的每一台機器，因此在更改限制後請再次執行它。已經運行的快取代理會繼續運行，並在其下一次檢查時應用新限制。

### 模組快取雜湊 {#module-cache-hashes}

編譯快取設定不屬於 <.localized_link href="/guides/features/projects/hashing">模組快取雜湊</.localized_link> 的一部分。Tuist 會將每個 `COMPILATION_CACHE_*` 建置設定以及每個帶有值的 `-cas-plugin-option` 標誌排除在雜湊計算之外。開啟或關閉 `enableCaching`，或更改上傳政策，會保留你目標的雜湊值，因此你已經預熱的 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔仍然有效。你可以針對相同的模組快取比較有和沒有 Xcode 快取的建置。

> [!NOTE]
> **前綴映射設定會被雜湊化**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true` 還會設定 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 和 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 設定。這些設定是模組快取雜湊的一部分，因此在 Xcode 27 及更高版本中，開啟或關閉 `enableCaching` 會改變你目標的雜湊值。

### 重用大型產物的部分內容 {#reusing-parts-of-large-outputs}

當伺服器支援時，Xcode 快取會以分塊方式傳輸大型產物，並僅發送或抓取自先前版本以來有變更的分塊。這些分塊儲存在一個小型本地快取中，與 `DerivedData` 分開，因此即使在清理編譯快取後仍能保留。小型產物、較舊的伺服器以及較舊的客戶端則使用傳統的完整產物傳輸方式。

這能減少下載和上傳的數據量，但不會減少重新編譯的量。如果是一台沒有匹配分塊的冷機器，仍然會下載整個產物。

### 持續整合 {#continuous-integration}

若要在你的 CI 環境中啟用快取，你需要執行與本地環境相同的指令：`tuist setup cache`。

對於身份驗證，你可以使用 <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份驗證</.localized_link>（推薦用於支援的 CI 供應商）或透過 `TUIST_TOKEN` 環境變數使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>。

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

請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以获取更多範例，包括基於令牌的身份驗證以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的編譯快取儲存空間 {#compilation-cache-store-on-ci}

編譯快取儲存空間是 Xcode 存放編譯產物的本地目錄。`COMPILATION_CACHE_CAS_PATH` 建置設定會設定其位置，預設為 `DerivedData` 內的 `CompilationCache.noindex`。

#### 有狀態儲存空間 {#stateful-store}

若要在建置之間保留儲存空間，請將 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 用的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一個持久路徑，並使用 [儲存空間大小限制](#store-size-limit) 來限制其大小。

## 疑難排解 {#troubleshooting}

### 建置警告指出 Xcode 快取代理失敗 {#cas-proxy-failed}

如果建置顯示如下警告，Xcode 會根據哪個編譯首先遇到失敗，在其前面加上 `CAS error:` 或 `CAS operation failed:`：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

這表示編譯快取無法連接到由 `tuist setup cache` 安裝的本地快取代理。建置仍然成功，但受影響的編譯無法獲得遠端快取命中，因此其運行方式如同使用空快取的建置。它們的上傳內容會保留在磁碟上，並在代理再次處理請求時發送：如果在同一個建置期間及時恢復，則在該建置稍後階段發送；否則會在同一台機器的下一次建置期間發送。作業結束後被丟棄的 CI 機器會遺失這些資料。該警告在每次建置中出現一次，顯示在 Xcode 的問題導覽器和 `xcodebuild` 輸出中。

若要檢查代理是否正在運行，請查找監聽警告中所述套接字的進程：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果命令沒有列印任何內容，請運行 `tuist setup cache` 以重新啟動代理。在 CI 上，請在每個作業中的任何 `xcodebuild` 調用之前運行 `tuist setup cache`。

### 建置極慢並發出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的建置時間遠長於預期，且 Xcode 建置日誌充滿了如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

這表示 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一個無人監聽的套接字，通常是早期版本的 Tuist 設定的每個專案套接字（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供該套接字服務。Xcode 會在每次編譯快取請求時重試連接，而不是快速失敗，這可能導致建置耗時一小時或更久，而 Tuist 無法改變此行為。

要解決此問題：

- **生成的專案**：再次運行 `tuist generate`。
- **其他專案**：將 `COMPILATION_CACHE_*` 建置設定替換為 `tuist setup cache` 列印的設定，如 [設定 Xcode 建置設定](#configure-xcode-build-settings) 中所述。

如果你不使用 Xcode 快取，請改為移除 `COMPILATION_CACHE_*` 建置設定並運行 `tuist teardown cache`。

### `uploaded CAS output` 在本地出現，即使上傳已禁用 {#uploaded-cas-output-with-upload-disabled}

當設定 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 機器上設定 `upload: Environment.isCI`）時，你仍可能在建置日誌中看到 `note: uploaded CAS output ...`。`xcodebuild` 無法跳過這些調用，因此 Tuist 仍然會接收它們，但它不會向 Tuist 伺服器發布任何內容。儀表板指標已考慮此情況，因此不會報告虛假的上傳流量。

## 相關 {#related}

探索 [Tuist 的共享快取](https://tuist.dev/cache)，了解工程團隊和編碼代理如何重用建置產物。
