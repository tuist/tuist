---
{
  "title": "模組快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "快取編譯後的二進制檔案，並透過 Tuist Module Cache 與團隊共享。"
}
---

# 模組快取 {#module-cache}

> [!WARNING]
> **要求**
>
> - 一個 <.localized_link href="/guides/features/projects">已生成的項目</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的項目圖，以計算目標的哈希值並替換其二進制文件。

Tuist 模組快取提供了一種強大的方法來優化構建時間，方法是將你的模組快取為二進制文件（`.xcframework`s）並在不同環境之間共享。此功能允許你利用之前生成的二進制文件，減少重複編譯的需要並加快開發過程。

> [!TIP]
> **與 Xcode 快取結合使用**
>
> 模組快取和 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link> 是互補的，因為它們在不同的粒度級別上工作。模組快取在構建運行之前用預構建的 `.xcframework`s 替換整個模組，而 Xcode 快取則在構建期間重用編譯輸出。
>
> 編譯快取設置不是模組快取哈希的一部分，因此開啟或關閉 Xcode 快取會保留你已經預熱的二進制文件。在 Xcode 27 及更高版本中，附帶的前綴映射設置會被哈希化。請參閱 <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取哈希</.localized_link>。

## 預熱 {#warming}

Tuist 有效地 <.localized_link href="/guides/features/projects/hashing">利用哈希</.localized_link> 來檢測依賴圖中每個目標的變化。利用這些數據，它構建並為源自這些目標的二進制文件分配唯一標識符。在圖生成時，Tuist 隨後無縫地用相應的二進制版本替換原始目標。

這個操作稱為 *「預熱」*，會生成用於本地使用或通過 Tuist 與團隊成員和 CI 環境共享的二進制文件。預熱快取的過程很簡單，可以通過一個簡單的命令啟動：

```bash
tuist cache
```

該命令重用二進制文件以加快過程。

如果某個二進制文件上傳失敗，該命令仍會上傳其餘文件，然後以非零狀態退出並列出未上傳的目標。機器本地快取中的二進制文件被視為已快取，因此要從同一台機器再次上傳它們，請在預熱之前運行 `tuist clean binaries`。傳遞 `--no-upload` 以僅將二進制文件存儲在本地快取中。

### 目標選擇 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 來為單一目標進行快取、生成和測試：

```bash
tuist cache --destination simulator
tuist generate --destination simulator
tuist test --destination simulator

tuist cache --destination device
tuist generate --destination device
tuist test --destination device -- -destination 'platform=iOS,id=DEVICE_IDENTIFIER'
```

默認值是 `all`，它保留你的目標支持的所有目標，包括 Mac Catalyst。後續的 `tuist cache` 會重用已快取的切片並僅構建缺少的 SDK。常規生成會在缺少任何所需切片時保留模組的源代碼。

受限生成將源目標限制為選定的目標，並保留原生 macOS 目標，包括宏。兩種受限模式都不包括 Mac Catalyst。使用 `--destination all` 重新生成以恢復所有目標。

`tuist test --destination` 僅使用和下載所選目標的切片，因此模擬器測試執行可以使用僅限模擬器或完整預熱的二進制文件。當傳遞給 `xcodebuild` 後 `--` 的目標不匹配時會失敗，並且 `--destination device` 需要設備 `-destination`。選擇性測試哈希不依賴於目標，因此具有不同 `--destination` 值的運行共享測試結果。

逐切片快取支持具有標準架構的 iOS 和 macOS。其他平台、自定義架構和不支持的產品保留完整工件快取。舊版模組快取始終下載完整工件，並在預熱時需要 `--destination all`。

### 遠程上傳准入 {#remote-upload-admission}

現代模組快取使用 REAPI。當繁忙的快取暫時拒絕帶有 `RESOURCE_EXHAUSTED` 的上傳時，Tuist 會帶有抖動地退避，遵守標準的 `google.rpc.RetryInfo` 最小延遲，並在有限的等待預算內重試。上傳准入允許每次調用最多六次重試。每個 blob 上傳操作在其存在檢查、批量上傳和流式寫入之間共享一個 60 秒的累積退避預算；併發等待各自消耗預算，因此重複拒絕不會給予每個排隊的 blob 另一分鐘的重試時間。成功的傳輸不消耗此預算，並且在預算用完時不會被取消。動作結果發布有其自己的有限預算。指數延遲從一秒開始，在向比例抖動之前增長到 30 秒。如果服務器要求的延遲超過剩餘預算，Tuist 會失敗而不是比指示更早地重試。取消會中斷退避，並且快取讀取保留短重試，以便過載不會阻礙生成。

