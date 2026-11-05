---
{
  "title": "模組快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "快取編譯後的二進制檔案，並透過 Tuist Module Cache 與你的團隊共享。"
}
---

# 模組快取 {#module-cache}

> [!WARNING]
> **必要條件**
>
> - 一個<.localized_link href="/guides/features/projects">已生成的專案</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的專案圖，以計算目標的雜湊並替換其二進制檔。

Tuist 模組快取提供強大的方法來優化建置時間，方法是將你的模組快取為二進制檔（`.xcframework`s）並在不同環境之間共用。此功能讓你能够利用先前產生的二進制檔，減少重複編譯的需要並加快開發流程。

> [!TIP]
> **與 Xcode 快取搭配使用**
>
> 模組快取與<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link>互補，因為它們在不同的粒度層級運作。模組快取在建置執行前以預先建置的 `.xcframework`s 替換整個模組，而 Xcode 快取則在建置期間重用編譯輸出。
>
> 編譯快取設定不屬於模組快取雜湊的一部分，因此開啟或關閉 Xcode 快取會保留你已經預熱的二進制檔。在 Xcode 27 及之後版本，隨附的前綴對應設定會被納入雜湊。請參閱<.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取雜湊</.localized_link>。

## 預熱 {#warming}

Tuist 有效率地<.localized_link href="/guides/features/projects/hashing">使用雜湊</.localized_link>來偵測相依圖中每個目標的變更。利用這些資料，它會建置並為衍生自這些目標的二進制檔分配唯一識別碼。在圖生成時，Tuist 會無縫地以對應的二進制版本替換原始目標。

這個稱為 *「預熱」* 的操作會產生供本地使用或透過 Tuist 與隊友及 CI 環境共用的二進制檔。預熱快取的過程很直接，可以使用一個簡單的指令啟動：

```bash
tuist cache
```

該指令會重用二進制檔以加快處理速度。

如果某個二進制檔上傳失敗，指令仍會上傳其餘部分，然後以非零狀態退出並列出未上傳的目標。機器本地快取中的二進制檔算作已快取，因此要從同一台機器再次上傳它們，請在預熱前執行 `tuist clean binaries`。傳遞 `--no-upload` 以僅將二進制檔儲存在本地快取中。

### 目的地選擇 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 來快取、生成並測試單一目的地：

```bash
tuist cache --destination simulator
tuist generate --destination simulator
tuist test --destination simulator

tuist cache --destination device
tuist generate --destination device
tuist test --destination device -- -destination 'platform=iOS,id=DEVICE_IDENTIFIER'
```

預設值是 `all`，它會保留你的目標支援的所有目的地，包括 Mac Catalyst。後續的 `tuist cache` 會重用已快取的切片並僅建置缺少的 SDK。常規生成會在缺少任何所需切片時保留模組的原始碼。

限制生成會將原始碼目標限制為所選目的地，並保留原生 macOS 目標，包括巨集。兩種限制模式都不包括 Mac Catalyst。使用 `--destination all` 重新生成以恢復所有目的地。

`tuist test --destination` 僅使用和下載所選目的地的切片，因此模擬器測試執行可以使用僅模擬器或完整預熱的二進制檔。當傳遞給 `--` 之後的 `xcodebuild` 的目的地不相符時會失敗，且 `--destination device` 需要裝置 `-destination`。選擇性測試雜湊不依賴目的地，因此具有不同 `--destination` 值的執行會共用測試結果。

逐切片快取支援具有標準架構的 iOS 和 macOS。其他平台、自訂架構和不支援的產品則保持完整構件快取。舊版模組快取始終下載完整構件，並在預熱時需要 `--destination all`。

### 遠端上傳准入 {#remote-upload-admission}

