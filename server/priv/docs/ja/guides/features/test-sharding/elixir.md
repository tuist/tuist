---
{
  "title": "Elixirテストのシャーディング",
  "titleTemplate": ":title · テストのシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Shardingを使用して、Elixirプロジェクトのテストを複数のCIランナーに分散させます。"
}
---
# Elixirのテストシャーディング {#elixir-test-sharding}

Tuist Hexパッケージには、Elixirプロジェクトのテストをシャーディングするための組み込みサポートが含まれています。過去のタイミングデータに基づいてバランスの取れたシャーディングプランをTuistサーバーで作成し、プロジェクトを一度コンパイルすることで、すべてのランナーがすぐにテストを実行できるようにします。

> [!IMPORTANT]
> **要件**
>
> - CIのシャーディングジョブを設定する前に、<.localized_link href="/guides/get-started/elixir-project">共通のElixirセットアップ</.localized_link>を完了してください

## 仕組み {#how-it-works}

テストシャーディングは2段階のワークフローに従います：

1. **ビルドフェーズ：** Tuistはテスト用にプロジェクトをコンパイルし、テストファイルを列挙して、サーバー上で**シャーディングプラン**を作成します。サーバーは過去30日間のテストタイミングデータを使用して、各シャードの実行時間が概ね同じになるようにテストを分散させます。ビルドフェーズではビルドをアップロードし、CIシステムが並列ランナーを生成するために使用する**シャードマトリクス**を出力します。
2. **テストフェーズ：** 各CIランナーは**シャードインデックス**を受け取り、ビルドをダウンロードして、そのシャードに割り当てられたテストのみを実行します。

> [!NOTE]
> 登録済みのTuist Linuxランナーでは、シャードビルドでローカルアーティファクトストレージを使用できます。このようなビルドを使用するすべてのシャードは、同じサイトの登録済みランナーで実行する必要があります。ワークフローを他のランナーに移行する場合は、ローカルストレージを無効にしてビルドを再実行してください。

テストはファイル単位で分散されます。ファイル内のすべてのテストは同じシャードで実行されます。Tuistがまだ検知していないテストには推定値が適用されるため、プロジェクトの最初のプランは後続のプランよりもバランスが悪くなります。

## ビルドフェーズ {#build-phase}

`tuist.test.build`タスクを使用してテストシャードを準備します：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

シャーディングタスクを呼び出す前に、共通セットアップによってインストールされたエイリアスを通じてコンパイルを行います。クリーンなチェックアウト状態では、Tuistの依存関係キャッシュが復元する機会を得る前に、Mixが`tuist.test.build`を検出しながら依存関係をコンパイルすることがあります。明示的なコンパイルは、シャーディングタスクと同じテスト環境で実行されます。

このタスクは以下の処理を行います：
1. テスト環境でプロジェクトをコンパイルします
2. 過去のタイミングデータを使用してTuistサーバー上にシャーディングプランを作成します
3. シャードが再度コンパイルしないようビルドをアップロードします
4. CIシステム用のシャードマトリクスを出力します

### ビルドオプション {#build-options}

| オプション | 説明 |
|--------|-------------|
| `--shard-max <N>` | シャードの最大数（デフォルト：2） |
| `--shard-min <N>` | シャードの最小数 |
| `--shard-total <N>` | 範囲ではなく、正確なシャード数 |
| `--shard-max-duration <MS>` | シャードあたりの目標最大期間（ミリ秒） |
| `--shard-reference <REF>` | シャードがプランを見つけるための名前 |
| `--no-upload` | ビルドをアップロードせずにシャードを計画します。各シャードは各自でコンパイルを行います |

その他の引数はすべて`mix compile`に転送されます。

シャード参照はCI環境変数（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）から自動的に導出されるか、`TUIST_SHARD_REFERENCE`環境変数を通じて明示的に設定できます。これらのプロバイダー以外では、ビルドフェーズと1回のパイプライン実行のシャードが共有する値に設定する必要があります。GitHub Actionsでは、参照には実行試行も含まれます。失敗したジョブのみを再実行する場合、シャードジョブで新しい参照を導出するのではなく、元のビルドジョブの参照を渡してください。

