---
{
  "title": "Elixir 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 測試分片，將 Elixir 專案的測試分散到多個 CI runner 上執行。"
}
---
# Elixir 測試分片 {#elixir-test-sharding}

Tuist Hex 套件內建支援將 Elixir 專案的測試進行分片。它會使用 Tuist 伺服器，根據歷史計時數據建立平衡的分片計劃，並只編譯你的專案一次，讓每個執行器都能直接開始執行測試。

> [!IMPORTANT] REQUIREMENTS
> - 在設定 CI 分片工作之前，請先完成 <.localized_link href="/guides/get-started/elixir-project">共用的 Elixir 設定</.localized_link>

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建構階段：** Tuist 會為測試編譯你的專案、列舉測試檔案，並在伺服器上建立 **分片計劃**。伺服器會使用過去 30 天的歷史測試計時數據，將測試分配到各個分片，使每個分片的耗時大致相同。建構階段會上傳建構產物，並輸出一個 **分片矩陣**，供你的 CI 系統用來產生平行執行器。
2. **測試階段：** 每個 CI 執行器會收到一個 **分片索引**、下載建構產物，並只執行指派給該分片的測試。

建構上傳會同時傳送最多四個部分，並針對暫時性的部分失敗最多重試三次。在已註冊的 Tuist Linux 執行器上，分片建構可以使用本機構件儲存空間。所有使用此類建構的分片必須在同一站點的已註冊執行器上執行；當將工作流程移轉至其他執行器時，請停用本機儲存空間並重新執行建構。

測試以檔案為單位分配：同一個檔案中的所有測試都會在同一個分片上執行。Tuist 尚未見過的測試會獲得估算值，因此專案的初期計劃平衡度會低於後續計劃。

## 建構階段 {#build-phase}

使用 `tuist.test.build` 任務準備測試分片：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

在叫用分片任務之前，請透過共用設定所安裝的別名進行編譯。在乾淨的檢出環境中，Mix 可能在發現 `tuist.test.build` 的同時編譯相依套件，此時 Tuist 的相依快取還來不及還原它們。明確的編譯會在與分片任務相同的測試環境中執行。

此任務會：
1. 在測試環境中編譯專案
2. 使用歷史計時數據在 Tuist 伺服器上建立分片計劃
3. 上傳建構產物，以免分片再次編譯
4. 為你的 CI 系統輸出分片矩陣

### 建構選項 {#build-options}

| 選項 | 說明 |
|--------|-------------|
| `--shard-max <N>` | 最大分片數量（預設：2） |
| `--shard-min <N>` | 最小分片數量 |
| `--shard-total <N>` | 精確的分片數量，而非範圍 |
| `--shard-max-duration <MS>` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-reference <REF>` | 分片用來查找計劃的名稱 |
| `--no-upload` | 規劃分片而不上傳建構產物；每個分片隨後會自行編譯 |

所有其他引數都會轉發給 `mix compile`。

分片參考會自動從 CI 環境變數（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）衍生，或可以透過 `TUIST_SHARD_REFERENCE` 環境變數明確設定。在這些提供者之外，你必須將其設定為建構階段與同一管道執行的各分片所共用的值。在 GitHub Actions 上，參考也包含執行嘗試次數：當僅重新執行失敗的工作時，請傳遞原始建構工作的參考，而不是在分片工作中衍生新的參考。

## 測試階段 {#test-phase}

當設定 `TUIST_SHARD_INDEX` 時，套件會從伺服器取得分片指派、下載建構產物，並在不編譯的情況下只執行指派的測試檔案。在乾淨的執行器上，請在叫用任務前先引導 SDK 並載入其路徑：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

在 Mix 的工作程序中編譯 SDK 不會將其載入父程序。明確的 `deps.loadpaths` 步驟可防止任務探索在下載建構產物之前編譯剩餘的相依套件。這種單一命令形式會保留你專案的測試準備別名。如果其設定命令觸發編譯，請使用下方的獨立設定序列。

你傳遞的任何測試檔案或目錄會進一步縮小分片範圍：只有同時位於分片中且在你選擇範圍內的檔案才會執行。如果分片最終沒有測試，則會成功結束。

所有分片的結果會作為單一測試執行出現在儀表板上，其 **分片** 區段會顯示每個分片的耗時。

如果必須在測試之前執行設定，請先下載建構產物而不啟動應用程式：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

在停用編譯的情況下，於單獨的程序中執行你的設定。例如，Ecto 專案可以使用以下方式建立並遷移其資料庫：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

在此階段保留任何其他專案特定的準備工作。你的編譯別名也必須在進行引導工作之前尊重 `--no-compile`：Mix 只會將旗標轉發給列表別名的最後一個任務，因此較早的無條件 `deps.compile` 仍會執行。請參閱 <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手動編譯整合</.localized_link> 中的受保護別名。

然後在執行分片之前，在不編譯的情況下載入已還原的 SDK。這也能防止當路徑相依套件的來源比下載的建構產物更新時，任務探索去編譯該相依套件：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

兩個命令都需要相同的分片參考。`--prepare-only` 需要已上傳的建構產物，而如果準備好的應用程式構件遺失，`--no-download` 則會失敗。`--no-download` 會明確跳過你專案的測試準備別名（包括重試時），並在跳過設定步驟時列印通知。一般執行會保留其別名，即使你轉發 `--no-compile --no-deps-check` 亦然。將資料庫遷移保持在單獨的程序中，也能避免當遷移回歸測試自行載入那些模組時出現模組重新定義警告。

當測試不同環境時，請傳遞穩定的 `--scheme` 標籤，例如 `--scheme clickhouse-current` 或 `--scheme clickhouse-floor`。具有不同標籤的結果不會被視為同一設定的不穩定重試。

### 分片所需項目 {#what-the-shards-need}

上傳的建構產物是 `_build/test` 目錄。每個分片執行器仍然需要：
- 與建構階段相同的檢出
- 相同的 Elixir 和 Erlang/OTP 版本
- 相依套件來源，來自 `mix deps.get`

尚不支援從 umbrella 專案的根目錄進行分片。請在其其中一個應用程式內執行這兩個階段。

## 持續整合 {#continuous-integration}

### GitHub Actions {#github-actions}

在 GitHub Actions 上，建構階段會將分片索引寫入其步驟的 `matrix` 輸出。使用矩陣策略來平行執行分片：

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### 其他提供者 {#other-providers}

在 GitHub Actions 之外，建構階段會將計劃寫入 `.tuist-shard-matrix.json`：

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

使用 `shard_count` 來設定你的平行作業，並為每個作業分配其 `TUIST_SHARD_INDEX`，範圍從 `0` 到 `shard_count - 1`。在 Tuist 無法自動衍生參考的提供者上，也請為每個作業提供相同的 `TUIST_SHARD_REFERENCE`。
