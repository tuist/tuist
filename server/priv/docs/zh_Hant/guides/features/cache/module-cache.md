---
{
  "title": "模組快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Module Cache 快取編譯後的二進位檔，並在團隊中共享。"
}
---

# 模組快取{#module-cache}

> [!WARNING]
> **必要條件**
>
> - <.localized_link href="/guides/features/projects">已產生的專案</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的專案圖，以計算目標的雜湊值並替換其二進位檔。

Tuist 模組快取提供了一種強大的方式，透過將模組快取為二進位檔（`.xcframework`）並在不同環境間共用，來優化建置時間。此功能讓你能够利用先前產生的二進位檔，減少重複編譯的需求，並加速開發流程。

> [!TIP]
> **與 Xcode 快取搭配使用**
>
> 模組快取與 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 互為補充，因為它們運作於不同的粒度層級。模組快取在建置執行前，以預先建置的 `.xcframework` 取代整個模組；而 Xcode 快取則在建置期間重複使用編譯輸出。
>
> 編譯快取設定不屬於模組快取雜湊的一部分，因此開啟或關閉 Xcode 快取不會影響你已預熱的二進位檔。在 Xcode 27 及更新版本中，隨附的前綴對應設定會被納入雜湊計算。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取雜湊</.localized_link>。

## 預熱{#warming}

Tuist 會針對相依圖中的每個目標有效 <.localized_link href="/guides/features/projects/hashing">運用雜湊</.localized_link> 來偵測變更。利用這些資料，它會為源自這些目標的二進位檔進行建置並指派唯一識別碼。在產生圖表時，Tuist 接著會無縫地以對應的二進位版本取代原始目標。

這項稱為 *「預熱」* 的操作會產生供本機使用，或透過 Tuist 與團隊成員及 CI 環境共用的二進位檔。預熱快取的過程簡單明瞭，只需執行一個命令即可啟動：

```bash
tuist cache
```

該命令會重複使用二進位檔以加速流程。

如果某個二進位檔上傳失敗，命令仍會上傳其餘檔案，然後以非零狀態結束，並列出未上傳的目標。機器本機快取中的二進位檔視為已快取，因此若要從同一台機器再次上傳它們，請在預熱前執行`tuist clean binaries`。傳遞`--no-upload`以僅將二進位檔儲存於本機快取中。

### 目的地選擇{#destination-selection}

使用`--destination simulator`或`--destination device`來針對單一目的地進行快取與產生：

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

預設值為`all`，這會保留你的目標支援的所有目的地，包括 Mac Catalyst。後續的`tuist cache`會重複使用已快取的切片，並僅建置缺少的 SDK。一般產生會在缺少任何必要切片時保留模組的原始碼。

限制性產生會將來源目標限制為選定的目的地，並保留原生 macOS 目標，包括巨集。兩種限制模式均不包含 Mac Catalyst。使用`--destination all`重新產生以還原所有目的地。

逐切片快取支援具有標準架構的 iOS 和 macOS。其他平台、自訂架構和不支援的產品則維持完整構件快取。傳統模組快取需要`--destination all`。

### 遠端上傳准入{#remote-upload-admission}

現代模組快取使用 REAPI。當繁忙的快取暫時以`RESOURCE_EXHAUSTED`拒絕上傳時，Tuist 會以抖動方式退避，遵守標準的`google.rpc.RetryInfo`最小延遲，並在有限的等待預算內重試。每次呼叫的上傳准入最多允許六次重試。每個 blob 上傳作業在其存在檢查、批次上傳和串流寫入之間共用一個 60 秒的累積退避預算；並行等待各自消耗預算，因此重複拒絕不會讓每個排隊的 blob 再獲得一分鐘的重試時間。成功的傳輸不會消耗此預算，且在預算耗盡時不會被取消。動作結果發布有其自身的有限預算。指數延遲從一秒開始，在比例抖動前增長至 30 秒。如果伺服器要求的延遲超過剩餘預算，Tuist 會失敗而非早於指示進行重試。取消會中斷退避，而快取讀取保留短重試，以免過載導致產生停滯。

