---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Cache compiled binaries and share them across your team with Tuist Module Cache."
}
---

# 模組快取 {#module-cache}

> [!WARNING]
> **必要條件**
>
> - <.localized_link href="/guides/features/projects">已生成的項目</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的項目圖，以對目標進行雜湊並替換其二進制檔。

Tuist Module Cache 提供了一種強大的方法來最佳化建置時間，方法是將你的模組快取為二進位檔（`.xcframework`）並在不同環境之間共用。此功能讓你能夠利用先前產生的二進位檔，減少重複編譯的需求並加速開發流程。

> [!TIP]
> **與 Xcode 快取結合使用**
>
> 模組快取與 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 互為補充，因為它們在不同的粒度層級上運作。模組快取會在建構執行前，將整個模組替換為預先建構的 `.xcframework`，而 Xcode 快取則在建構期間重用編譯輸出。
>
> 編譯快取設定並非模組快取雜湊的一部分，因此開啟或關閉 Xcode 快取仍會保留你已預熱的二進制檔。在 Xcode 27 及更高版本中，隨附的前綴映射設定也會被雜湊。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取雜湊</.localized_link>。

## 預熱 {#warming}

Tuist 會有效 <.localized_link href="/guides/features/projects/hashing">利用雜湊</.localized_link> 來偵測依賴關係圖中每個目標的變更。利用這些資料，它會為源自這些目標的二進制檔進行建構並分配唯一識別碼。在圖生成時，Tuist 會無縫地將原始目標替換為其對應的二進制版本。

此操作稱為 *「預熱」*，會產生用於本機使用或透過 Tuist 與團隊成員及 CI 環境共用的二進位檔。預熱快取的過程很簡單，可以使用一個簡單的指令來啟動：

```bash
tuist cache
```

該指令會重複使用二進位檔以加速處理程序。

如果某個二進位檔上傳失敗，指令仍會上傳其餘部分，然後以非零狀態退出並列出未上傳的目標。機器本機快取中的二進位檔被視為已快取，因此若要從同一台機器再次上傳它們，請在預熱之前執行 `tuist clean binaries`。傳遞 `--no-upload` 以僅將二進位檔儲存在本機快取中。

### 目的地選擇 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 來為單一目的地進行快取和生成：

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

預設值是 `all`，它會保留你的目標支援的所有目的地，包括 Mac Catalyst。後續的 `tuist cache` 會重複使用已快取的切片並僅建置缺少的 SDK。常規生成會在缺少任何所需切片時保留模組的原始碼。

限制性生成將來源目標限制為選定的目的地，並保留原生 macOS 目標，包括巨集。兩種限制模式都不包含 Mac Catalyst。使用 `--destination all` 重新生成以還原所有目的地。

逐切片快取支援具有標準架構的 iOS 和 macOS。其他平台、自訂架構和不支援的產品則保持完整工件快取。舊版模組快取需要 `--destination all`。

### 遠端上傳准入 {#remote-upload-admission}

現代模組快取使用 REAPI。當繁忙的快取暫時以 `RESOURCE_EXHAUSTED` 拒絕上傳時，Tuist 會以抖動方式退避，遵守標準的 `google.rpc.RetryInfo` 最小延遲，並在有限的等待預算內重試。每次呼叫的上傳准入最多允許六次重試。每個 blob 上傳操作在其存在檢查、批次上傳和串流寫入之間共用一個 60 秒的累計退避預算；並行等待各自消耗預算，因此重複拒絕不會讓每個排隊的 blob 再獲得一分鐘的重試時間。成功的傳輸不會消耗此預算，也不會在預算耗盡時被取消。動作結果發布有其自己的有限預算。指數延遲從一秒開始，在向比例抖動增長之前趨向 30 秒。如果伺服器要求的延遲超過剩餘預算，Tuist 會失敗而不是比指示更早重試。取消會中斷退避，而快取讀取會保留短重試，以免過載導致生成停滯。