這些默認值也有助於沒有重試提示的舊版 Kura。較長的重試吸收臨時爭用，而不是持續過載：如果拒絕持續存在，請減少暖作業上的 [快取併發限制](#cache-concurrency-limit) 或增加服務器容量。請參閱 [Kura 上傳大小調整](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing) 以獲取 pod 內存估計和准入指標。

### 配置選擇 {#configuration-selection}

當在不傳遞 `--configuration` 的情況下預熱快取時，Tuist 按以下順序選擇要使用的構建配置：

1. 清單的 `Project.Options.generationOptions` 中設置的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體 `debug` 的第一個構建配置，按名稱字母順序排序。

要為特定配置預熱快取，請顯式傳遞它：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

默認情況下，當 Tuist 命令需要項目生成時，它們會自動用快取中的二進制等效項替換依賴項（如果可用）。此外，如果你指定要關注的目標列表，Tuist 也會用其快取的二進制文件替換任何依賴目標（如果可用）。對於喜歡不同方法的人，有一個選項可以使用特定標誌完全退出此行為：

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
> 二進制快取是一項專為開發工作流程設計的功能，例如在模擬器或設備上運行應用程序，或運行測試。它不適用於發布構建。歸檔應用程序時，請使用 `--cache-profile none` 生成包含源代碼的項目。

## 快取配置文件 {#cache-profiles}

Tuist 支持快取配置文件，以控制在生成項目時替換目標為快取二進制文件的積極程度。

- 內置：
  - `only-external`：僅替換外部依賴項（系統默認）
  - `all-possible`：盡可能多地替換目標（包括內部目標）
  - `none`：從不使用快取的二進制文件替換

在 `tuist generate` 上使用 `--cache-profile` 選擇配置文件：

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
> **已棄用的標誌**
>
> `--no-binary-cache` 標誌已棄用。請改用 `--cache-profile none`。該已棄用的標誌仍可用於向後兼容。

解析有效行為時的優先級（從高到低）：

1. `--cache-profile none`
2. 目標聚焦（將目標傳遞給 `generate`）→ 配置文件 `all-possible`
3. `--cache-profile <value>`
4. 配置默認值（如果已設置）
5. 系統默認值（`only-external`）

## 支持的產品 {#supported-products}

只有以下目標產品可由 Tuist 快取：

- 框架（靜態和動態），包括依賴 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的測試支持框架
- 庫（靜態和動態），包括依賴 XCTest 或 Swift Testing 的測試支持庫
- Bundle
- Swift Macros

測試 Bundle 仍被排除在模塊快取之外。這意味著 `unitTests` 和 `uiTests` 目標不會作為二進制文件快取，但測試所依賴的常規框架和庫目標即使鏈接了 XCTest 或 Swift Testing 也可以被快取。

快取的庫 `.xcframework` 保留了生成的項目導入它們所需的元數據，包括 Swift 模塊以及當源目標聲明公共頭文件時的公共 C/Objective-C 頭文件。

> [!NOTE]
> **上游依賴項**
>
> 當一個目標不可快取時，它也會使上游目標不可快取。例如，如果你有依賴關係圖 `A > B`，其中 A 依賴於 B，如果 B 不可快取，A 也將不可快取。

## 分析 {#analytics}

在項目的儀表板中打開 **模塊快取 → 模塊** 以查找頻繁未命中的模塊。選擇你想要改進的環境，例如 **CI**，以及日期範圍。概覽顯示快取命中、未命中以及有未命中的模塊；打開一個模塊會顯示其歷史記錄以及分配給每次觀察的原因。

**未命中** 下拉菜單選擇一個原因的数量和解釋。圖表顯示所有四個原因的分布。在模塊頁面上，使用歷史記錄的 **原因** 過濾器來檢查單個事件。將鼠標懸停在原因徽章上，或使用鍵盤聚焦它以查看其定義。

### 未命中原因 {#miss-reasons}

| 原因 | 含義 |
| --- | --- |
| **已更改** | 模塊自身比較的輸入發生了變化。這些包括文件哈希、構建設置、解析的配置以及編譯器標識符。源代碼編輯只是可能的原因之一。 |
| **上游** | 模塊自身比較的輸入保持不變，但其依賴項或外部包的哈希發生了變化。模塊的源文件可以未被觸動。 |
| **冷啟動** | 沒有早期的模塊觀察可供比較，或者報告的輸入無法解釋未命中，且沒有合格的早期遠程可用性證據。冷啟動並不證明該模塊從未被抓取過。 |
| **已驅逐** | 精確的快取鍵此前在同一項目中同一記錄的快取端點上有過遠程命中，但現在未命中。 |

對於標記為 **已驅逐** 的未命中，工件此前已從遠程快取下載，但這次無法重用。驅逐可能是原因，儘管訪問或下載失敗也可以解釋未命中。Tuist 僅在找到早期的遠程命中時才分配此標籤；此前的未命中和本地命中不足夠。

例如：

| 場景 | 分類 |
| --- | --- |
| 模塊未命中，沒有早期觀察或合格的遠程命中 | 冷啟動 |
| A 發生變化；B 依賴於 A，C 依賴於 B；所有三個鍵都發生變化 | A 是已更改；B 和 C 是上游 |
| 預熱後編譯器版本發生變化，源代碼和設置不變 | 當兩次觀察都報告編譯器輸入時，受影響的未命中為已更改 |
| 精確鍵已從遠程下載，然後在其工件被驅逐後未命中 | 已驅逐（當早期命中符合證據條件時） |
| 一個鍵反覆未命中且從未成功預熱 | 可能保持冷啟動 |

原因描述觀察結果；它們不是附加到鍵的永久標籤。例如，編譯器升級後的第一次未命中可能是已更改，而該新鍵的後續未命中如果從未被觀察為遠程可用，則可能是冷啟動。

### 提高快取命中率 {#improving-cache-hit-rate}

1. **選擇一致的基準。** 從 CI 和具有代表性的日期範圍開始。按未命中次數對模塊進行排序，然後考慮它們的命中率、依賴項和構建成本。修復經常未命中的昂貴依賴項比提高微小模塊的命中率更能節省時間。在進行更改後，比較相同的環境和類似的工作負載。
2. **調查已更改的未命中。** 打開相關的運行並比較它們的完整鍵和報告的輸入。將預熱和使用任務對齊到預期的 Xcode/編譯器版本、配置和目標目的地。在有意更改後再次預熱。如果易變的生成文件或依賴環境的設置使原本穩定的模塊失效，請調查這些輸入。將影響二進制兼容性的輸入保留在哈希中。
3. **追蹤上游未命中到已更改的依賴項。** 檢查其歷史記錄以找到直接更改。預熱產生的鍵可以恢復重用。如果頻繁更改的實現使許多昂貴的依賴項失效，請考慮使用更小的模塊或穩定的接口，如 [效率](#efficiency) 部分所述。
4. **檢查冷啟動未命中的預熱覆蓋範圍。** 驗證預熱是否選擇了所需的模塊，使用了消費任務的配置和環境，並成功上傳了工件。檢查實際 CI 任務使用的完整鍵。如果預熱和消費請求不同的鍵，在假設快取被驅逐之前檢查哈希輸入。即使模塊的源代碼沒有更改，也可能出現沒有早期成功上傳的重複未命中。
5. **利用已驅逐未命中的證據。** 確認消費運行的鍵和端點，然後檢查消費運行的快取警告和預熱任務的上傳結果。在適用的情況下檢查保留或驅逐策略。重新預熱所需的工件並驗證後續命中。如果仍然未命中，請與支持團隊分享相關的運行鏈接和日誌。

為了進行哈希比較，請在您打算預熱和消費的每個相關環境中運行此命令，使用您打算預熱和消費的配置：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模塊的完整哈希和組件塊。在同一台未更改的機器上重複命令通常應產生相同的結果；比較實際的預熱和消費環境以調查不匹配。兩個命令都不需要命中快取。有關進一步檢查，請參見 <.localized_link href="/guides/features/projects/hashing#debugging">哈希診斷</.localized_link>。

## 效率 {#efficiency}

通過二進制快取可以達到的效率水平在很大程度上取決於圖結構。為了達到最佳效果，我們建議以下幾點：

1. 避免非常嵌套的依賴圖。圖越淺越好。
2. 使用協議/接口目標而不是實現目標來定義依賴關係，並從最頂層的目標依賴注入實現。
3. 將頻繁修改的目標拆分為更小的目標，以降低其更改的可能性。

上述建議是 <.localized_link href="/guides/features/projects/tma-architecture">模塊化架構</.localized_link> 的一部分，我們建議將其作為一種構建項目結構的方式，以最大化不僅是二進制快取的好處，還有 Xcode 功能的好處。

## 推薦設置 {#recommended-setup}

我們建議設置一個 CI 任務，**在 main 分支的每次提交中運行** 以預熱快取。這將確保快取始終包含 `main` 中更改的二進制文件，以便本地和 CI 分支構建可以增量地基於它們。

> [!TIP]
> **保持快取預熱隔離**
>
> 在專門的 CI 步驟中運行 `tuist cache`，不要有依賴於生成的工作區的後續步驟。由於 `tuist cache` 會為了快取構建目的修改工作區，任何需要工作區的 CI 步驟都應先運行 `tuist generate` 以獲得一個新的、可用的工作區。

> [!TIP]
> **快取預熱使用二進制文件**
>
> `tuist cache` 命令還利用二進制快取來加速預熱。

以下是一些常見工作流程的示例：

### 開發人員開始處理新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他們從 `main` 創建一個新分支。
2. 他們運行 `tuist generate`。
3. Tuist 從 `main` 拉取最新的二進制文件並用它們生成項目。

### 開發人員向上游推送更改 {#a-developer-pushes-changes-upstream}

1. CI 流水線將運行 `xcodebuild build` 或 `tuist test` 來構建或測試項目。
2. 工作流程將從 `main` 拉取最新的二進制文件並用它們生成項目。
3. 然後它將增量地構建或測試項目。

## 配置 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將 `TUIST_CACHE_CONCURRENCY_LIMIT` 設置為正整數以限制下載和上傳。例如，減少預熱任務中小型自託管快取的負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

當未設置時，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時，下載使用八個任務；對於僅批處理計劃，則使用 32 個任務。舊版 HTTP 快取路徑默認為 100；該默認值不適用於 REAPI。無效值（包括之前記錄的 `none`）會保留默認值而不是移除限制。使用 `unset TUIST_CACHE_CONCURRENCY_LIMIT` 恢復默認值。

限制適用於每個傳輸操作，而不是全局適用於所有操作或 CI 任務。三個同時進行的預熱任務，限制為二，可以對同一快取進行六個活躍上傳。消費者任務可以將變量保持未設置狀態，以保留默認的下載並行性。

### 快取預熱臨時目錄 {#cache-warm-scratch-directory}

默認情況下，`tuist cache` 會為構建中間文件和組裝的快取工件創建一個臨時臨時目錄，然後在快取預熱完成時將其刪除。要將這些文件保存在您管理的目錄下，請設置 `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑，也可以是相對於當前工作目錄的相對路徑。如果目錄不存在，Tuist 會創建它。如果目錄已存在，則必須是空目錄。

當設置此環境變量時，命令完成後 Tuist 會保留目錄及其內容。調用者負責在下一次快取預熱之前清理它。當變量未設置時，Tuist 會繼續使用並刪除臨時目錄。

當需要預熱外部構建目標時，Tuist 會拒絕使用由調用者擁有的臨時目錄。外部構建腳本控制其自身的輸出位置，因此 Tuist 無法保證這些輸出保留在臨時目錄內。

### 代碼覆蓋率 {#code-coverage}

來自模塊快取的目標是預構建二進制文件，只有當該二進制文件是使用覆蓋率計數器構建時，測試執行才會測量其代碼。在 `Tuist.swift` 中為你的項目開啟覆蓋率：

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

啟用 `enabled` 後，每個命令和每個環境都會讀取項目自身目標的一個插樁快取變體，因此在 CI 上的一次預熱即可同時服務於 CI 和本地機器：

| 命令 | 你項目的目標 | 外部包 |
| --- | --- | --- |
| `tuist cache`（Debug 配置） | 預熱插樁二進制文件 | 預熱普通二進制文件 |
| `tuist cache`（Release 配置） | 預熱普通二進制文件 | 預熱普通二進制文件 |
| `tuist hash cache` | 打印插樁密鑰 | 打印普通密鑰 |
| `tuist generate` | 讀取插樁二進制文件 | 讀取普通二進制文件 |
| `tuist test` | 讀取插樁二進制文件 | 讀取普通二進制文件 |

該選項適用於 Xcode 視為 Debug 的每種配置。Release 構建從不進行插樁。Tuist 還會在這些配置中鏈接分析運行時（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使不收集覆蓋率的構建也會鏈接插樁二進制文件，並在自動生成的 scheme 以及你定義但未設置 `coverage` 的 scheme 的測試操作中開啟覆蓋率。

除非 scheme 自行設置覆蓋率，否則你定義的 scheme 會遵循該選項：`.options(coverage: false)` 保持關閉，而 `.options(coverage: true)` 保持開啟，無論選項如何規定。測試計劃自行決定覆蓋率，並且 `-enableCodeCoverage` 仍然會覆蓋單次運行，如同在 Xcode 中一樣。讀取插樁二進制文件但不收集覆蓋率的運行會正常構建和測試。當運行收集覆蓋率但項目的目標作為普通二進制文件來自快取時，Tuist 會警告未測量其覆蓋率。

`TUIST_COVERAGE_ENABLED` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(enabled:)`。請為整個環境（例如 CI 工作流程）設置它，而不是為單一命令設置，以便預熱快取的命令與讀取快取的命令保持一致。

`prefixMapping`（參見 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有其自己的覆蓋設置：`TUIST_COVERAGE_PREFIX_MAPPING` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(prefixMapping:)`。

覆蓋為關閉會讀取普通變體，而開啟覆蓋率預熱的快取不會填充該變體，因此這些目標會從源代碼構建。Release 預熱始終預熱普通二進制文件。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 和 `prefixMapping` 會更改項目目標的構建設置和快取密鑰，以及其測試目標的選擇性測試哈希值。在所有共享快取的機器上將它們設置為相同的值，不要從環境中派生它們（例如從 `Environment.isCI`）：CI 和本地機器之間不同的值會導致不同的密鑰。環境變量也是如此：使用 `TUIST_COVERAGE_ENABLED=0` 的運行不會重用開啟覆蓋率運行的二進制文件或選擇性測試結果。

請記住：

- 插樁二進制文件更大：靜態歸檔和動態庫大約增加 20–30%。Debug 構建的運行速度相同。
- 無論是否啟用此選項，Xcode 的覆蓋率報告從不顯示來自快取的代碼。Tuist 的覆蓋率上傳會測量它。要在 Xcode 中查看目標的覆蓋率，請使用 `tuist generate <target>` 聚焦該目標，使其從源代碼構建。

## 疑難排解 {#troubleshooting}

### 我的目標沒有使用二進制文件 {#it-doesnt-use-binaries-for-my-targets}

確保 <.localized_link href="/guides/features/projects/hashing#debugging">哈希值是確定性的</.localized_link>，跨環境和運行保持一致。如果項目引用了環境（例如通過絕對路徑），可能會發生這種情況。你可以使用 `diff` 命令來比較連續兩次調用 `tuist generate` 生成的項目，或者跨環境或運行進行比較。

還要確保目標不直接或間接依賴於 <.localized_link href="/guides/features/cache/module-cache#supported-products">不可快取的目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用源代碼時，Xcode 的構建系統可以通過 Derived Data 解析未明確聲明的依賴項。但是，當你依賴二進制快取時，必須明確聲明依賴項；否則，當找不到符號時，你可能會看到編譯錯誤。為了調試此問題，我們建議使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令，並在 CI 中設置它以防止隱式鏈接回歸。
