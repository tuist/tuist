---
{
  "title": "Elixir 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 測試分片，將 Elixir 專案的測試分散到多個 CI 執行器上。"
}
---
# Elixir 測試分片 {#elixir-test-sharding}

Tuist Hex 套件內建支援將 Elixir 專案的測試分片。它會使用 Tuist 伺服器，根據歷史計時資料建立均衡的分片計劃，並只編譯你的專案一次，讓每個執行器可以直接執行測試。

> [!IMPORTANT]
> **必要條件**
>
> - 在設定 CI 分片工作之前，請先完成<.localized_link href="/guides/get-started/elixir-project">共用 Elixir 設定</.localized_link>

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建構階段：** Tuist 會為測試編譯你的專案、列舉測試檔案，並在伺服器上建立**分片計劃**。伺服器會使用過去 30 天的歷史測試計時資料，將測試分配到各分片，使每個分片的耗時大致相同。建構階段會上傳構件，並輸出**分片矩陣**，供你的 CI 系統用來產生平行執行器。
2. **測試階段：** 每個 CI 執行器會收到一個**分片索引**、下載構件，並只執行指派給該分片的測試。

> [!NOTE]
> 在已註冊的 Tuist Linux 執行器上，分片建構可以使用本機構件儲存。所有使用此類構件的分片都必須在同一站點的已註冊執行器上執行；若要將工作流程移至其他執行器，請停用本機儲存並重新執行建構。

測試以檔案為單位分配：同一檔案中的所有測試都會在同一個分片上執行。Tuist 尚未見過的測試會獲得估算值，因此專案的初期計劃不如後期計劃均衡。

## 建構階段 {#build-phase}

使用 `tuist.test.build` 工作準備測試分片：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

在叫用分片工作之前，請透過共用設定安裝的別名進行編譯。在冷啟動檢出時，Mix 可能在探索 `tuist.test.build` 的過程中編譯相依套件，而 Tuist 的相依快取尚未有機會還原它們。明確的編譯會在與分片工作相同的測試環境中執行。

此工作會：
1. 在測試環境中編譯專案
2. 使用歷史計時資料在 Tuist 伺服器上建立分片計劃
3. 上傳構件，避免各分片重複編譯
4. 為你的 CI 系統輸出分片矩陣

### 建構選項 {#build-options}

| 選項 | 說明 |
|--------|-------------|
| `--shard-max <N>` | 最大分片數（預設：2） |
| `--shard-min <N>` | 最小分片數 |
| `--shard-total <N>` | 精確的分片數，而非範圍 |
| `--shard-max-duration <MS>` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-reference <REF>` | 分片用來查找計劃的名稱 |
| `--no-upload` | 規劃分片但不上傳構件；每個分片會自行編譯 |

所有其他引數都會轉發至 `mix compile`。

分片參考會自動從 CI 環境變數（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）衍生，或可透過 `TUIST_SHARD_REFERENCE` 環境變數明確設定。在這些提供者之外，你必須將其設定為建構階段與同一次管道運行的各分片共用的值。在 GitHub Actions 上，參考也包含運行嘗試次數：當僅重新執行失敗的工作時，請傳遞原始建構工作的參考，而不是在分片工作中衍生新的參考。

## 測試階段 {#test-phase}

當設定 `TUIST_SHARD_INDEX` 時，套件會從伺服器取得分片指派、下載構件，並在不編譯的情況下只執行指派的測試檔案。在冷啟動執行器上，請在叫用工作之前引導 SDK 並載入其路徑：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

在 Mix 的工作進程中編譯 SDK 不會將其載入父進程。明確的 `deps.loadpaths` 步驟可防止任務探索在下載構件之前編譯其餘相依套件。此單一指令形式會保留你專案的測試準備別名。如果其設定指令觸發編譯，請使用下方的獨立設定序列。

你傳入的任何測試檔案或目錄會進一步縮窄分片：只有同時屬於該分片且在你選擇範圍內的檔案才會執行。若分片最終沒有測試，則會成功結束。

所有分片的結果會在儀表板上合併為單一**測試執行**，其「分片」區段會顯示每個分片的耗時。

如果必須在測試之前執行設定，請先下載構件而不啟動應用程式：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

在停用編譯的情況下，於獨立進程中執行設定。例如，Ecto 專案可以使用以下方式建立並遷移資料庫：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

在此階段保留任何其他專案專屬的準備工作。你的編譯別名也必須在執行引導工作前尊重 `--no-compile`：Mix 只會將旗標轉發至清單別名的最後一個工作，因此較早的無條件 `deps.compile` 仍會執行。請參閱 <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手動編譯整合</.localized_link> 中的防護別名。

然後在執行分片之前，載入已還原的 SDK 而不進行編譯。這也能防止任務探索在來源比下載的構件更新時編譯路徑相依套件：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

兩個指令都需要相同的分片參考。`--prepare-only` 需要已上傳的構件，而如果準備好的應用程式構件遺失，`--no-download` 會失敗。`--no-download` 會明確跳過你專案的測試準備別名（包括重試時），並在跳過設定步驟時列印通知。一般運行會保留其別名，即使你轉發 `--no-compile --no-deps-check`。將資料庫遷移放在獨立進程中，也能避免當遷移回歸測試自行載入那些模組時出現模組重新定義警告。

測試不同環境時，請傳遞穩定的 `--scheme` 標籤，例如 `--scheme clickhouse-current` 或 `--scheme clickhouse-floor`。具有不同標籤的結果不會被視為同一設定的不穩定重跑。

### 分片所需 {#what-the-shards-need}

已上傳的構件位於 `_build/test` 目錄。每個分片執行器仍需要：
- 與構建階段相同的檢出
- 相同的 Elixir 和 Erlang/OTP 版本
- 相依套件來源，來自 `mix deps.get`

尚不支援從 umbrella 專案的根目錄進行分片。請在其其中一個應用程式內執行兩個階段。

## 持續整合 {#continuous-integration}

### GitHub Actions {#github-actions}

在 GitHub Actions 上，構建階段會將分片索引寫入其步驟的 `matrix` 輸出。使用矩陣策略並行運行分片：

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

在 GitHub Actions 之外，構建階段會將計劃寫入 `.tuist-shard-matrix.json`：

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

使用 `shard_count` 設定你的並行工作，並為每個工作分配其 `TUIST_SHARD_INDEX`，範圍從 `0` 到 `shard_count - 1`。對於 Tuist 無法自動推導參考的提供者，也請為每個工作提供相同的 `TUIST_SHARD_REFERENCE`。
