---
{
  "title": "模組快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "快取編譯後的二進位檔，並透過 Tuist Module Cache 在團隊間共享。"
}
---

# 模組快取 {#module-cache}

> [!IMPORTANT]
> **必要條件**
>
> - 一個<.localized_link href="/guides/features/projects">產生的專案</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的專案圖，以對目標進行雜湊並替換其二進位檔。

Tuist Module Cache 提供了一種強大的方式，透過將你的模組快取為二進位檔（`.xcframework`）並在不同環境之間共用，來最佳化建置時間。這項功能讓你能够利用先前產生的二進位檔，減少重複編譯的需求，並加速開發流程。若要了解快取移除了緩慢建置中的哪一部分，請參閱[緩慢建置](https://tuist.dev/solutions/slow-builds)。

> [!TIP]
> **與 Xcode 快取搭配使用**
>
> 模組快取與<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link>互補，因為它們在不同的粒度層級上運作。模組快取在建置執行前，以預先建置的 `.xcframework` 取代整個模組；而 Xcode 快取則在建置期間重複使用編譯輸出。
>
> 編譯快取設定不屬於模組快取雜湊的一部分，因此開啟或關閉 Xcode 快取會保留你已預熱的二進位檔。在 Xcode 27 及更新版本中，隨附的前綴對應設定會被納入雜湊。請參閱<.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取雜湊</.localized_link>。

## 預熱 {#warming}

Tuist 有效<.localized_link href="/guides/features/projects/hashing">利用雜湊</.localized_link>來偵測相依圖中每個目標的變更。利用這些資料，它會建置並為源自這些目標的二進位檔分配唯一識別碼。在產生圖時，Tuist 會無縫地以對應的二進位版本取代原始目標。

這項稱為 *「預熱」* 的作業會產生供本機使用，或透過 Tuist 與團隊成員及 CI 環境共用的二進位檔。預熱快取的過程簡單明瞭，只需執行一個指令即可啟動：

```bash
tuist cache
```

該指令會重複使用二進位檔以加速流程。

如果某個二進位檔上傳失敗，指令仍會上傳其餘項目，然後以非零狀態結束，並列出未上傳的目標。機器本機快取中的二進位檔會被視為已快取，因此若要從同一台機器再次上傳它們，請在預熱前執行 `tuist clean binaries`。傳遞 `--no-upload` 以僅將二進位檔儲存在本機快取中。

### 目的地選擇 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 來針對單一目的地進行快取、產生與測試：

```bash
tuist cache --destination simulator
tuist generate --destination simulator
tuist test --destination simulator

tuist cache --destination device
tuist generate --destination device
tuist test --destination device -- -destination 'platform=iOS,id=DEVICE_IDENTIFIER'
```

預設值為 `all`，這會保留你的目標所支援的所有目的地，包括 Mac Catalyst。後續的 `tuist cache` 會重複使用已快取的切片，並僅建置缺少的 SDK。一般產生會在缺少任何必要切片時保留模組的原始碼。

限制式產生會將原始碼目標限制為選定的目的地，並保留原生 macOS 目標，包括巨集。兩種限制模式都不包含 Mac Catalyst。使用 `--destination all` 重新產生以恢復所有目的地。

`tuist test --destination` 僅使用並下載所選目的地的切片，因此模擬器測試執行可以使用僅限模擬器或完整預熱的二進位檔。當傳遞給 `--` 之後的 `xcodebuild` 的目的地不符時會失敗，且 `--destination device` 需要裝置 `-destination`。選擇性測試雜湊不依賴目的地，因此具有不同 `--destination` 值的執行會共用測試結果。

逐切片快取支援具備標準架構的 iOS 與 macOS。其他平台、自訂架構以及不受支援的產品則維持完整構件快取。舊版模組快取一律下載完整構件，並在預熱時需要 `--destination all`。

### 遠端上傳准入 {#remote-upload-admission}

現代模組快取使用 REAPI。當忙碌的快取暫時以 `RESOURCE_EXHAUSTED` 拒絕上傳時，Tuist 會以抖動方式退避，遵守標準的 `google.rpc.RetryInfo` 最小延遲，並在有限的等待預算內重試。每次呼叫的上傳准入最多允許六次重試。每個 blob 上傳作業在其存在檢查、批次上傳和串流寫入之間共用一個 60 秒的累積退避預算；並行等待各自消耗預算，因此重複拒絕不會讓每個排隊的 blob 再獲得一分鐘的重試時間。成功的傳輸不會消耗此預算，且在預算耗盡時不會被取消。動作結果發布擁有其自身的有限預算。指數延遲從一秒開始，在向比例抖動過渡前增長至 30 秒。如果伺服器要求的延遲超過剩餘預算，Tuist 會失敗，而不是早於指示進行重試。取消會中斷退避，而快取讀取會保留短重試，以免過載導致產生停滯。

這些預設值也有助於沒有重試提示的較舊 Kura 版本。較長的重試能吸收暫時的爭用，而非持續的過載：如果拒絕持續發生，請降低預熱作業的[快取並行限制](#cache-concurrency-limit)，或增加伺服器容量。請參閱[Kura 上傳規模評估](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以取得 Pod 記憶體估算與准入指標。

### 組態選擇 {#configuration-selection}

在未傳遞 `--configuration` 的情況下預熱快取時，Tuist 會依下列順序選擇要使用的建置組態：

1. 清單 manifest 的 `Project.Options.generationOptions` 中設定的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體為 `debug` 的第一個建置組態，依名稱按字母順序排序。

若要為特定組態預熱快取，請明確傳遞該組態：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

預設情況下，當 Tuist 指令需要產生專案時，如果快取中有可用的二進位等效項目，它們會自動以這些項目取代相依性。此外，如果你指定要聚焦的目標清單，Tuist 也會以快取的二進位檔取代任何相依目標（前提是它們可用）。對於偏好不同做法的人，可以選擇使用特定旗標完全退出此行為：

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
> 二進位快取是一項專為開發工作流程設計的功能，例如在模擬器或裝置上執行應用程式，或執行測試。它不適用於發行版建置。在封存應用程式時，請使用 `--cache-profile none` 產生包含原始碼的專案。

## 快取設定檔 {#cache-profiles}

Tuist 支援快取設定檔，以控制在產生專案時以多積極的程度將目標替換為快取的二進位檔。

- 內建設定檔：
  - `only-external`：僅取代外部相依性（系統預設）
  - `all-possible`：盡可能取代更多目標（包括內部目標）
  - `none`：永不以快取的二進位檔取代

使用 `tuist generate` 上的 `--cache-profile` 選擇設定檔：

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
> `--no-binary-cache` 旗標已棄用。請改用 `--cache-profile none`。該已棄用的旗標仍為向後相容而有效。

解析有效行為時的優先順序（由高至低）：

1. `--cache-profile none`
2. 目標聚焦（將目標傳遞給 `generate`）→ 設定檔 `all-possible`
3. `--cache-profile <value>`
4. 組態預設值（若已設定）
5. 系統預設值（`only-external`）

## 支援的產品 {#supported-products}

Tuist 僅能快取下列目標產品：

- 框架（靜態與動態），包括相依於 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的測試支援框架
- 程式庫（靜態與動態），包括相依於 XCTest 或 Swift Testing 的測試支援程式庫
- Bundle
- Swift 巨集

測試 bundle 仍被排除在模組快取之外。這表示 `unitTests` 與 `uiTests` 目標不會以二進位檔形式快取，但測試所相依的一般框架與程式庫目標即使連結了 XCTest 或 Swift Testing，仍可被快取。

快取的程式庫 `.xcframework` 會保留產生專案匯入它們所需的詮釋資料，包括 Swift 模組，以及當來源目標宣告公開標頭時的公開 C/Objective-C 標頭。

> [!NOTE]
> **上游相依性**
>
> 當某個目標無法快取時，其上游目標也會變成無法快取。例如，若你有相依圖 `A > B`，其中 A 相依於 B，如果 B 無法快取，A 也無法快取。

## 分析 {#analytics}

在專案儀表板中開啟 **模組快取 → 模組**，找出經常未命中的模組。選擇你想改善的環境，例如 **CI**，以及日期範圍。概覽會顯示快取命中、未命中，以及有未命中的模組；開啟模組會顯示其歷史記錄，以及每次觀察所指派的原因。

**未命中**下拉式選單會選取某一原因的計數與說明。圖表顯示所有四種原因的分布。在模組頁面上，使用歷史記錄的 **原因**篩選器來檢查個別發生情況。將滑鼠懸停在原因徽章上，或使用鍵盤聚焦它，以查看其定義。

### 未命中原因 {#miss-reasons}

| 原因 | 意義 |
| --- | --- |
| **已變更** | 模組自身的比較輸入已變更。這些包括檔案雜湊、建置設定、已解析的組態，以及編譯器識別碼。原始碼編輯只是可能的原因之一。 |
| **上游** | 模組自身的比較輸入保持不變，但其相依性或外部套件的雜湊已變更。模組的原始碼檔案可能未被觸及。 |
| **冷啟動** | 沒有先前的模組觀察可供比較，或回報的輸入無法解釋未命中，且沒有符合條件的證據證明先前遠端可用性。冷啟動並不能證明該模組從未快取過。 |
| **已驅逐** | 確切的快取金鑰先前在同一專案的相同記錄快取端點上有遠端命中，但現在未命中。 |

對於標示為 **已驅逐** 的未命中，該構件先前已從遠端快取下載，但這次無法重複使用。驅逐是可能的原因，不過存取或下載失敗也可能導致未命中。Tuist 僅在找到先前的遠端命中時才會指派此標籤；先前的未命中和本地命中並不足夠。

例如：

| 情境 | 分類 |
| --- | --- |
| 模組未命中，且無先前的觀察或符合條件的遠端命中 | 冷啟動 |
| A 變更；B 相依於 A，而 C 相依於 B；三個金鑰皆變更 | A 為已變更；B 和 C 為上游 |
| 編譯器版本在快取預熱後變更，而原始碼與設定保持不變 | 當兩次觀察皆回報編譯器輸入時，受影響的未命中會歸類為已變更 |
| 確切的金鑰曾從遠端下載，但在其構件被驅逐後未命中 | 若先前的命中可作為證據，則歸類為已驅逐 |
| 某金鑰重複未命中，且從未成功預熱 | 它可能維持冷啟動狀態 |

原因用於描述觀察結果；它們並非附加在金鑰上的永久標籤。例如，編譯器升級後的第一次未命中可能是已變更，而該新金鑰後續的未命中若從未在遠端被觀察到可用，則可能是冷啟動。

### 提升快取命中率 {#improving-cache-hit-rate}

1. **選擇一致的基準。** 從 CI 和具有代表性的日期範圍開始。依未命中次數排序模組，然後考慮其命中率、相依者以及建置成本。修復經常未命中且昂貴的相依性，比提升微小模組的命中率更能節省時間。進行變更後，請比較相同的環境與類似的工作負載。
2. **調查已變更的未命中。** 開啟相關的執行記錄，並比較其完整金鑰與回報的輸入。將預熱與消費作業對齊至預期的 Xcode/編譯器版本、組態以及目標目的地。在有意圖的變更後再次預熱。若易變動的產生檔案或依賴環境的設定導致原本穩定的模組失效，請調查這些輸入。將影響二進位相容性的輸入保留在雜湊中。
3. **追蹤上游未命中以找到變更的相依性。** 檢查其歷史記錄以找出直接變更。預熱產生的金鑰可以恢復重用。若頻繁變更的實作導致許多昂貴的相依者失效，請考慮如[效率](#efficiency)所述，採用較小的模組或穩定的介面。
4. **檢查冷啟動未命中的預熱涵蓋範圍。** 驗證預熱是否選取了所需的模組、使用了消費作業的組態與環境，並成功上傳構件。檢查實際 CI 作業使用的完整金鑰。若預熱與消費請求不同的金鑰，請在假設快取被驅逐之前，先檢查雜湊輸入。即使模組的原始碼未變更，仍可能出現重複未命中且無先前成功上傳的情況。
5. **利用已驅逐未命中的證據。** 確認消費執行的金鑰與端點，然後檢查消費執行的快取警告以及預熱作業的上傳結果。視情況檢查保留或驅逐策略。重新預熱所需的構件，並驗證後續是否命中。若仍然未命中，請將相關的執行連結與日誌提供給支援團隊。

若要進行雜湊比較，請在你打算預熱與消費的每個相關環境中，使用該組態執行以下指令：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模組的完整雜湊與元件區塊。在相同且未變更的機器上重複執行指令，通常應產生相同的結果；比較實際的預熱與消費環境以調查不符之處。這兩個指令都不需要命中快取。如需進一步檢查，請參閱<.localized_link href="/guides/features/projects/hashing#debugging">雜湊診斷</.localized_link>。

## 效率 {#efficiency}

透過二進位快取所能達到的效率水準，很大程度上取決於圖結構。為了達到最佳結果，我們建議如下：

1. 避免非常巢狀的相依圖。圖層越淺越好。
2. 使用協定/介面目標來定義相依性，而非實作目標，並從最頂層的目標注入實作的相依性。
3. 將頻繁修改的目標拆分為較小的目標，以降低其變更的可能性。

上述建議屬於<.localized_link href="/guides/features/projects/tma-architecture">模組化架構</.localized_link>的一部分，我們提出此架構作為組織專案的方式，以最大化二進位快取與 Xcode 功能的效益。

## 建議設定 {#recommended-setup}

我們建議設定一個 CI 作業，**在 main 分支的每次提交中執行**以預熱快取。這將確保快取始終包含`main`中變更的二進位檔，以便本地與 CI 分支能夠在其基礎上進行增量建置。

> [!TIP]
> **保持快取預熱隔離**
>
> 在專用的 CI 步驟中執行`tuist cache`，且後續步驟不應依賴產生的工作區。由於`tuist cache`會為了快取建置目的而修改工作區，任何需要工作區的 CI 步驟都應先執行`tuist generate`以取得全新且可用的工作區。

> [!TIP]
> **快取預熱使用二進位檔**
>
> `tuist cache`指令也會利用二進位快取來加速預熱。

以下是一些常見工作流程的範例：

### 開發人員開始開發新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他們從`main`建立新分支。
2. 他們執行`tuist generate`。
3. Tuist 從`main`拉取最新的二進位檔，並用它們產生專案。

### 開發人員推送變更至上遊 {#a-developer-pushes-changes-upstream}

1. CI 流程將執行`xcodebuild build`或`tuist test`以建置或測試專案。
2. 工作流程將從`main`拉取最新的二進位檔，並用它們產生專案。
3. 接著它將增量建置或測試專案。

## 組態 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將`TUIST_CACHE_CONCURRENCY_LIMIT`設定為正整數以限制下載與上傳。例如，在預熱作業中減少小型自託管快取的負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

若未設定，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時，下載使用八個任務；僅限批次的計畫則使用 32 個。舊版 HTTP 快取路徑預設為 100；該預設不適用於 REAPI。無效值（包括先前文件記載的`none`）會保留預設值，而非移除限制。使用`unset TUIST_CACHE_CONCURRENCY_LIMIT`以恢復預設值。

限制適用於每次傳輸作業，而非全域適用於所有作業或 CI 工作。三次同時預熱且限制為二時，可能對同一快取進行六個上傳動作。消費者作業可以將變數保持未設定狀態，以保留預設的下載並行度。

### 快取預熱暫存目錄 {#cache-warm-scratch-directory}

預設情況下，`tuist cache`會建立一個暫存目錄來存放建置中介檔案與組裝好的快取產物，並在快取預熱完成後將其移除。若要將這些檔案保留在您管理的目錄下，請設定`TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑，也可以是相對於目前工作目錄的相對路徑。若目錄不存在，Tuist 會建立該目錄。若目錄已存在，則必須是空目錄。

當設定此環境變數時，Tuist 會在指令執行完畢後保留該目錄及其內容。呼叫者負責在下一次快取預熱前清理該目錄。當變數未設定時，Tuist 會繼續使用並移除暫存目錄。

當需要預熱外部建置目標時，Tuist 會拒絕使用由呼叫者擁有的暫存目錄。外部建置腳本控制其自身的輸出位置，因此 Tuist 無法保證這些輸出會留在暫存目錄內。

### 程式碼涵蓋率 {#code-coverage}

來自模組快取的目標是預先建置的二進位檔，只有在該二進位檔建置時啟用了涵蓋率計數器，測試執行才會測量其程式碼。本節說明快取如何處理涵蓋率；若要端到端設定涵蓋率，請參閱<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">程式碼涵蓋率</.localized_link>。在`Tuist.swift`中為您的專案開啟涵蓋率：

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

啟用`enabled`後，每個指令與每個環境都會讀取專案自身目標的單一插樁版快取，因此在 CI 上的一次預熱即可同時服務 CI 與本地機器：

| 指令 | 您專案的目標 | 外部套件 |
| --- | --- | --- |
| `tuist cache`（Debug 組態） | 預熱插樁二進位檔 | 預熱普通二進位檔 |
| `tuist cache`（Release 組態） | 預熱普通二進位檔 | 預熱普通二進位檔 |
| `tuist hash cache` | 列印插樁金鑰 | 列印普通金鑰 |
| `tuist generate` | 讀取插樁二進位檔 | 讀取普通二進位檔 |
| `tuist test` | 讀取插樁二進位檔 | 讀取普通二進位檔 |

此選項適用於 Xcode 視為 Debug 的每種組態。Release 建置從不進行插樁。Tuist 也會在這些組態中連結分析期執行階段（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使未收集涵蓋率的建置仍會連結插樁二進位檔，並在其自動產生的 Scheme 以及您定義但未設定`coverage`的 Scheme 之測試動作中開啟涵蓋率。

您定義的 Scheme 會遵循此選項，除非它自行設定涵蓋率：`.options(coverage: false)`會保持關閉，而`.options(coverage: true)`會保持開啟，無論選項為何。測試計畫自行決定涵蓋率，且`-enableCodeCoverage`仍會覆寫執行，如同在 Xcode 中一樣。讀取插樁二進位檔但未收集涵蓋率的執行會正常建置與測試。當執行收集涵蓋率，但您專案的目標來自快取且為普通二進位檔時，Tuist 會警告無法測量其涵蓋率。

`TUIST_COVERAGE_ENABLED`環境變數（`1`或`0`）優先於`coverage: .coverage(enabled:)`。請為整個環境（例如 CI 工作流程）設定此變數，而非僅針對單一指令，以使預熱快取的指令與讀取快取的指令保持一致。

`prefixMapping`（請參閱<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有其自身的覆寫機制：`TUIST_COVERAGE_PREFIX_MAPPING`環境變數（`1`或`0`）優先於`coverage: .coverage(prefixMapping:)`。

覆寫為關閉會讀取普通版本，而啟用涵蓋率預熱的快取不會填充該版本，因此這些目標會從原始碼建置。Release 預熱始終預熱普通二進位檔。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled`與`prefixMapping`會變更您專案目標的建置設定與快取金鑰，以及其測試目標的選擇性測試雜湊。在共享快取的每台機器上將它們設定為相同的值，不要從環境衍生它們（例如從`Environment.isCI`）：CI 與本地機器之間不同的值會導致金鑰不同。環境變數也是如此：使用`TUIST_COVERAGE_ENABLED=0`的執行不會重用啟用涵蓋率執行的二進位檔或選擇性測試結果。

請記住：

- 插樁二進位檔較大：靜態歸檔與動態函式庫約增加 20–30%。Debug 建置的執行速度相同。
- 無論是否啟用此選項，Xcode 的涵蓋率報告永遠不會顯示來自快取的程式碼。Tuist 的涵蓋率上傳會測量它。若要在 Xcode 中查看目標的涵蓋率，請使用`tuist generate <target>`聚焦該目標，使其從原始碼建置。

## 疑難排解 {#troubleshooting}

### 我的目標未使用二進位檔 {#it-doesnt-use-binaries-for-my-targets}

確保<.localized_link href="/guides/features/projects/hashing#debugging">雜湊在不同環境與執行中具有決定性</.localized_link>。如果專案參考了環境（例如透過絕對路徑），可能會發生這種情況。您可以使用`diff`指令來比較連續兩次呼叫`tuist generate`所產生的專案，或跨環境與執行進行比較。

同時確保目標沒有直接或間接依賴<.localized_link href="/guides/features/cache/module-cache#supported-products">不可快取的目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用原始碼時，Xcode 的建置系統透過 Derived Data 可以解析未明確宣告的相依性。然而，當您依賴二進位快取時，必須明確宣告相依性；否則當找不到符號時，您可能會看到編譯錯誤。為了除錯此問題，我們建議使用<.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link>指令，並在 CI 中設定它以防止隱式連結的回退。
