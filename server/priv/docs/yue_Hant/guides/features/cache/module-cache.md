---
{
  "title": "模組快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "快取已編譯的二進制檔案，並透過 Tuist Module Cache 與你的團隊共享。"
}
---

# 模組快取 {#module-cache}

> [!WARNING]
> **要求**
>
> - 一個<.localized_link href="/guides/features/projects">已生成項目</.localized_link>。模組快取會讀取 Tuist 在 `Project.swift` 背後維護的項目圖，以計算目標的哈希值並替換其二進制檔案。

Tuist Module Cache 提供強大的方法來優化構建時間，方法是將你的模組快取為二進制檔案（`.xcframework`s）並在不同環境之間共享。此功能讓你利用先前生成的二進制檔案，減少重複編譯的需要，並加快開發流程。

> [!TIP]
> **與 Xcode 快取結合使用**
>
> 模組快取和<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取</.localized_link>是互補的，因為它們在不同的粒度級別上運作。模組快取在構建運行之前用預先構建的 `.xcframework`s 替換整個模組，而 Xcode 快取則在構建期間重用編譯輸出。
>
> 編譯快取設定不屬於模組快取哈希的一部分，因此開啟或關閉 Xcode 快取會保留你已經預熱的二進制檔案。在 Xcode 27 及更高版本中，隨附的前綴映射設定會被哈希化。請參閱<.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模組快取哈希</.localized_link>。

## 預熱 {#warming}

Tuist 有效地<.localized_link href="/guides/features/projects/hashing">利用哈希</.localized_link>來檢測依賴關係圖中每個目標的變化。利用這些數據，它會構建並為源自這些目標的二進制檔案分配唯一標識符。在圖生成時，Tuist 會無縫地將原始目標替換為其對應的二進制版本。

這個稱為 *「預熱」* 的操作會生成用於本地使用或透過 Tuist 與隊友及 CI 環境共享的二進制檔案。預熱快取的過程簡單直接，可以透過一個簡單的命令啟動：

```bash
tuist cache
```

該命令會重用二進制檔案以加快流程。

如果某個二進制檔案上傳失敗，命令仍會上傳其餘部分，然後以非零狀態退出並列出未上傳的目標。機器本地快取中的二進制檔案算作已快取，因此要從同一台機器再次上傳它們，請在預熱之前運行 `tuist clean binaries`。傳遞 `--no-upload` 以僅將二進制檔案存儲在本地快取中。

### 目的地選擇 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 來為單一目的地進行快取和生成：

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

預設值是 `all`，它會保留你的目標支持的所有目的地，包括 Mac Catalyst。後續的 `tuist cache` 會重用已快取的切片並僅構建缺少的 SDK。常規生成會在缺少任何所需切片時保留模組的源代碼。

受限生成將源目標限制為選定的目的地，並保留原生 macOS 目標，包括宏。兩種受限模式都不包括 Mac Catalyst。使用 `--destination all` 重新生成以恢復所有目的地。

逐切片快取支持具有標準架構的 iOS 和 macOS。其他平台、自定義架構和不支持的產品則保持完整工件快取。舊版模組快取需要 `--destination all`。

### 遠程上傳准入 {#remote-upload-admission}

現代模組快取使用 REAPI。當繁忙的快取暫時以 `RESOURCE_EXHAUSTED` 拒絕上傳時，Tuist 會帶有抖動地退避，遵守標準的 `google.rpc.RetryInfo` 最小延遲，並在有限的等待預算內重試。上傳准入允許每次調用最多重試六次。每個 blob 上傳操作在其存在檢查、批量上傳和流式寫入之間共享一個 60 秒的累計退避預算；並發等待各自消耗預算，因此重複拒絕不會讓每個排隊的 blob 再獲得一分鐘的重試時間。成功的傳輸不會消耗此預算，並且在預算耗盡時不會被取消。動作結果發布有其自己的有限預算。指數延遲從一秒開始，在向比例抖動增長之前趨向 30 秒。如果伺服器要求的延遲超過剩餘預算，Tuist 會失敗而不是早於指示進行重試。取消會中斷退避，而快取讀取會保留短重試，以便過載不會阻滯生成。