## テストフェーズ {#test-phase}

`TUIST_SHARD_INDEX`が設定されている場合、パッケージはサーバーからシャード割り当てを取得し、ビルドをダウンロードして、コンパイルせずに割り当てられたテストファイルのみを実行します。クリーンなランナーでは、タスクを呼び出す前にSDKをブートストラップし、そのパスを読み込んでください：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

MixのワーカープロセスでSDKをコンパイルしても、親プロセスには読み込まれません。明示的な`deps.loadpaths`ステップにより、ビルドをダウンロードする前に残りの依存関係がコンパイルされるのを防ぎます。この単一コマンド形式は、プロジェクトのテスト準備エイリアスを保持します。セットアップコマンドがコンパイルを引き起こす場合は、以下の別個のセットアップ手順を使用してください。

渡したテストファイルやディレクトリによってシャードがさらに絞り込まれます。シャード内かつ選択範囲内のファイルのみが実行されます。テストがないシャードになった場合、正常に終了します。

すべてのシャードの結果はダッシュボード上で単一のテスト実行として表示され、**シャード**セクションに各シャードの実行時間が示されます。

テストの前にセットアップを実行する必要がある場合は、アプリケーションを起動せずにまずビルドをダウンロードしてください：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

コンパイルを無効にした別プロセスでセットアップを実行します。例えば、Ectoプロジェクトでは以下を使用してデータベースを作成およびマイグレーションできます：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

このフェーズでは他のプロジェクト固有の準備を維持してください。ブートストラップ作業を行う前に、コンパイルエイリアスも`--no-compile`を尊重する必要があります。Mixはリストエイリアスの最後のタスクにのみフラグを転送するため、以前の無条件の`deps.compile`は依然として実行されます。<.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手動コンパイル統合</.localized_link>のガード付きエイリアスを参照してください。

その後、シャードを実行する前にコンパイルなしで復元されたSDKを読み込みます。これにより、ソースがダウンロードされたビルドよりも新しい場合、タスク検出がパス依存関係をコンパイルするのも防止します：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

両方のコマンドには同じシャード参照が必要です。`--prepare-only`にはアップロードされたビルドが必要であり、準備されたアプリケーションアーティファクトが存在しない場合、`--no-download`は失敗します。`--no-download`はプロジェクトのテスト準備エイリアスを明示的にスキップし、再試行時も含め、セットアップステップをスキップする際に通知を表示します。通常のrunは、`--no-compile --no-deps-check`を転送した場合でもエイリアスを保持します。データベースマイグレーションを別プロセスで行うことで、マイグレーション回帰テストがそれらのモジュール自体を読み込む際のモジュール再定義警告も回避できます。

異なる環境をテストする際は、`--scheme clickhouse-current`や`--scheme clickhouse-floor`など、安定した`--scheme`ラベルを渡してください。異なるラベルの結果は、同じ構成の不安定な再実行としては扱われません。

### シャードに必要なもの {#what-the-shards-need}

アップロードされたビルドは `_build/test` ディレクトリです。各シャードランナーには依然として以下が必要です：
- ビルドフェーズと同じチェックアウト
- 同じElixirおよびErlang/OTPバージョン
- `mix deps.get` からの依存関係ソース

アンブレラプロジェクトのルートからのシャーディングはまだサポートされていません。そのアプリケーションの1つ内で両方のフェーズを実行してください。

## 継続的インテグレーション {#continuous-integration}

### GitHub Actions {#github-actions}

GitHub Actionsでは、ビルドフェーズがシャードインデックスをステップの `matrix` 出力に書き込みます。マトリクス戦略を使用してシャードを並列に実行します：

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

### 他のプロバイダー {#other-providers}

GitHub Actions以外では、ビルドフェーズがプランを `.tuist-shard-matrix.json` に書き込みます：

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

`shard_count` を使用して並列ジョブを設定し、各ジョブに `0` から `shard_count - 1` までの `TUIST_SHARD_INDEX` を割り当てます。Tuistが参照を導出しないプロバイダーでは、すべてのジョブに同じ `TUIST_SHARD_REFERENCE` も与えてください。