這些預設值也有助於沒有重試提示的舊版 Kura。較長的重試吸收的是暫時性競爭，而非持續性過載：如果拒絕持續發生，請降低預熱作業的[快取並發限制](#cache-concurrency-limit)或增加伺服器容量。請參閱[Kura 上傳規模評估](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以取得 Pod 記憶體估算和准入指標。

### 組態選擇{#configuration-selection}

當在不傳遞`--configuration`的情況下預熱快取時，Tuist 會依下列順序選擇要使用的建置組態：

1. 資訊清單的`Project.Options.generationOptions`中設定的[`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體為`debug`的第一個建置組態，依名稱字母順序排序。

若要為特定組態預熱快取，請明確傳遞該組態：

```bash
tuist cache --configuration Release
```

## 用法{#usage}

預設情況下，當 Tuist 命令需要產生專案時，如果可用，它們會自動以快取中的二進位等效項替換相依性。此外，如果你指定要關注的目標清單，Tuist 也會以快取的二進位檔替換任何相依目標（前提是它們可用）。對於偏好不同方法的人，可以使用特定旗標完全退出此行為：

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> 二進位快取是一項專為開發工作流程設計的功能，例如在模擬器或裝置上執行應用程式，或執行測試。它不適用於發行版建置。在歸檔應用程式時，請使用`--cache-profile none`產生包含原始碼的專案。

## 快取設定檔{#cache-profiles}

Tuist 支援快取設定檔，以控制在產生專案時替換目標為快取二進位檔的積極程度。

- 內建設定檔：
  - `only-external`：僅替換外部相依性（系統預設）
  - `all-possible`：盡可能替換更多目標（包括內部目標）
  - `none`：永不以快取二進位檔替換

在`tuist generate`上使用`--cache-profile`選擇設定檔：

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **已棄用的旗標**
>
> `--no-binary-cache`旗標已棄用。請改用`--cache-profile none`。已棄用的旗標仍為了向後相容而有效。

解析有效行為時的優先順序（從高到低）：

1. `--cache-profile none`
2. 目標焦點（將目標傳遞給`generate`）→ 設定檔`all-possible`
3. `--cache-profile <value>`
4. 組態預設值（若已設定）
5. 系統預設值（`only-external`）

## 支援的產品{#supported-products}

Tuist 僅能快取下列目標產品：

- Framework（靜態與動態），包括相依於[XCTest](https://developer.apple.com/documentation/xctest)或 Swift Testing 的測試支援 Framework
- 程式庫（靜態與動態），包括相依於 XCTest 或 Swift Testing 的測試支援程式庫
- Bundle
- Swift Macros

測試 Bundle 仍被排除在模組快取之外。這表示`unitTests`和`uiTests`目標不會以二進位檔形式快取，但測試所依賴的一般 Framework 和程式庫目標即使連結了 XCTest 或 Swift Testing，仍可被快取。

快取的程式庫`.xcframework`會保留產生專案匯入它們所需的後設資料，包括 Swift 模組以及當來源目標宣告公開標頭時的公開 C/Objective-C 標頭。

> [!NOTE]
> **上游相依性**
>
> 當某個目標無法快取時，其上游目標也會變成無法快取。例如，若你有相依圖`A > B`，其中 A 相依於 B，如果 B 無法快取，A 也無法快取。

## 分析{#analytics}

在專案儀表板中開啟**模組快取 → 模組**以找出經常未命中的模組。選擇你想要改善的環境，例如**CI**，以及日期範圍。概覽會顯示快取命中、未命中以及有未命中的模組；開啟模組會顯示其歷史記錄以及每次觀察所指派的原因。

**未命中**下拉式選單會為單一原因選擇計數與說明。圖表顯示所有四種原因的分布。在模組頁面上，使用歷史記錄的**原因**篩選器來檢查個別發生情況。將滑鼠懸停在原因徽章上，或使用鍵盤聚焦它以查看其定義。

### 未命中原因{#miss-reasons}

| 原因 | 意義 |
| --- | --- |
| **已變更** | 模組自身的比較輸入已變更。這些包括檔案雜湊、建置設定、解析後的組態以及編譯器識別碼。原始碼編輯只是可能的原因之一。 |
| **上游** | 模組自身的比較輸入保持不變，但其相依性或外部套件的雜湊已變更。模組的原始檔可能完全未更動。 |
| **冷啟動** | 沒有較早的模組觀察可供比較，或者報告的輸入無法解釋未命中，且沒有符合條件的早期遠端可用性證據。冷啟動並不能證明該模組從未快取過。 |
| **已驅逐** | 確切的快取金鑰先前在同一專案的相同記錄快取端點曾有遠端命中，但現在未命中。 |

對於標示為**已驅逐**的未命中，該構件先前已從遠端快取下載，但這次無法重複使用。驅逐是可能的原因，儘管存取或下載失敗也可能解釋未命中。Tuist 僅在找到早期的遠端命中時才會指派此標籤；先前的未命中和本地命中並不足夠。

例如：

| 情境 | 分類 |
| --- | --- |
| 模組未命中，且無早期觀察或符合條件的遠端命中 | 冷啟動 |
| A 變更；B 相依於 A，C 相依於 B；三個金鑰皆變更 | A 為已變更；B 和 C 為上游 |
| 預熱後編譯器版本變更，原始碼和設定保持不变 | 當兩次觀察都報告編譯器輸入時，受影響的未命中為已變更 |
| 確切的金鑰曾從遠端下載，但在其構件被驅逐後未命中 | 已驅逐，當早期的命中符合證據條件時 |
| 金鑰反覆未命中且從未成功預熱 | 可能保持冷啟動 |

原因用於描述觀察結果；它們並非附加在金鑰上的永久標籤。例如，編譯器升級後的第一次未命中可能是「已變更」，而如果該新金鑰從未在遠端被觀察到可用，後續的未命中則可能是「冷啟動」。

### 提升快取命中率 {#improving-cache-hit-rate}

1. **選擇一致的基準。** 從 CI 和具有代表性的日期範圍開始。按未命中次數對模組排序，然後考慮其命中率、相依者和建置成本。修復經常未命中的昂貴相依性，比提升微小模組的命中率更能節省時間。在進行變更後，比較相同的環境和類似的工作負載。
2. **調查「已變更」未命中。** 開啟相關的執行記錄，並比較其完整金鑰和報告的輸入。將預熱和使用作業對齊至預期的 Xcode/編譯器版本、組態和目標目的地。在有意圖的變更後再次預熱。如果易變的產生檔案或依賴環境的設定導致原本穩定的模組失效，請調查這些輸入。將影響二進位相容性的輸入保留在雜湊中。
3. **追蹤「上游」未命中至變更的相依性。** 檢查其歷史記錄以找出直接變更。預熱產生的金鑰可以恢復重複使用。如果頻繁變更的實作導致許多昂貴的相依者失效，請考慮如[效率](#efficiency)所述，採用較小的模組或穩定的介面。
4. **檢查「冷啟動」未命中的預熱涵蓋範圍。** 驗證預熱是否選取了所需的模組、使用了消費作業的組態和環境，並成功上傳了構件。檢查實際 CI 作業使用的完整金鑰。如果預熱和消費請求不同的金鑰，在假設快取已被驅逐之前，請檢查雜湊輸入。即使模組的原始碼未變更，仍可能出現反覆未命中且無早期成功上傳的情況。
5. **利用「已驅逐」未命中的證據。** 確認消費執行的金鑰和端點，然後檢查消費執行的快取警告和預熱作業的上傳結果。在適用時檢查保留或驅逐策略。重新預熱所需的構件並驗證後續的命中。如果仍然未命中，請將相關的執行連結和日誌提供給支援團隊。

若要進行雜湊比較，請在您打算預熱和消費的每個相關環境中，使用您預期的組態執行以下命令：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模組的完整雜湊和元件區塊。在同一台未變更的機器上重複執行命令通常應產生相同的結果；比較實際的預熱和消費環境以調查不一致之處。這兩個命令都不需要命中快取。如需進一步檢查，請參閱<.localized_link href="/guides/features/projects/hashing#debugging">雜湊診斷</.localized_link>。

## 效率 {#efficiency}

透過二進位快取所能達到的效率水準，很大程度上取決於圖結構。為了獲得最佳結果，我們建議採取以下措施：

1. 避免過深巢狀的相依圖。圖層越淺越好。
2. 使用協定/介面目標而非實作目標來定義相依性，並從最頂層的目標注入實作的相依性。
3. 將頻繁修改的目標拆分為較小的目標，以降低其變更的可能性。

上述建議屬於<.localized_link href="/guides/features/projects/tma-architecture">模組化架構</.localized_link>的一部分，我們建議以此方式組織專案，不僅能最大化二進位快取的效益，也能充分利用 Xcode 的功能。

## 建議設定 {#recommended-setup}

我們建議設定一個 CI 作業，**在主分支的每次提交中都執行**以預熱快取。這將確保快取始終包含`main`中變更的二進位檔，以便本地和 CI 分支建置能在此基礎上進行增量建置。

> [!TIP]
> **保持快取預熱隔離**
>
> 在專用的 CI 步驟中執行`tuist cache`，且不要有後續依賴所產生工作區的步驟。由於`tuist cache`會為了快取建置目的而修改工作區，任何需要工作區的 CI 步驟都應先執行`tuist generate`以獲得全新且可用的工作區。

> [!TIP]
> **快取預熱使用二進位檔**
>
> `tuist cache`命令也會利用二進位快取來加速預熱過程。

以下是一些常見工作流程的範例：

### 開發人員開始開發新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他們從`main`建立一個新分支。
2. 他們執行`tuist generate`。
3. Tuist 從`main`提取最新的二進位檔，並使用它們產生專案。

### 開發人員推送變更至上游 {#a-developer-pushes-changes-upstream}

1. CI 流水線將執行`xcodebuild build`或`tuist test`來建置或測試專案。
2. 工作流程將從`main`提取最新的二進位檔，並使用它們產生專案。
3. 然後它將增量建置或測試專案。

## 組態 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將`TUIST_CACHE_CONCURRENCY_LIMIT`設定為正整數以限制下載和上傳。例如，減少小型自託管快取在預熱作業中的負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

未設定時，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時，下載使用八個任務；僅限批次的計畫則使用 32 個。舊版 HTTP 快取路徑預設為 100；該預設不適用於 REAPI。無效值（包括先前文件記錄的`none`）會保留預設值而非移除限制。使用`unset TUIST_CACHE_CONCURRENCY_LIMIT`來恢復預設值。

限制適用於每次傳輸作業，而非全域適用於所有作業或 CI 工作。三個併發預熱作業若限制為二，可能會對同一快取同時進行六個上傳。消費作業可以不設定該變數，以保留預設的下載平行處理能力。

### 快取預熱暫存目錄 {#cache-warm-scratch-directory}

預設情況下，`tuist cache`會為建置中介檔案和組合好的快取構件建立一個暫存暫存目錄，並在快取預熱完成後將其刪除。若要將這些檔案保留在您管理的目錄下，請設定`TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑或相對於目前工作目錄的路徑。當目錄不存在時，Tuist 會建立該目錄。如果目錄已存在，則必須是空目錄。

設定此環境變數後，Tuist 會在命令完成後保留該目錄及其內容。呼叫者負責在下一次快取預熱前清理它。當未設定該變數時，Tuist 會繼續使用並移除暫存目錄。

當需要預熱外部建置目標時，Tuist 會拒絕使用由呼叫者擁有的暫存目錄。外部建置腳本控制其自身的輸出位置，因此 Tuist 無法保證這些輸出會保留在暫存目錄內。

### 程式碼涵蓋率 {#code-coverage}

> [!NOTE] EARLY ACCESS
> 模組快取的程式碼涵蓋率功能處於早期存取階段。僅在設定 `TUIST_FEATURE_FLAG_COVERAGE=1` 時，命令才會讀取並預熱下述的檢測二進位檔。

來自模組快取的目標是預先建置的二進位檔，只有在該二進位檔建置時啟用了涵蓋率計數器，測試執行才會測量其程式碼。請在 `Tuist.swift` 中為您的專案開啟涵蓋率：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

啟用 `enabled` 後，每個命令和每個環境都會讀取專案自身目標的單一檢測版快取變體，因此在 CI 上的一次預熱即可同時服務 CI 和本機機器：

| 命令 | 您專案的目標 | 外部套件 |
| --- | --- | --- |
| `tuist cache`（Debug 組態） | 預熱檢測二進位檔 | 預熱普通二進位檔 |
| `tuist cache`（Release 組態） | 預熱普通二進位檔 | 預熱普通二進位檔 |
| `tuist hash cache` | 列印檢測金鑰 | 列印普通金鑰 |
| `tuist generate` | 讀取檢測二進位檔 | 讀取普通二進位檔 |
| `tuist test` | 讀取檢測二進位檔 | 讀取普通二進位檔 |

此選項適用於 Xcode 視為 Debug 的每種組態。Release 建置永遠不會進行檢測。Tuist 也會在這些組態中連結分析期執行階段（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使未收集涵蓋率的建置仍會連結檢測二進位檔，並在其自動產生的 scheme 以及您定義但未設定 `coverage` 的 scheme 之測試動作中開啟涵蓋率。

您定義的 scheme 會遵循此選項，除非它自行設定涵蓋率：`.options(coverage: false)` 會保持關閉，而 `.options(coverage: true)` 會保持開啟，無論選項如何規定。測試計畫會自行決定涵蓋率，且 `-enableCodeCoverage` 仍會覆蓋執行行為，如同在 Xcode 中一樣。讀取檢測二進位檔但未收集涵蓋率的執行會正常建置和測試。當執行收集涵蓋率，但您專案的目標以普通二進位檔形式來自快取時，Tuist 會警告其涵蓋率未被測量。

`TUIST_COVERAGE_ENABLED` 環境變數（`1` 或 `0`）優先於 `coverage: .coverage(enabled:)`。請為整個環境（例如 CI 工作流程）設定它，而非僅針對單一命令，以使預熱快取的命令與讀取快取的命令保持一致。

`prefixMapping`（參見<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有其自身的覆蓋機制：`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）優先於 `coverage: .coverage(prefixMapping:)`。

覆蓋為關閉會讀取普通變體，而開啟涵蓋率預熱的快取不會填充該變體，因此這些目標會從原始碼建置。Release 預熱永遠只預熱普通二進位檔。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 和 `prefixMapping` 會變更您專案目標的建置設定和快取金鑰，以及其測試目標的選擇性測試雜湊。在所有共用快取的機器上將它們設定為相同的值，不要從環境衍生它們（例如從 `Environment.isCI`）：CI 和本機機器之間不同的值會導致不同的金鑰。環境變數也是如此：使用 `TUIST_COVERAGE_ENABLED=0` 的執行不會重複使用開啟涵蓋率執行的二進位檔或選擇性測試結果。

請記住：

- 檢測二進位檔較大：靜態歸檔和動態函式庫約大 20–30%。Debug 建置的執行速度相同。
- 無論是否啟用此選項，Xcode 的涵蓋率報告永遠不會顯示來自快取的程式碼。Tuist 的涵蓋率上傳會測量它。若要在 Xcode 中查看目標的涵蓋率，請使用 `tuist generate <target>` 聚焦該目標，使其從原始碼建置。

## 疑難排解 {#troubleshooting}

### 它沒有為我的目標使用二進位檔 {#it-doesnt-use-binaries-for-my-targets}

確保<.localized_link href="/guides/features/projects/hashing#debugging">雜湊值在不同環境與執行中具有一致性</.localized_link>。如果專案參考了環境（例如透過絕對路徑），就可能發生這種情況。您可以使用`diff`命令來比較兩次連續執行`tuist generate`所產生的專案，或是比較不同環境或執行之間的專案。

同時請確認目標沒有直接或間接相依於<.localized_link href="/guides/features/cache/module-cache#supported-products">無法快取的目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用原始碼時，Xcode 的建置系統可以透過 Derived Data 解析未明確宣告的相依性。然而，當您依賴二進位快取時，必須明確宣告相依性；否則當找不到符號時，您可能會看到編譯錯誤。為了除錯此問題，我們建議使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令，並在 CI 中設定它以防止隱式連結的回退。