現代模組快取使用 REAPI。當繁忙的快取暫時以 `RESOURCE_EXHAUSTED` 拒絕上傳時，Tuist 會帶有抖動地退避，遵守標準的 `google.rpc.RetryInfo` 最小延遲，並在有限的等待預算內重試。上傳准入允許每次呼叫最多六次重試。每個 blob 上傳操作在其存在檢查、批次上傳和串流寫入之間共用一個 60 秒的累計退避預算；並發等待各自消耗預算，因此重複拒絕不會讓每個排隊的 blob 再獲得一分鐘的重試時間。成功的傳輸不會消耗此預算，且在預算用盡時不會被取消。動作結果發布有其自身的有限預算。指數延遲從一秒開始，在向比例抖動之前增長至 30 秒。如果伺服器要求的延遲超過剩餘預算，Tuist 會失敗而不是早於指示進行重試。取消會中斷退避，且快取讀取保留短重試，以免過載導致生成停滯。

這些預設值也有助於沒有重試提示的較舊 Kura 版本。較長的重試吸收的是暫時性爭用，而非持續過載：如果拒絕持續存在，請減少預熱作業上的[快取並發限制](#cache-concurrency-limit)或增加伺服器容量。請參閱[Kura 上傳規模估算](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以獲取 Pod 記憶體估算和准入指標。

### 組態選擇 {#configuration-selection}

當在不傳遞 `--configuration` 的情況下預熱快取時，Tuist 會按以下順序選擇要使用的建置組態：

1. 你的 manifest 中 `Project.Options.generationOptions` 設定的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體 `debug` 的第一個建置組態，按名稱字母順序排序。

要為特定組態預熱快取，請明確傳遞：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

預設情況下，當 Tuist 指令需要專案生成時，如果可用，它們會自動用快取中的二進制等效項替換相依性。此外，如果你指定要專注的目標列表，Tuist 也會用其快取的二進制檔替換任何相依目標，前提是它們可用。對於偏好不同方法的人，有一個選項可以使用特定旗標完全退出此行為：

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
> 二進制快取是專為開發工作流程設計的功能，例如在模擬器或裝置上運行應用程式，或運行測試。它不適用於發行版建置。在歸檔應用程式時，請使用 `--cache-profile none` 生成包含原始碼的專案。

## 快取設定檔 {#cache-profiles}

Tuist 支援快取設定檔，以控制在生成專案時替換目標為快取二進制檔的積極程度。

- 內建：
  - `only-external`：僅替換外部相依性（系統預設）
  - `all-possible`：盡可能替換更多目標（包括內部目標）
  - `none`：從不使用快取二進制檔替換

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
> `--no-binary-cache` 旗標已棄用。請改用 `--cache-profile none`。該已棄用的旗標仍可用於向後相容。

解析有效行為時的優先順序（由高到低）：

1. `--cache-profile none`
2. 目標焦點（將目標傳遞給 `generate`）→ 設定檔 `all-possible`
3. `--cache-profile <value>`
4. 組態預設值（如有設定）
5. 系統預設值（`only-external`）

## 支援的產品 {#supported-products}

只有以下目標產品可由 Tuist 快取：

- 框架（靜態和動態），包括依賴 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的測試支援框架
- 程式庫（靜態和動態），包括依賴 XCTest 或 Swift Testing 的測試支援程式庫
- Bundle
- Swift Macros

測試 bundle 仍被排除在模組快取之外。這表示 `unitTests` 和 `uiTests` 目標不會以二進制檔形式快取，但測試所依賴的一般框架和程式庫目標即使連結了 XCTest 或 Swift Testing 仍可被快取。

快取的程式庫 `.xcframework` 會保留生成專案匯入它們所需的元資料，包括 Swift 模組以及當原始目標宣告公開標頭時的公開 C/Objective-C 標頭。

> [!NOTE]
> **上游相依性**
>
> 當一個目標不可快取時，其上游目標也會變成不可快取。例如，如果你有相依性圖 `A > B`，其中 A 依賴 B，如果 B 不可快取，A 也將不可快取。

## 分析 {#analytics}

在專案儀表板中開啟 **模組快取 → 模組** 以找出經常未命中的模組。選擇你想要改善的環境，例如 **CI**，以及日期範圍。概覽顯示快取命中、未命中以及有未命中的模組；開啟模組會顯示其歷史記錄以及每次觀察分配的原因。

**未命中** 下拉選單可選擇一個原因的数量和解釋。圖表顯示所有四個原因的分布。在模組頁面上，使用歷史記錄的 **原因** 篩選器來檢查個別事件。將滑鼠懸停在原因徽章上，或使用鍵盤聚焦它，以查看其定義。

### 未命中原因 {#miss-reasons}

| 原因 | 意義 |
| --- | --- |
| **已變更** | 模組自身的比較輸入已變更。這些包括檔案雜湊、建置設定、解析後的組態以及編譯器識別碼。原始碼編輯只是可能的原因之一。 |
| **上游** | 模組自身的比較輸入保持不變，但其相依性或外部套件的雜湊已變更。模組的原始檔可能未被觸及。 |
| **冷啟動** | 沒有早期的模組觀察可供比較，或者報告的輸入無法解釋未命中，且沒有符合條件的早期遠端可用性證據。冷啟動並不能證明該模組從未被快取。 |
| **已驅逐** | 精確的快取金鑰先前在同一專案的相同記錄快取端點曾有遠端命中，但現在未命中。 |

對於標記為 **已驅逐** 的未命中，該構件先前已從遠端快取下載，但這次無法重用。驅逐是可能的原因，儘管存取或下載失敗也可能解釋未命中。Tuist 僅在找到早期的遠端命中時才會分配此標籤；先前的未命中和本地命中並不足夠。

例如：

| 情境 | 分類 |
| --- | --- |
| 模組未命中，且沒有早期觀察或符合條件的遠端命中 | 冷啟動 |
| A 變更；B 依賴 A，而 C 依賴 B；所有三個金鑰都變更 | A 為已變更；B 和 C 為上游 |
| 預熱後編譯器版本變更，原始碼和設定保持不變 | 當兩次觀察都報告編譯器輸入時，受影響的未命中為已變更 |
| 精確金鑰已從遠端下載，然後在其構件被驅逐後未命中 | 已驅逐（當早期命中符合證據條件時） |
| 金鑰重複未命中，且從未成功預熱 | 可能保持冷啟動狀態 |

原因描述觀察結果；它們不是附加在金鑰上的永久標籤。例如，編譯器升級後的第一次未命中可能是「已變更」，而如果該新金鑰從未被觀察為遠端可用，則後續的未命中可能是「冷啟動」。

### 提升快取命中率 {#improving-cache-hit-rate}

1. **選擇一致的基準。** 從 CI 和具代表性的日期範圍開始。按未命中次數對模組排序，然後考慮其命中率、依賴者和建置成本。修復經常未命中且昂貴的依賴項，比提升微小模組的命中率更能節省時間。在進行更改後，比較相同的環境和類似的工作負載。
2. **調查「已變更」未命中。** 開啟相關的執行記錄，並比較其完整金鑰和報告的輸入。將預熱和使用工作對齊到預期的 Xcode/編譯器版本、組態和目標目的地。在有意更改後再次預熱。如果易變的生成檔案或依賴環境的設定使原本穩定的模組失效，請調查這些輸入。將影響二進位相容性的輸入保留在雜湊中。
3. **追蹤「上游」未命中至已變更的依賴項。** 檢查其歷史記錄以找到直接變更。預熱產生的金鑰可以恢復重用。如果頻繁變更的實作使許多昂貴的依賴項失效，請考慮使用較小的模組或穩定的介面，如 [效率](#efficiency) 部分所述。
4. **檢查「冷啟動」未命中的預熱覆蓋範圍。** 驗證預熱是否選擇了所需的模組，使用了使用工作的組態和環境，並成功上傳了構件。檢查實際 CI 工作使用的完整金鑰。如果預熱和使用請求不同的金鑰，請在假設快取被驅逐之前檢查雜湊輸入。即使模組的原始碼沒有變更，也可能出現重複未命中且沒有早期成功上傳的情況。
5. **利用「已驅逐」未命中的證據。** 確認使用執行的金鑰和端點，然後檢查使用執行的快取警告和預熱工作的上傳結果。在適用時檢查保留或驅逐情況。重新預熱所需的構件並驗證後續命中。如果仍然未命中，請與支援團隊分享相關的執行連結和日誌。

要進行雜湊比較，請在每個相關環境中使用你打算預熱和使用的組態運行以下命令：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模組的完整雜湊和組件區塊。在同一台未變更的機器上重複命令通常應產生相同的結果；比較實際的預熱和使用環境以調查不匹配。這兩個命令都不需要命中快取。有關進一步檢查，請參閱 <.localized_link href="/guides/features/projects/hashing#debugging">雜湊診斷</.localized_link>。

## 效率 {#efficiency}

透過二進位快取可達到的效率水平很大程度上取決於圖結構。為了達到最佳結果，我們建議以下做法：

1. 避免非常嵌套的依賴圖。圖層越淺越好。
2. 使用協議/介面目標而不是實作目標來定義依賴項，並從最頂層目標注入依賴實作。
3. 將頻繁修改的目標拆分為更小的目標，以降低變更的可能性。

上述建議是 <.localized_link href="/guides/features/projects/tma-architecture">模組化架構</.localized_link> 的一部分，我們建議以此方式組織你的專案，以最大化二進位快取和 Xcode 功能的效益。

## 建議設定 {#recommended-setup}

我們建議設置一個 CI 工作，**在 main 分支的每次提交中運行** 以預熱快取。這將確保快取始終包含 `main` 中變更的二進位檔，以便本地和 CI 分支在其基礎上進行增量建置。

> [!TIP]
> **保持快取預熱隔離**
>
> 在專用的 CI 步驟中運行 `tuist cache`，不要有依賴生成工作區的後續步驟。由於 `tuist cache` 會為了快取建置目的而修改工作區，任何需要工作區的 CI 步驟都應先運行 `tuist generate` 以獲得全新且可用的工作區。

> [!TIP]
> **快取預熱使用二進位檔**
>
> `tuist cache` 命令也利用二進位快取來加速預熱。

以下是一些常見工作流程的示例：

### 開發人員開始開發新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他們從 `main` 建立新分支。
2. 他們運行 `tuist generate`。
3. Tuist 從 `main` 拉取最新的二進位檔並用它們生成專案。

### 開發人員推送變更至上游 {#a-developer-pushes-changes-upstream}

1. CI 管道將運行 `xcodebuild build` 或 `tuist test` 來建置或測試專案。
2. 工作流程將從 `main` 拉取最新的二進位檔並用它們生成專案。
3. 然後它將增量建置或測試專案。

## 組態 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將 `TUIST_CACHE_CONCURRENCY_LIMIT` 設置為正整數以限制下載和上傳。例如，減少預熱工作中小型自託管快取的負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

未設置時，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時，下載使用八個任務；對於僅批處理計劃，則使用 32 個。舊版 HTTP 快取路徑預設為 100；該預設不適用於 REAPI。無效值（包括先前記錄的 `none`）會保留預設值而不是移除限制。使用 `unset TUIST_CACHE_CONCURRENCY_LIMIT` 恢復預設值。

限制適用於每次傳輸操作，而不是全局適用於所有操作或 CI 工作。三個同時進行的預熱工作，限制為二，可能對同一快取有六個活躍的上傳。消費者工作可以留空該變量以保留預設的下載並行性。

### 快取預熱暫存目錄 {#cache-warm-scratch-directory}

預設情況下，`tuist cache` 會為建置中間產品和組裝的快取構件建立一個臨時暫存目錄，然後在快取預熱完成時將其刪除。若要將這些檔案保留在你管理的目錄下，請設置 `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑，也可以是相對於目前工作目錄的相對路徑。若目錄不存在，Tuist 會建立該目錄。若目錄已存在，則必須是空目錄。

設置此環境變量後，命令完成時 Tuist 會保留目錄及其內容。呼叫者負責在下一次快取預熱前清理它。當變量未設置時，Tuist 會繼續使用並刪除臨時目錄。

當需要預熱外部建置目標時，Tuist 會拒絕使用由呼叫者擁有的暫存目錄。外部建置腳本控制其自身的輸出位置，因此 Tuist 無法保證這些輸出會保留在暫存目錄內。

### 程式碼涵蓋率 {#code-coverage}

來自模組快取的目標是預先建置的二進位檔，只有在該二進位檔建置時啟用了涵蓋率計數器，測試執行才會測量其程式碼。本節說明快取如何處理涵蓋率；若要端到端設置涵蓋率，請參閱 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">程式碼涵蓋率</.localized_link>。在 `Tuist.swift` 中為你的專案啟用涵蓋率：

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

啟用 `enabled` 後，每個命令和每個環境都會讀取專案自身目標的單一插樁版快取，因此在 CI 上的一次預熱即可同時服務 CI 和本地機器：

| 命令 | 你專案的目標 | 外部套件 |
| --- | --- | --- |
| `tuist cache`（Debug 組態） | 預熱插樁二進位檔 | 預熱普通二進位檔 |
| `tuist cache`（Release 組態） | 預熱普通二進位檔 | 預熱普通二進位檔 |
| `tuist hash cache` | 列印插樁金鑰 | 列印普通金鑰 |
| `tuist generate` | 讀取插樁二進位檔 | 讀取普通二進位檔 |
| `tuist test` | 讀取插樁二進位檔 | 讀取普通二進位檔 |

此選項適用於 Xcode 視為 Debug 的每種組態。Release 建置從不進行插樁。Tuist 也會在這些組態中連結設定檔運行時（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使不收集涵蓋率的建置仍會連結插樁二進位檔，並在其自動生成的 Scheme 以及你定義但未設置 `coverage` 的 Scheme 的測試動作中啟用涵蓋率。

你定義的 Scheme 會遵循此選項，除非它自行設置涵蓋率：`.options(coverage: false)` 會保持關閉，而 `.options(coverage: true)` 會保持開啟，無論選項如何規定。測試計劃自行決定涵蓋率，而 `-enableCodeCoverage` 仍會覆蓋單次執行，如同在 Xcode 中一樣。讀取插樁二進位檔但不收集涵蓋率的執行會正常建置和測試。當執行收集涵蓋率，但你專案的目標來自快取且為普通二進位檔時，Tuist 會警告無法測量其涵蓋率。

`TUIST_COVERAGE_ENABLED` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(enabled:)`。請為整個環境（例如 CI 工作流程）設置它，而不是為單一命令設置，以使預熱快取的命令與讀取快取的命令保持一致。

`prefixMapping`（參見 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有其自身的覆蓋設置：`TUIST_COVERAGE_PREFIX_MAPPING` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(prefixMapping:)`。

覆蓋為關閉會讀取普通版本，而啟用涵蓋率預熱的快取不會填充該版本，因此這些目標會從原始碼建置。Release 預熱始終預熱普通二進位檔。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 和 `prefixMapping` 會更改你專案目標的建置設置和快取金鑰，以及其測試目標的選擇性測試雜湊。在所有共用快取的機器上將它們設置為相同的值，不要從環境衍生它們（例如從 `Environment.isCI`）：CI 和本地機器之間不同的值會導致不同的金鑰。環境變量也是如此：使用 `TUIST_COVERAGE_ENABLED=0` 的執行不會重用啟用涵蓋率執行的二進位檔或選擇性測試結果。

請記住：

- 插樁二進位檔較大：靜態歸檔和動態庫大約增加 20–30%。Debug 建置以相同速度運行。
- 無論是否啟用此選項，Xcode 的涵蓋率報告從不顯示來自快取的程式碼。Tuist 的涵蓋率上傳會測量它。若要在 Xcode 中查看目標的涵蓋率，請使用 `tuist generate <target>` 聚焦該目標，以便從原始碼建置。

## 疑難排解 {#troubleshooting}

### 它沒有為我的目標使用二進位檔 {#it-doesnt-use-binaries-for-my-targets}

確保 <.localized_link href="/guides/features/projects/hashing#debugging">雜湊是確定性的</.localized_link>，跨越不同環境和執行。如果專案引用了環境（例如通過絕對路徑），可能會發生這種情況。你可以使用 `diff` 命令來比較兩次連續調用 `tuist generate` 生成的專案，或跨環境或執行進行比較。

還要確保目標不直接或間接依賴於 <.localized_link href="/guides/features/cache/module-cache#supported-products">不可快取的目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用原始碼時，Xcode 的建置系統可以通過 Derived Data 解析未明確聲明的依賴關係。然而，當你依賴二進位快取時，必須明確聲明依賴關係；否則，當找不到符號時，你很可能會看到編譯錯誤。為了調試此問題，我們建議使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令，並在 CI 中設置它以防止隱式連結的回退。