這些預設值也有助於沒有重試提示的舊版 Kura。較長的重試吸收的是臨時爭用，而非持續過載：如果拒絕持續存在，請減少預熱作業上的[快取併發限制](#cache-concurrency-limit)或增加伺服器容量。請參閱[Kura 上傳規模調整](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以獲取 pod 記憶體估算和准入指標。

### 配置選擇 {#configuration-selection}

當在不傳遞 `--configuration` 的情況下預熱快取時，Tuist 會按以下順序選擇要使用的構建配置：

1. 清單中 `Project.Options.generationOptions` 設定的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否則，變體為 `debug` 的第一個構建配置，按名稱字母順序排序。

要為特定配置預熱快取，請明確傳遞它：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

預設情況下，當 Tuist 命令需要項目生成時，它們會自動用快取中的二進制等效項替換依賴項（如果可用）。此外，如果你指定要關注的目標列表，Tuist 也會用其快取的二進制檔案替換任何依賴目標，前提是它們可用。對於喜歡不同方法的人，可以選擇使用特定標誌完全退出此行為：

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
> 二進制快取是一項專為開發工作流程設計的功能，例如在模擬器或設備上運行應用程序，或運行測試。它不適用於發布構建。在歸檔應用程序時，請使用 `--cache-profile none` 生成包含源代碼的項目。

## 快取配置文件 {#cache-profiles}

Tuist 支持快取配置文件，以控制在生成項目時替換目標為快取二進制檔案的積極程度。

- 內置：
  - `only-external`：僅替換外部依賴項（系統預設）
  - `all-possible`：盡可能替換更多目標（包括內部目標）
  - `none`：從不使用快取二進制檔案替換

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
> `--no-binary-cache` 標誌已棄用。請改用 `--cache-profile none`。該已棄用的標誌仍為向後兼容而有效。

解析有效行為時的優先級（從高到低）：

1. `--cache-profile none`
2. 目標聚焦（將目標傳遞給 `generate`）→ 配置文件 `all-possible`
3. `--cache-profile <value>`
4. 配置預設值（如果已設定）
5. 系統預設值（`only-external`）

## 支援的產品 {#supported-products}

只有以下目標產品可由 Tuist 快取：

- 框架（靜態和動態），包括依賴 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的測試支援框架
- 程式庫（靜態和動態），包括依賴 XCTest 或 Swift Testing 的測試支援程式庫
- Bundle
- Swift Macros

測試 Bundle 仍被排除在模組快取之外。這意味著 `unitTests` 和 `uiTests` 目標不會以二進制形式快取，但測試所依賴的常規框架和程式庫目標即使連結了 XCTest 或 Swift Testing 也可以快取。

快取的程式庫 `.xcframework` 會保留生成項目導入它們所需的元數據，包括 Swift 模組以及當源目標聲明公開標頭時的公開 C/Objective-C 標頭。

> [!NOTE]
> **上游依賴項**
>
> 當一個目標不可快取時，它也會使上游目標不可快取。例如，如果你有依賴圖 `A > B`，其中 A 依賴於 B，如果 B 不可快取，A 也將不可快取。

## 分析 {#analytics}

在項目的儀表板中打開 **模組快取 → 模組** 以查找經常錯過的模組。選擇你想要改善的環境，例如 **CI**，以及日期範圍。概覽顯示快取命中、錯過以及有錯過的模組；打開模組會顯示其歷史記錄和分配給每次觀察的原因。

**錯過** 下拉選單選擇一個原因的数量和解釋。圖表顯示所有四個原因的分布。在模組頁面上，使用歷史記錄的 **原因** 過濾器來檢查個別事件。將鼠標懸停在原因徽章上，或使用鍵盤聚焦它以查看其定義。

### 錯過原因 {#miss-reasons}

| 原因 | 含義 |
| --- | --- |
| **已更改** | 模組自身的比較輸入已更改。這些包括文件哈希、構建設置、解析的配置和編譯器標識符。源代碼編輯只是可能的原因之一。 |
| **上游** | 模組自身的比較輸入保持不變，但其依賴項或外部包哈希已更改。模組的源文件可以未受影響。 |
| **冷啟動** | 沒有早期的模組觀察可供比較，或者報告的輸入無法解釋錯過，並且沒有合格的早期遠程可用性證據。冷啟動並不能證明該模組從未快取過。 |
| **已驅逐** | 確切的快取鍵以前在同一項目中的同一記錄快取端點上有遠程命中，但現在錯過了。 |

對於標記為 **已驅逐** 的錯過，工件以前從遠程快取下載，但這次無法重用。驅逐可能是原因，儘管訪問或下載失敗也可以解釋錯過。Tuist 只有在找到早期的遠程命中時才會分配此標籤；之前的錯過和本地命中是不夠的。

例如：

| 場景 | 分類 |
| --- | --- |
| 模組錯過，沒有早期觀察或合格的遠程命中 | 冷啟動 |
| A 更改；B 依賴於 A，C 依賴於 B；所有三個鍵都更改 | A 是已更改；B 和 C 是上游 |
| 預熱後編譯器版本更改，源代碼和設置不變 | 當兩次觀察都報告編譯器輸入時，受影響的錯過是已更改 |
| 確切的鍵從遠程下載，然後在其工件被驅逐後錯過 | 已驅逐，當早期的命中符合證據資格時 |
| 一個鍵反覆錯過且從未成功預熱 | 它可以保持冷啟動 |

原因係描述觀察結果，唔係永久貼喺某個鍵上面嘅標籤。例如，升級編譯器後第一次錯過可能係「已更改」，而之後同一個新鍵再錯過，如果從來冇觀察到遠程可用，就可能係「冷啟動」。

### 提升快取命中率 {#improving-cache-hit-rate}

1. **選擇一致嘅基準。** 由 CI 同具代表性嘅日期範圍開始。按錯過次數排序模組，然後考慮佢哋嘅命中率、依賴者同構建成本。修復一個經常錯過又昂貴嘅依賴，比起提升細模組嘅命中率可以節省更多時間。做出改變後，比較同一環境同類似工作負載。
2. **調查「已更改」錯過。** 開啟相關運行並比較佢哋嘅完整鍵同報告輸入。將預熱同消費作業對齊到預期嘅 Xcode/編譯器版本、配置同目標目的地。有意更改後再次預熱。如果易變嘅生成文件或依賴環境嘅設置令原本穩定嘅模組失效，請調查呢啲輸入。將影響二進制兼容性嘅輸入保留喺哈希中。
3. **追蹤「上游」錯過到已更改嘅依賴。** 檢查其歷史以找到直接更改。預熱產生嘅鍵可以恢復重用。如果經常更改嘅實現使許多昂貴嘅依賴者失效，請考慮使用較小嘅模組或穩定接口，如 [效率](#efficiency) 部分所述。
4. **檢查「冷啟動」錯過嘅預熱覆蓋範圍。** 驗證預熱是否選擇咗所需模組、使用消費作業嘅配置同環境，並成功上傳工件。檢查實際 CI 作業使用嘅完整鍵。如果預熱同消費請求唔同嘅鍵，請喺假設快取被驅逐之前檢查哈希輸入。即使模組源碼冇變，亦可能出現反覆錯過且之前冇成功上傳嘅情況。
5. **利用「已驅逐」錯過嘅證據。** 確認消費運行嘅鍵同端點，然後檢查消費運行嘅快取警告同預熱作業嘅上傳結果。適用時檢查保留或驅逐情況。重新預熱所需工件並驗證後續命中。如果仍然錯過，請將相關運行鏈接同日誌分享畀支援團隊。

要進行哈希比較，請喺每個相關環境中使用你打算預熱同消費嘅配置運行以下命令：

```bash
tuist hash cache --configuration Debug --verbose
```

比較模組嘅完整哈希同組件塊。喺同一台未更改嘅機器上重複命令通常會產生相同結果；比較實際預熱同消費環境以調查不匹配。兩個命令都唔需要命中快取。有關進一步檢查，請參閱 <.localized_link href="/guides/features/projects/hashing#debugging">哈希診斷</.localized_link>。

## 效率 {#efficiency}

通過二進制快取可以達到嘅效率水平很大程度上取決於圖結構。為咗達到最佳效果，我哋建議如下：

1. 避免非常深嘅依賴圖。圖越淺越好。
2. 用協議/接口目標定義依賴，而唔係用實現目標，並從最頂層目標注入依賴實現。
3. 將經常修改嘅目標拆分成更小、更改可能性更低嘅目標。

上述建議係 <.localized_link href="/guides/features/projects/tma-architecture">模塊化架構</.localized_link> 嘅一部分，我哋建議以此方式組織項目，以最大化二進制快取同 Xcode 功能嘅效益。

## 推薦設置 {#recommended-setup}

我哋建議設置一個 CI 作業，**喺主分支每次提交時運行**以預熱快取。這將確保快取始終包含 `main` 中更改嘅二進制文件，以便本地同 CI 分支構建可以基於它們增量進行。

> [!TIP]
> **保持快取預熱隔離**
>
> 喺專用嘅 CI 步驟中運行 `tuist cache`，唔好有後續步驟依賴生成嘅工作區。由於 `tuist cache` 會為構建快取目嘅修改工作區，任何需要工作區嘅 CI 步驟應先運行 `tuist generate` 以獲取全新、可用嘅工作區。

> [!TIP]
> **快取預熱使用二進制文件**
>
> `tuist cache` 命令亦會利用二進制快取來加速預熱。

以下係一些常見工作流程嘅示例：

### 開發人員開始處理新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 佢哋從 `main` 創建新分支。
2. 佢哋運行 `tuist generate`。
3. Tuist 從 `main` 拉取最新嘅二進制文件並用它們生成項目。

### 開發人員向上游推送更改 {#a-developer-pushes-changes-upstream}

1. CI 管道將運行 `xcodebuild build` 或 `tuist test` 來構建或測試項目。
2. 工作流程將從 `main` 拉取最新嘅二進制文件並用它們生成項目。
3. 然後它會增量構建或測試項目。

## 配置 {#configuration}

### 快取併發限制 {#cache-concurrency-limit}

將 `TUIST_CACHE_CONCURRENCY_LIMIT` 設置為正整數以限制下載同上傳。例如，減少預熱作業中小型自託管快取嘅負載：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

未設置時，REAPI 上傳使用八個傳輸任務。當任何 blob 需要 ByteStream 時下載使用八個，純批量計劃使用 32 個。舊版 HTTP 快取路徑默認為 100；該默認值不適用於 REAPI。無效值（包括之前記錄嘅 `none`）會保留默認值而唔係移除限制。使用 `unset TUIST_CACHE_CONCURRENCY_LIMIT` 恢復默認值。

限制應用於每次傳輸操作，而唔係全局跨操作或 CI 作業。三個同時預熱且限制為二可以有六個上傳活動針對同一快取。消費者作業可以留低變量未設置以保留默認下載並行性。

### 快取預熱臨時目錄 {#cache-warm-scratch-directory}

默認情況下，`tuist cache` 會為構建中間件同組裝嘅快取工件創建臨時臨時目錄，然後喺快取預熱完成時刪除它。要將這些文件保留喺你管理嘅目錄下，請設置 `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路徑可以是絕對路徑或相對於當前工作目錄。Tuist 會喺目錄不存在時創建它。如果已經存在，它必須係一個空目錄。

設置此環境變量後，Tuist 會在命令完成後保留目錄及其內容。調用者負責喺下次快取預熱前清理它。當變量未設置時，Tuist 會繼續使用並刪除臨時目錄。

當需要預熱外部構建目標時，Tuist 會拒絕調用者擁有嘅臨時目錄。外部構建腳本控制自己嘅輸出位置，因此 Tuist 無法保證這些輸出保留喺臨時目錄內。

### 代碼覆蓋率 {#code-coverage}

> [!NOTE] EARLY ACCESS
> 模塊快取嘅代碼覆蓋率處於早期訪問階段。只有喺設置 `TUIST_FEATURE_FLAG_COVERAGE=1` 時，命令才會讀取同預熱下面描述嘅插樁二進制文件。

模組快取中嘅目標係預先構建嘅二進制文件，只有當該二進制文件係帶覆蓋率計數器構建時，測試執行才會測量其代碼。喺 `Tuist.swift` 中為你嘅項目開啟覆蓋率：

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

啟用 `enabled` 後，每個命令同每個環境都會為你自己項目嘅目標讀取一個插樁版本嘅快取，因此 CI 上嘅單次預熱可以同時服務 CI 同本地機器：

| 命令 | 你項目嘅目標 | 外部包 |
| --- | --- | --- |
| `tuist cache`（Debug 配置） | 預熱插樁二進制文件 | 預熱普通二進制文件 |
| `tuist cache`（Release 配置） | 預熱普通二進制文件 | 預熱普通二進制文件 |
| `tuist hash cache` | 打印插樁密鑰 | 打印普通密鑰 |
| `tuist generate` | 讀取插樁二進制文件 | 讀取普通二進制文件 |
| `tuist test` | 讀取插樁二進制文件 | 讀取普通二進制文件 |

該選項適用於 Xcode 視為 Debug 嘅每種配置。Release 構建從不插樁。Tuist 亦會喺這些配置中鏈接配置文件運行時（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此即使唔收集覆蓋率嘅構建仍然會鏈接插樁二進制文件，並喺它自動生成嘅方案以及你定義但將 `coverage` 留空嘅方案嘅測試操作中開啟覆蓋率。

你定義嘅方案會遵循該選項，除非它自己設置覆蓋率：`.options(coverage: false)` 會保持關閉，而 `.options(coverage: true)` 會保持開啟，無論選項如何規定。測試計劃自己決定覆蓋率，而 `-enableCodeCoverage` 仍然會覆蓋一次運行，就像喺 Xcode 中一樣。讀取插樁二進制文件但唔收集覆蓋率嘅運行會正常構建同測試。當一次運行收集覆蓋率，但你項目嘅目標作為普通二進制文件來自快取時，Tuist 會警告它們嘅覆蓋率未被測量。

`TUIST_COVERAGE_ENABLED` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(enabled:)`。為整個環境（例如 CI 工作流）設置它，而唔係為單個命令設置，以便預熱快取嘅命令同讀取它嘅命令保持一致。

`prefixMapping`（參見 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 快取</.localized_link>）有自己嘅覆蓋設置：`TUIST_COVERAGE_PREFIX_MAPPING` 環境變量（`1` 或 `0`）優先於 `coverage: .coverage(prefixMapping:)`。

覆蓋為關閉會讀取普通版本，而開啟覆蓋率預熱嘅快取唔會填充該版本，因此這些目標會從源代碼構建。Release 預熱始終預熱普通二進制文件。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 同 `prefixMapping` 會更改你項目目標嘅構建設置同快取密鑰，以及其測試目標嘅選擇性測試哈希。喺共享快取嘅每部機器上將它們設置為相同值，唔好從環境派生它們（例如從 `Environment.isCI`）：CI 同本地機器之間不同嘅值會導致它們擁有不同嘅密鑰。環境變量亦然：帶有 `TUIST_COVERAGE_ENABLED=0` 嘅運行唔會重用開啟覆蓋率運行嘅二進制文件或選擇性測試結果。

請記住：

- 插樁二進制文件更大：靜態歸檔同動態庫大約大 20–30%。Debug 構建以相同速度運行。
- 無論是否啟用此選項，Xcode 嘅覆蓋率報告從不顯示來自快取嘅代碼。Tuist 嘅覆蓋率上傳會測量它。要喺 Xcode 中查看目標嘅覆蓋率，請使用 `tuist generate <target>` 聚焦它以從源代碼構建。

## 疑難解答 {#troubleshooting}

### 它唔會為我嘅目標使用二進制文件 {#it-doesnt-use-binaries-for-my-targets}

確保 <.localized_link href="/guides/features/projects/hashing#debugging">哈希係確定性嘅</.localized_link> 跨環境同運行。如果項目引用環境（例如通過絕對路徑），可能會發生這種情況。你可以使用 `diff` 命令來比較連續兩次調用 `tuist generate` 生成嘅項目，或者跨環境或運行進行比較。

還要確保目標唔直接或間接依賴於 <.localized_link href="/guides/features/cache/module-cache#supported-products">不可快取嘅目標</.localized_link>。

### 缺少符號 {#missing-symbols}

使用源代碼時，Xcode 嘅構建系統可以通過 Derived Data 解析未明確聲明嘅依賴項。然而，當你依賴二進制快取時，必須明確聲明依賴項；否則，當找不到符號時，你可能會看到編譯錯誤。要調試此問題，我哋建議使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令並喺 CI 中設置它，以防止隱式鏈接回歸。