這些預設值也有助於沒有重試提示的較舊 Kura 版本。較長的重試吸收的是暫時性競爭，而非持續性過載：如果拒絕持續發生，請降低暖作業上的[快取並發限制](#cache-concurrency-limit)或增加伺服器容量。請參閱[Kura 上傳規模調整](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以取得 Pod 記憶體估算和准入指標。

### 組態選擇 {#configuration-selection}

當在不傳遞 `--configuration` 的情況下預熱快取時，Tuist 會按照以下順序選擇要使用的建置組態：

1. 在你的 manifest 的 `Project.Options.generationOptions` 中設定的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體 `debug` 的第一個建置組態，按名稱字母順序排序。

若要為特定組態預熱快取，請明確傳遞它：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

預設情況下，當 Tuist 指令需要專案生成時，它們會自動用快取中的二進位等效項替換依賴項（如果可用）。此外，如果你指定要專注的目標清單，Tuist 也會用其快取的二進位檔替換任何依賴目標，前提是它們可用。對於偏好不同方法的人，有一個選項可以透過使用特定旗標完全退出此行為：

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
> 二進位快取是一項專為開發工作流程設計的功能，例如在模擬器或裝置上執行應用程式，或執行測試。它不適用於發行版建置。在歸檔應用程式時，請使用 `--cache-profile none` 生成包含原始碼的專案。

## 快取設定檔 {#cache-profiles}

Tuist 支援快取設定檔，以控制在生成專案時目標被快取二進位檔替換的積極程度。

- 內建：
  - `only-external`：僅替換外部依賴項（系統預設）
  - `all-possible`：盡可能替換更多目標（包括內部目標）
  - `none`：永遠不用快取二進位檔替換

在 `tuist generate` 上使用 `--cache-profile` 選擇設定檔：

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
> `--no-binary-cache` 旗標已棄用。請改用 `--cache-profile none`。已棄用的旗標仍可向後相容運作。

解析有效行為時的優先順序（從高到低）：

1. `--cache-profile none`
2. 目標焦點（將目標傳遞給 `generate`）→ 設定檔 `all-possible`
3. `--cache-profile <value>`
4. 組態預設值（如果已設定）
5. 系統預設值（`only-external`）

## 支援的產品 {#supported-products}

只有以下目標產品可由 Tuist 快取：

- Framework（靜態和動態），包括依賴 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的測試支援 Framework
- 程式庫（靜態和動態），包括依賴 XCTest 或 Swift Testing 的測試支援程式庫
- Bundle
- Swift Macros

測試 Bundle 仍被排除在模組快取之外。這意味著 `unitTests` 和 `uiTests` 目標不會以二進位檔形式快取，但測試所依賴的一般 Framework 和程式庫目標即使連結了 XCTest 或 Swift Testing 也可以被快取。

快取的程式庫 `.xcframework` 會保留生成專案匯入它們所需的元數據，包括當原始目標宣告公開標頭時的 Swift 模組和公開 C/Objective-C 標頭。

> [!NOTE]
> **上游依賴項**
>
> 當一個目標不可快取時，它也會使上游目標變得不可快取。例如，如果你有依賴圖 `A > B`，其中 A 依賴於 B，如果 B 不可快取，A 也將不可快取。

## 分析 {#analytics}

在專案的儀表板中開啟 **模組快取 → 模組** 以找出經常未命中的模組。選擇你想要改善的環境，例如 **CI**，以及日期範圍。概覽顯示快取命中、未命中和有未命中的模組；開啟模組會顯示其歷史記錄和分配給每個觀察的原因。

**未命中** 下拉式選單選擇一個原因的数量和解釋。圖表顯示所有四個原因的分布。在模組頁面上，使用歷史記錄的 **原因** 篩選器來檢查個別事件。將滑鼠懸停在原因徽章上，或使用鍵盤聚焦它以查看其定義。

### 未命中原因 {#miss-reasons}

| 原因 | 含義 |
| --- | --- |
| **已變更** | 模組自身的比較輸入已變更。這些包括檔案雜湊、建置設定、解析後的組態和編譯器識別碼。原始碼編輯只是可能的原因之一。 |
| **上游** | 模組自身的比較輸入保持不變，但其依賴項或外部套件的雜湊已變更。模組的原始檔可以 untouched。 |
| **冷啟動** | 沒有早期的模組觀察可供比較，或者報告的輸入無法解釋未命中，且沒有合格的早期遠端可用性證據。冷啟動並不能證明該模組從未快取過。 |
| **已驅逐** | 確切的快取金鑰先前在同一專案的相同記錄快取端點上有遠端命中，但現在未命中。 |

對於標記為 **已驅逐** 的未命中，構件先前已從遠端快取下載，但這次無法重用。驅逐是可能的原因，儘管存取或下載失敗也可以解釋未命中。Tuist 僅在找到早期的遠端命中時才分配此標籤；先前的未命中和本地命中是不夠的。

例如：

| 情境 | 分類 |
| --- | --- |
| 模組未命中，沒有早期觀察或合格的遠端命中 | 冷啟動 |
| A 變更；B 依賴於 A，C 依賴於 B；所有三個金鑰都變更 | A 是已變更；B 和 C 是上游 |
| 預熱後編譯器版本變更，原始碼和設定不變 | 當兩個觀察都報告編譯器輸入時，受影響的未命中是已變更 |
| 確切的金鑰已從遠端下載，然後在其構件被驅逐後未命中 | 已驅逐，當早期的命中符合證據資格時 |
| 金鑰反覆未命中且從未成功預熱 | 它可以保持冷啟動 |

原因描述觀察結果；它們不是附加在金鑰上的永久標籤。例如，編譯器升級後的第一次未命中可能是「已變更」，而如果該新金鑰從未在遠端被觀察到可用，則後續的未命中可能是「冷啟動」。

### 提高快取命中率 {#improving-cache-hit-rate}

1. **選擇一致的基準。** 從 CI 和具代表性的日期範圍開始。按未命中次數對模組進行排序，然後考慮它們的命中率、依賴項和建置成本。修復經常未命中的昂貴依賴項比提高微小模組的命中率更能節省時間。在進行更改後，比較相同的環境和類似的工作負載。
2. **調查「已變更」未命中。** 開啟相關的運行並比較它們的完整金鑰和報告的輸入。將預熱和使用作業對齊到預期的 Xcode/編譯器版本、組態和目標目的地。在有意變更後再次預熱。如果易變的生成檔案或依賴環境的設定使原本穩定的模組失效，請調查這些輸入。將影響二進位相容性的輸入保留在雜湊中。
3. **追蹤「上游」未命中到已變更的依賴項。** 檢查其歷史記錄以找到直接變更。預熱產生的金鑰可以恢復重用。如果頻繁變更的實作使許多昂貴的依賴項失效，請考慮使用較小的模組或穩定的介面，如[效率](#efficiency)部分所述。
4. **檢查「冷啟動」未命中的預熱覆蓋範圍。** 驗證預熱是否選擇了所需的模組，使用了使用作業的組態和環境，並成功上傳了構件。檢查實際 CI 作業使用的完整金鑰。如果預熱和使用請求不同的金鑰，請在假設快取已被驅逐之前檢查雜湊輸入。即使模組的原始碼沒有變更，也可能出現反覆未命中且沒有早期成功上傳的情況。
5. **利用「已驅逐」未命中的證據。** 確認使用運行的金鑰和端點，然後檢查使用運行的快取警告和預熱作業的上傳結果。在適用的情況下檢查保留或驅逐。重新預熱所需的構件並驗證後續命中。如果仍然未命中，請與支援團隊分享相關的運行連結和日誌。

要進行雜湊比較，請在您打算預熱和使用的每個相關環境中執行此命令，並使用相應的組態：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模組的完整雜湊和元件區塊。在同一台未變更的機器上重複執行命令通常應產生相同的結果；比較實際的預熱和使用環境以調查不匹配。兩個命令都不需要命中快取。有關進一步檢查，請參閱<.localized_link href="/guides/features/projects/hashing#debugging">雜湊診斷</.localized_link>。

## 效率 {#efficiency}

透過二進位快取可以達到的效率水平很大程度上取決於圖形結構。為了達到最佳效果，我們建議以下幾點：

1. 避免非常嵌套的依賴圖。圖形越淺越好。
2. 使用協議/介面目標而不是實作目標來定義依賴項，並從最頂層目標依賴注入實作。
3. 將頻繁修改的目標拆分為較小的目標，以降低其變更的可能性。

上述建議是<.localized_link href="/guides/features/projects/tma-architecture">模組化架構</.localized_link>的一部分，我們建議將其作為建構專案的方式，以最大化二進位快取和 Xcode 功能的優勢。

## 推薦設定 {#recommended-setup}

我們建議有一個 CI 作業，**在主分支的每次提交中運行**以預熱快取。這將確保快取始終包含`main`中變更的二進位檔，以便本地和 CI 分支在其基礎上增量建置。

> [!TIP]
> **保持快取預熱隔離**
>
> 在專用的 CI 步驟中運行`tuist cache`，不要有依賴生成工作區的後續步驟。由於`tuist cache`會為了快取建置目的而修改工作區，任何需要工作區的 CI 步驟都應先運行`tuist generate`以獲得一個新的、可用的工作區。

> [!TIP]
> **快取預熱使用二進位檔**
>
> `tuist cache`命令也利用二進位快取來加速預熱。

以下是一些常見工作流程的範例：

### 開發人員開始處理新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他們從`main`建立一個新分支。
2. 他們運行`tuist generate`。
3. Tuist 從`main`拉取最新的二進位檔並用它們生成專案。

### 開發人員向上游推送變更 {#a-developer-pushes-changes-upstream}

1. CI 流水線將運行`xcodebuild build`或`tuist test`來建置或測試專案。
2. 工作流程將從`main`拉取最新的二進位檔並用它們生成專案。
3. 然後它將增量建置或測試專案。

## 組態 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將`TUIST_CACHE_CONCURRENCY_LIMIT`設定為正整數以限制下載和上傳。例如，減少預熱作業中小型自託管快取的負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

當未設定時，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時，下載使用八個任務；對於僅批次計劃，則使用 32 個任務。舊版 HTTP 快取路徑預設為 100；該預設不適用於 REAPI。無效值（包括先前記錄的`none`）會保留預設值而不是移除限制。使用`unset TUIST_CACHE_CONCURRENCY_LIMIT`來恢復預設值。

限制適用於每個傳輸操作，而不是全局跨操作或 CI 作業。三個同時進行的預熱作業，限制為二，可以有六個上傳活動針對同一個快取。消費者作業可以不設定變數以保留預設的下載並行性。

### 快取預熱暫存目錄 {#cache-warm-scratch-directory}

預設情況下，`tuist cache`會為建置中間產物和組裝的快取構件建立一個臨時暫存目錄，然後在快取預熱完成時將其刪除。若要將這些檔案保留在您管理的目錄下，請設定`TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑或相對於當前工作目錄的路徑。當目錄不存在時，Tuist 會建立該目錄。如果它已經存在，則必須是一個空目錄。

當設定此環境變數時，Tuist 會在命令完成後保留目錄及其內容。呼叫者負責在下一次快取預熱前清理它。當未設定變數時，Tuist 會繼續使用並刪除臨時目錄。

當需要預熱外部建置目標時，Tuist 會拒絕由呼叫者擁有的暫存目錄。外部建置腳本控制其自身的輸出位置，因此 Tuist 無法保證這些輸出會保留在暫存目錄內。

### 程式碼涵蓋率 {#code-coverage}

> [!NOTE] EARLY ACCESS
> 模組快取的程式碼涵蓋率功能處於早期存取階段。只有當設定 `TUIST_FEATURE_FLAG_COVERAGE=1` 時，命令才會讀取和預熱下述的檢測二進位檔。

來自模組快取的目標是預先建置的二進位檔，只有在該二進位檔是使用涵蓋率計數器建置的情況下，測試運行才會測量其程式碼。在 `Tuist.swift` 中為您的專案開啟涵蓋率：

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

使用 `enabled` 時，每個命令和每個環境都會讀取專案自身目標的其中一個檢測版快取，因此在 CI 上的一次預熱即可同時服務於 CI 和本地機器：

| 命令 | 您專案的目標 | 外部套件 |
| --- | --- | --- |
| `tuist cache`（Debug 組態） | 預熱檢測二進位檔 | 預熱普通二進位檔 |
| `tuist cache`（Release 組態） | 預熱普通二進位檔 | 預熱普通二進位檔 |
| `tuist hash cache` | 列印檢測金鑰 | 列印普通金鑰 |
| `tuist generate` | 讀取檢測二進位檔 | 讀取普通二進位檔 |
| `tuist test` | 讀取檢測二進位檔 | 讀取普通二進位檔 |

此選項適用於 Xcode 視為 Debug 的每種組態。Release 建置從不進行檢測。Tuist 也會在這些組態中連結分析執行時（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使未收集涵蓋率的建置仍會連結檢測二進位檔，並在其自動生成的方案以及您定義但未設定 `coverage` 的方案之測試動作中開啟涵蓋率。

您定義的方案會遵循此選項，除非它自行設定涵蓋率：`.options(coverage: false)` 會保持關閉，而 `.options(coverage: true)` 會保持開啟，無論選項如何規定。測試計劃自行決定涵蓋率，且 `-enableCodeCoverage` 仍會覆蓋運行，如同在 Xcode 中一樣。讀取檢測二進位檔但未收集涵蓋率的運行會正常建置和測試。當運行收集涵蓋率但您專案的目標來自快取且為普通二進位檔時，Tuist 會警告其涵蓋率未被測量。

`TUIST_COVERAGE_ENABLED` 環境變數（`1` 或 `0`）優先於 `coverage: .coverage(enabled:)`。請為整個環境（例如 CI 工作流程）而非單一命令設定它，以便預熱快取的命令與讀取快取的命令保持一致。

`prefixMapping`（參見 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有其自身的覆蓋設定：`TUIST_COVERAGE_PREFIX_MAPPING` 環境變數（`1` 或 `0`）優先於 `coverage: .coverage(prefixMapping:)`。

覆蓋為關閉會讀取普通版本，而開啟涵蓋率預熱的快取不會填充該版本，因此這些目標會從原始碼建置。Release 預熱始終預熱普通二進位檔。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 和 `prefixMapping` 會變更您專案目標的建置設定和快取金鑰，以及其測試目標的選擇性測試雜湊值。在所有共用快取的機器上將它們設定為相同的值，且不要從環境衍生它們（例如從 `Environment.isCI`）：CI 和本地機器之間不同的值會導致它們擁有不同的金鑰。環境變數也是如此：使用 `TUIST_COVERAGE_ENABLED=0` 的運行不會重用開啟涵蓋率運行的二進位檔或選擇性測試結果。

請記住：

- 檢測二進位檔較大：靜態歸檔和動態函式庫大約增加 20–30%。Debug 建置以相同速度運行。
- 無論是否使用此選項，Xcode 的涵蓋率報告從不顯示來自快取的程式碼。Tuist 的涵蓋率上傳會測量它。若要在 Xcode 中查看目標的涵蓋率，請使用 `tuist generate <target>` 聚焦該目標，使其從原始碼建置。

## 疑難排解 {#troubleshooting}

### 它沒有為我的目標使用二進位檔 {#it-doesnt-use-binaries-for-my-targets}

確保 <.localized_link href="/guides/features/projects/hashing#debugging">雜湊值是確定性的</.localized_link>，跨環境和運行皆然。如果專案引用了環境（例如透過絕對路徑），可能會發生這種情況。您可以使用 `diff` 命令來比較由兩次連續調用 `tuist generate` 生成的專案，或跨環境或運行進行比較。

同時確保目標不直接或間接依賴於 <.localized_link href="/guides/features/cache/module-cache#supported-products">不可快取的目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用原始碼時，Xcode 的建置系統透過 Derived Data 可以解析未明確聲明的依賴關係。然而，當您依賴二進位快取時，必須明確聲明依賴關係；否則，當找不到符號時，您可能會看到編譯錯誤。為了除錯此問題，我們建議使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令，並在 CI 中設定它以防止隱式連結的回退。
