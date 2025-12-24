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

Tuist 模組快取提供了一種強大的方式，可將模組快取為二進位檔 (`.xcframework`s)
並在不同環境中共用，從而優化您的建立時間。此功能可讓您利用先前產生的二進位檔，減少重複編譯的需要，並加快開發流程。

## 暖化{#warming}

Tuist 可以有效地 <LocalizedLink href="/guides/features/projects/hashing"> 利用依賴圖表中每個目標的哈希值 </LocalizedLink> 來偵測變更。利用這些資料，Tuist
會建立並為這些目標衍生的二進位檔案指定獨特的識別碼。在生成圖形時，Tuist 會以相應的二進位版本無縫取代原始目標。

此操作稱為* 「暖身」，* 製作二進位檔供本端使用，或透過 Tuist 與隊友和 CI 環境分享。暖化快取記憶體的過程很直接，只要一個簡單的指令就可以啟動：


```bash
tuist cache
```

此指令會重複使用二進位檔案，以加快處理速度。

## 使用方式{#usage}

在預設情況下，當 Tuist
指令需要產生專案時，如果可用的話，它們會自動用快取記憶體中的二進位等效物取代依賴物。此外，如果您指定了要集中處理的目標清單，Tuist
也會用快取記憶體中的二進位檔取代任何依賴的目標，前提是這些二進位檔是可用的。對於那些偏好不同方法的人，有一個選項可以透過使用特定的標誌來完全選擇不使用此行為：

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
二進位快取是專為開發工作流程設計的功能，例如在模擬器或裝置上執行應用程式，或執行測試。它不適用於發行版的建立。歸檔應用程式時，請使用`--no-binary-cache`
旗標，產生包含原始碼的專案。
<!-- -->
:::

## 快取設定檔{#cache-profiles}

Tuist 支援快取設定檔，可控制在產生專案時，如何積極地以快取的二進位檔取代目標。

- 嵌入式：
  - `only-external`: 只取代外部依賴 (系統預設)
  - `all-possible`: 盡可能取代所有目標 (包括內部目標)
  - `none`: 絕不以快取的二進位檔取代

使用`--cache-profile` 在`tuist 上選擇設定檔，產生` ：

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

解決有效行為時的優先順序（由高至低）：

1. `--no-binary-cache` → 設定檔`無`
2. 目標焦點 (將目標傳送至`產生`) → 檔案`all-possible`
3. `--cache-profile <value> 快取設定檔`
4. 組態預設值 (如果已設定)
5. 系統預設值 (`only-external`)

## 支援的產品{#supported-products}

只有下列目標產品可由 Tuist 快取：

- 不依賴 [XCTest](https://developer.apple.com/documentation/xctest) 的框架 (靜態與動態)
- 捆包
- Swift 巨集

我們正努力支援依賴 XCTest 的函式庫和目標。

::: info UPSTREAM DEPENDENCIES
<!-- -->
當目標不可快取時，上游的目標也會變成不可快取。例如，如果您有依賴圖形`A &gt; B` ，其中 A 依賴於 B，如果 B 是非快取，A 也將非快取。
<!-- -->
:::

## 效率{#efficiency}

二進位快取所能達到的效率等級，在很大程度上取決於圖結構。為了達到最佳效果，我們建議如下：

1. 避免巢狀依存圖。圖形越淺越好。
2. 使用通訊協定/介面目標定義依賴關係，而非實作目標，並從最上層的目標依賴注入實作。
3. 將經常修改的目標分割成變更可能性較低的小目標。

上述建議是 <LocalizedLink href="/guides/features/projects/tma-architecture">The Modular Architecture</LocalizedLink> 的一部分，我們提出這種方式來架構您的專案，不僅讓二進位快取的效益最大化，也讓
Xcode 的功能最大化。

## 建議設定{#recommended-setup}

我們建議**在主分支** 的每次提交中執行 CI 作業，為快取記憶體加熱。這將確保快取記憶體中總是包含`main` 中變更的二進位檔，因此本機和 CI
分支會以增量方式建立這些變更。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` 指令也利用二進位快取記憶體加速暖機。
<!-- -->
:::

以下是一些常見工作流程的範例：

### 開發人員開始開發新功能{#a-developer-starts-to-work-on-a-new-feature}

1. 他們從`main` 建立一個新的分支。
2. 他們運行`tuist 生成` 。
3. Tuist 從`主網站` 取得最新的二進位檔，並使用這些二進位檔產生專案。

### 開發人員向上游推送變更{#a-developer-pushes-changes-upstream}

1. CI 管道會執行`xcodebuild build` 或`tuist test` 來建立或測試專案。
2. 工作流程會從`主網站` 取得最新的二進位檔，並使用這些二進位檔產生專案。
3. 然後，它會逐步建立或測試專案。

## 組態{#configuration}

### 快取記憶體並發限制{#cache-concurrency-limit}

預設情況下，Tuist 在下載和上傳快取物件時沒有任何並發限制，以達到最大吞吐量。您可以使用`TUIST_CACHE_CONCURRENCY_LIMIT`
環境變數來控制此行為：

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

這在網路頻寬有限的環境中，或在快取記憶體作業期間降低系統負載時非常有用。

## 疑難排解{#troubleshooting}

### 我的目標不使用二進位檔案{#it-doesnt-use-binaries-for-my-targets}

確保<LocalizedLink href="/guides/features/projects/hashing#debugging">hash 在不同的環境和執行中都是確定的</LocalizedLink>。如果專案有對環境的參照，例如透過絕對路徑，可能會發生這種情況。您可以使用`diff`
指令比較連續兩次調用`tuist generate` 所產生的專案，或跨環境或跨執行。

此外，請確定目標不會直接或間接依賴於
<LocalizedLink href="/guides/features/cache/generated-project#supported-products"> 不可快取的目標</LocalizedLink>。

### 遺失的符號{#missing-symbols}

當使用原始碼時，Xcode 的建立系統透過 Derived Data
可以解決未明確宣告的依賴關係。但是，當您依賴二進位緩存時，必須明確宣告依賴關係；否則，當找不到符號時，您很可能會看到編譯錯誤。若要除錯，建議使用
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> 指令，並在 CI 中設定，以防止隱式連結的退步。
