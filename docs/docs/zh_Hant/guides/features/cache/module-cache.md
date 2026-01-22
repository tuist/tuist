---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# 模組快取{#module-cache}

::: warning REQUIREMENTS
<!-- -->
- 一個 <LocalizedLink href="/guides/features/projects"> 產生的專案</LocalizedLink>
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

Tuist
模組快取提供強大的建置時間優化方案，透過將模組快取為二進位檔（`.xcframework、`）並跨環境共享，使您能重複利用先前生成的二進位檔，減少重複編譯需求並加速開發流程。

## 暖身{#warming}

Tuist 有效地
<LocalizedLink href="/guides/features/projects/hashing">利用</LocalizedLink>依賴關係圖中每個目標的雜湊值來偵測變更。透過此數據，它為衍生自這些目標的二進位檔建立並指派唯一識別碼。在生成圖時，Tuist
會無縫替換原始目標及其對應的二進位版本。

此操作稱為「預熱」（* ），可透過 Tuist 產生供本地使用或與團隊成員及 CI 環境共享的二進位檔（*
）。預熱快取的流程相當直觀，僅需執行單一指令即可啟動：


```bash
tuist cache
```

此指令會重複使用二進位檔以加速處理流程。

## 用法{#usage}

預設情況下，當 Tuist
指令需要生成專案時，若快取中存在對應的二進位檔，系統會自動將依賴項替換為其二進位等效版本。此外，若您指定需重點處理的目標清單，Tuist
亦會將所有依賴目標替換為其快取中的二進位檔（前提是該版本可用）。若您偏好不同處理方式，可透過特定標記完全停用此行為：

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

::: warning
<!-- -->
二進位快取是專為開發工作流程設計的功能，例如在模擬器或裝置上執行應用程式，或執行測試。此功能不適用於正式發布版本。當您將應用程式歸檔時，請使用以下指令產生包含原始碼的專案：`--cache-profile
none`
<!-- -->
:::

## 快取設定檔{#cache-profiles}

Tuist 支援快取設定檔，用以控制在生成專案時，目標檔案被快取二進位檔取代的積極程度。

- 內建函式：
  - `僅外部依賴項`: 僅替換外部依賴項（系統預設）
  - `all-possible`: 盡可能替換所有目標（包含內部目標）
  - `none`: 絕不以快取二進位檔取代

選取設定檔：`--cache-profile` 於`tuist generate`:

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

::: info DEPRECATED FLAG
<!-- -->
`--no-binary-cache` 參數已廢棄。請改用`--cache-profile none` 替代。廢棄參數仍為向後相容性而保留。
<!-- -->
:::

解析實際行為的優先順序（由高至低）：

1. `--cache-profile none`
2. 目標焦點（將目標傳遞至`生成` ）→ 剖析`所有可能`
3. `--cache-profile &lt;值&gt;`
4. 預設設定（若已設定）
5. 系統預設值 (`only-external`)

## 支援產品{#supported-products}

僅下列目標產品可由 Tuist 進行快取：

- 不依賴 [XCTest](https://developer.apple.com/documentation/xctest) 的框架（靜態與動態皆然）
- Bundles
- Swift 宏指令

我們正在努力支援依賴 XCTest 的函式庫與目標。

::: info UPSTREAM DEPENDENCIES
<!-- -->
當目標不可快取時，其上游目標亦隨之不可快取。例如，若依賴關係圖為`A &gt; B` ，其中 A 依賴 B，若 B 不可快取，則 A 亦將不可快取。
<!-- -->
:::

## 效率{#efficiency}

二進位快取能達到的效能程度，高度取決於圖結構。為獲得最佳效果，我們建議採取以下措施：

1. 避免過度嵌套的依存關係圖。圖層結構越淺越理想。
2. 定義依賴關係時應以協定/介面目標取代實作目標，並從最頂層目標進行依賴注入實作。
3. 將頻繁修改的目標拆分為更小的目標，以降低變更機率。

上述建議屬於我們提出的<LocalizedLink href="/guides/features/projects/tma-architecture">模組化架構</LocalizedLink>，此架構能協助您規劃專案結構，不僅最大化二進位快取的效益，更能充分發揮
Xcode 的功能優勢。

## 建議設定{#recommended-setup}

建議在主分支** 建立 CI 任務，使其於每次提交時由**執行以預熱快取。此舉可確保快取始終包含`主分支` 的變更二進位檔，使本地與 CI
分支能基於這些快取增量建置。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` 指令亦運用二進位快取機制加速預熱流程。
<!-- -->
:::

以下為常見工作流程範例：

### 一位開發人員開始著手開發新功能{#a-developer-starts-to-work-on-a-new-feature}

1. 他們從`main` 創建了新分支。
2. 他們執行`tuist generate` 。
3. Tuist 會從`main` 取得最新二進位檔，並用這些檔案生成專案。

### 開發人員將變更推送至上游{#a-developer-pushes-changes-upstream}

1. CI 管道將執行以下指令：`xcodebuild build` 或`tuist test` 以建置或測試專案。
2. 此工作流程將從`main` 拉取最新二進位檔，並以此建立專案。
3. 系統將依此逐步建置或測試專案。

## 組態{#configuration}

### 快取並發限制{#cache-concurrency-limit}

預設情況下，Tuist
會無並行限制地下載與上傳快取物件，以最大化吞吐量。您可透過環境變數控制此行為：`TUIST_CACHE_CONCURRENCY_LIMIT`

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

此功能在網路頻寬受限的環境中或於快取操作期間降低系統負載時相當實用。

## 疑難排解{#troubleshooting}

### 它不使用二進位檔作為我的目標{#it-doesnt-use-binaries-for-my-targets}

確保
<LocalizedLink href="/guides/features/projects/hashing#debugging">雜湊值在不同環境與執行次數間具有確定性</LocalizedLink>。若專案存在環境參照（例如透過絕對路徑），可能導致此問題。可使用`diff`
指令，比較連續兩次執行`tuist generate` 所產生的專案，或跨環境/執行次數進行比對。

同時請確保目標不直接或間接依賴於<LocalizedLink href="/guides/features/cache/generated-project#supported-products">不可快取的目標</LocalizedLink>。

### 缺失符號{#missing-symbols}

使用來源時，Xcode
的建置系統可透過派生資料解析未明示宣告的依賴關係。然而若依賴二進位快取，則必須明示宣告依賴關係；否則當符號無法被找到時，很可能會出現編譯錯誤。為此我們建議使用
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink>
指令進行除錯，並在持續整合環境中設定此指令以防止隱式連結的退化問題。

### 舊版模組快取{#legacy-module-cache}

在 Tuist`4.128.0`
中，我們已將模組快取的新基礎架構設為預設值。若您在新版中遇到問題，可透過設定環境變數`TUIST_LEGACY_MODULE_CACHE` 恢復舊版快取行為。

此遺留模組快取僅為臨時替代方案，將於未來更新中從伺服器端移除。請規劃遷移至其他解決方案。

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
