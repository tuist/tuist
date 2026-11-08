---
{
  "title": "Elixir 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 測試分片，將 Elixir 專案的測試分散至多個 CI 執行器。"
}
---
# Elixir 測試分片 {#elixir-test-sharding}

Tuist Hex 套件內建支援將 Elixir 專案的測試進行分片。它會使用 Tuist 伺服器，依據歷史執行時間資料建立平衡的分片計畫，並只編譯你的專案一次，讓每個執行器都能直接開始執行測試。

> [!IMPORTANT]
> **必要條件**
>
> - 在設定 CI 分片工作之前，請先完成<.localized_link href="/guides/get-started/elixir-project">共用的 Elixir 設定</.localized_link>

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建置階段：** Tuist 會為測試編譯你的專案、列舉測試檔案，並在伺服器上建立**分片計畫**。伺服器會使用過去 30 天的歷史測試時間資料，將測試分配到各分片，使每個分片的執行時間大致相同。建置階段會上傳建置產物，並輸出一個**分片矩陣**，供你的 CI 系統用來產生平行執行器。
2. **測試階段：** 每個 CI 執行器會收到一個**分片索引**、下載建置產物，並只執行指派給該分片的測試。

> [!NOTE]
> 在已註冊的 Tuist Linux 執行器上，分片建置可以使用本機構件儲存空間。所有使用此類建置的分片都必須在同一站點的已註冊執行器上執行；若要将工作流程移至其他執行器，請停用本機儲存空間並重新執行建置。

測試以檔案為單位分配：同一檔案中的所有測試會在同一個分片上執行。Tuist 尚未見過的測試會獲得估算值，因此專案初期的計畫平衡度會低於後期。

## 建置階段 {#build-phase}

使用 `tuist.test.build` 任務準備測試分片：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

在叫用分片任務之前，請透過共用設定安裝的別名進行編譯。在冷啟動檢出時，Mix 可能在探索 `tuist.test.build` 的同時編譯相依套件，此時 Tuist 的相依快取還來不及還原它們。明確的編譯步驟會在與分片任務相同的測試環境中執行。

此任務會：
1. 在測試環境中編譯專案
2. 使用歷史時間資料在 Tuist 伺服器上建立分片計畫
3. 上傳建置產物，避免各分片重複編譯
4. 輸出供 CI 系統使用的分片矩陣

### 建置選項 {#build-options}

| 選項 | 說明 |
|--------|-------------|
| `--shard-max <N>` | 最大分片數量（預設：2） |
| `--shard-min <N>` | 最小分片數量 |
| `--shard-total <N>` | 精確的分片數量，而非範圍 |
| `--shard-max-duration <MS>` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-reference <REF>` | 分片用來查找計畫的名稱 |
| `--no-upload` | 規劃分片而不上傳建置產物；每個分片會自行編譯 |

其餘所有引數都會轉發給 `mix compile`。

分片參考會自動從 CI 環境變數（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）衍生，或可透過 `TUIST_SHARD_REFERENCE` 環境變數明確設定。在非上述提供者中，你必須將其設定為建置階段與同一管線執行中的各分片共用的值。在 GitHub Actions 上，參考也包含執行嘗試：當僅重新執行失敗的工作時，請傳遞原始建置工作的參考，而不是在分片工作中衍生新的參考。

## 測試階段 {#test-phase}

當設定 `TUIST_SHARD_INDEX` 時，套件會從伺服器取得分片指派、下載建置產物，並在不編譯的情況下只執行指派的測試檔案。在冷啟動執行器上，請在叫用任務前先初始化 SDK 並載入其路徑：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

在 Mix 的工作程序中編譯 SDK 不會將其載入父程序。明確的 `deps.loadpaths` 步驟可防止任務探索在下載建置產物前編譯剩餘的相依套件。這種單一指令形式會保留你專案的測試準備別名。如果其設定指令觸發編譯，請使用下方的獨立設定序列。

你傳入的任何測試檔案或目錄會進一步縮小分片範圍：只有同時位於分片中且在你選擇範圍內的檔案才會執行。若分片最終沒有測試，則會成功結束。

所有分片的結果會在儀表板上顯示為單一測試執行，其**分片**區段會顯示每個分片的耗時。

如果必須在測試之前執行設定，請先下載建置產物而不啟動應用程式：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

在停用編譯的情況下，於獨立程序中執行設定。例如，Ecto 專案可以使用以下方式建立並遷移資料庫：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

在此階段保留任何其他專案特定的準備工作。你的編譯別名也必須在進行初始化工作前尊重 `--no-compile`：Mix 只會將旗標轉發給清單別名的最後一個任務，因此較早的無條件 `deps.compile` 仍會執行。請參閱 <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手動編譯整合</.localized_link> 中的防護別名。

接著在執行分片前，載入已還原的 SDK 且不進行編譯。這也能防止當路徑相依套件的來源比下載的建置產物更新時，任務探索去編譯該相依套件：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

兩個指令都需要相同的分片參考。`--prepare-only` 需要已上傳的建置產物，而若缺少已準備的應用程式構件，`--no-download` 會失敗。`--no-download` 會明確跳過你專案的測試準備別名（包括重試時），並在跳過設定步驟時列印通知。一般執行會保留其別名，即使你轉發 `--no-compile --no-deps-check` 亦然。將資料庫遷移保持在獨立程序中，也能避免當遷移回歸測試自行載入那些模組時出現模組重新定義警告。

測試不同環境時，請傳遞穩定的 `--scheme` 標籤，例如 `--scheme clickhouse-current` 或 `--scheme clickhouse-floor`。具有不同標籤的結果不會被視為同一設定的不穩定重試。

### 分片所需內容 {#what-the-shards-need}

已上傳的建置產物是 `_build/test` 目錄。每個分片執行器仍需要：
- 與建置階段相同的檢出副本
- 相同的 Elixir 和 Erlang/OTP 版本
- 來自 `mix deps.get` 的相依套件原始碼

尚不支援從 umbrella 專案的根目錄進行分片。請在其其中一個應用程式內執行這兩個階段。

## 持續整合 {#continuous-integration}

### GitHub Actions {#github-actions}

在 GitHub Actions 上，建置階段會將分片索引寫入其步驟的 `matrix` 輸出。使用矩陣策略來平行執行分片：

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

在 GitHub Actions 之外，建置階段會將計畫寫入 `.tuist-shard-matrix.json`：

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

使用 `shard_count` 設定你的平行工作，並為每個工作分配其 `TUIST_SHARD_INDEX`，範圍從 `0` 到 `shard_count - 1`。若 Tuist 無法從該提供者推導出參考值，也請為每個工作提供相同的 `TUIST_SHARD_REFERENCE`。
