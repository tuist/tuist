---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Shardingを使用して、Tuistで生成されたXcodeプロジェクト内のテストを複数のCIランナーに分散します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-test-sharding}

生成されたプロジェクトのテストシャーディングでは、ビルドフェーズとテストフェーズの両方で `tuist test` を使用します。

## 動作原理 {#how-it-works}

テストシャーディングは2段階のワークフローに従います：

1. **ビルドフェーズ：** Tuistはビルド済みの `.xctestrun` ファイルからテストモジュールを読み取り、サーバー上に **シャードプラン** を作成します。サーバーは過去30日間のテスト実行時間データを使用して、各シャードの実行時間が概ね均等になるようにテストを分散させます。ビルドフェーズは **シャードマトリックス** を出力し、CIシステムはこのマトリックスを使用して並列ランナーを起動します。
2. **テストフェーズ：** 各CIランナーは **シャードインデックス** と正確な **シャードプラン識別子** を受け取り、そのプランで指定されたテストを実行します。

`--shard-granularity suite` が使用されている場合、Tuistはビルドフェーズ中にスイートを列挙するためにすべてのテストバンドルを起動しません。代わりに、現在の `.xctestrun` ファイルがモジュールリストを提供し、サーバーはモジュールごとに既知のスイートを選択します。各モジュールについて、ビルド対象のブランチでの直近の数回のCI実行におけるスイートの和集合を取ります。そのブランチに履歴がないモジュールの場合、サーバーはプロジェクトのデフォルトブランチにフォールバックします。最新の実行ではなく複数の実行を読み取ることが重要なのは、シャーディングされた実行では各シャードが完了するたびにシャードごとのテスト実行がアップロードされるため、最新の実行にはこれまでに取り込まれたモジュールの一部しか含まれていないこと、および選択的テストの実行によって最新のブランチ実行でスキップされたスイートが隠蔽されないようにするためです。サーバーは依然として過去30日間のスイート実行時間を使用して期間を推定します。

Tuistはこれらの既知のスイートを要求されたシャード数に合わせて分散させ、最後のシャードをキャッチオールとして使用します。例えば、`--shard-total 5` はシャードインデックス `0` から `4` までを生成し、シャードインデックス `4` がキャッチオールとなります。通常のシャードは割り当てられたスイートに対して `-only-testing` を付けて実行されます。最後のシャードは `-only-testing` なしで実行され、以前のシャードに割り当てられたすべてのスイートに対して `-skip-testing` を渡すため、新たに追加されたスイート、名前が変更されたスイート、または履歴インベントリに欠落しているスイートも実行されます。モジュール粒度では `.xctestrun` ファイルがモジュールリストを提供するため、キャッチオールは不要です。

## ビルドフェーズ {#build-phase}

プロジェクトを生成し、テストをビルドして、シャードプランを作成します：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` フラグは、Tuistにテストを実行せずにビルドするよう指示します。シャードプランニングフラグ（`--shard-min`/`--shard-max`/`--shard-total`）を `--build-only` なしで渡すと、Tuistはエラーになります。

このコマンドは：
1. マニフェストからXcodeプロジェクトを生成します
2. テストをビルドします
3. 過去のタイミングデータを使用してTuistサーバー上にシャードプランを作成します
4. `.xctestproducts` バンドルをアップロードするか、シャードランナーが使用するシャードアーカイブを書き出します
5. CIシステム用のシャードマトリックスを出力します
6. 該当する場合、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link> グラフを永続化し、シャードランナーがプロジェクトを再生成する必要がないようにします

### ビルドオプション {#build-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | シャードの最大数。`--shard-max-duration` と組み合わせてシャード数を制限します |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | シャードの最小数 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | シャードの正確な数（`--shard-min`/`--shard-max` とは排他）。スイート粒度の場合、最後のシャードがキャッチオールとなります |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | シャードあたりの目標最大期間（ミリ秒単位） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（デフォルト）はテストモジュール全体をシャードに分散させます。`suite` は個々のテストクラスを分散させ、より細かなバランス調整を行います |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子（サポートされているCIプロバイダーで自動導出） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuistが最適化されたシャードアーカイブを書き込むパス。テスト製品をリモートストレージにアップロードする代わりに使用されます |

## テストフェーズ {#test-phase}

各シャードランナーは割り当てられたテストを実行します：

```sh
tuist test --without-building
```

`--without-building` フラグは、Tuistに再ビルドせず以前にビルドされた製品を使用してテストを実行するよう指示します。`--without-building` なしで `TUIST_SHARD_INDEX` / `--shard-index` が設定されている場合、Tuistはエラーになります。

### テストオプション {#test-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 実行するシャードのゼロベースのインデックス |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ビルドフェーズによって出力される正確なシャードプラン識別子。生成されたプロバイダー出力にはこの値が自動的に含まれます |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子（サポートされているCIプロバイダーで自動導出） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | ローカルで管理されるシャードアーカイブへのパス。Tuistはリモートストレージからテスト製品をダウンロードする代わりにこれを抽出します |

Tuistは`.xctestproducts`バンドルをダウンロードし、そのシャードに割り当てられたテストのみを含むようにフィルタリングします。

> [!TIP]
> **選択的テスト**
>
> テストのシャーディングは<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>とシームレスに連携します。選択的テストのグラフはビルドフェーズ中に永続化され、各シャードで復元されるため、ランナーはプロジェクトを再生成する必要がありません。

## 継続的インテグレーション {#continuous-integration}

Tuistは以下のCIプロバイダーを自動的に検出します：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

他のプロバイダーの場合は、`.tuist-shard-matrix.json`ファイルを参照して並列ジョブを設定してください。

### GitHub Actions {#github-actions}

マトリックス戦略を使用してシャードを並列実行します：

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuistは`.tuist-shard-child-pipeline.yml`を生成し、これを[子パイプライン](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines)としてトリガーできます。生成されたシャードジョブが継承する`.tuist-shard`テンプレートジョブを定義します：

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --build-only --shard-total 5
  artifacts:
    paths:
      - .tuist-shard-child-pipeline.yml

test-shards:
  stage: test
  needs: [build-shards]
  trigger:
    include:
      - artifact: .tuist-shard-child-pipeline.yml
        job: build-shards
    strategy: depend
```

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --without-building
```

### CircleCI {#circleci}

Tuistは[continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)用のパラメータを含む`.tuist-shard-continuation.json`を生成します。`shard-plan-id`パラメータは継続設定で宣言する必要があります：

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    macos:
      xcode: "16.0"
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            tuist test --build-only --shard-total 5
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: .tuist-shard-continuation.json

workflows:
  setup:
    jobs:
      - build-shards
```

```yaml
# .circleci/continue-config.yml
version: 2.1

parameters:
  shard-indices:
    type: string
    default: ""
  shard-count:
    type: integer
    default: 0
  shard-plan-id:
    type: string
    default: ""

jobs:
  test-shard:
    macos:
      xcode: "16.0"
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            export TUIST_SHARD_PLAN_ID=<< pipeline.parameters.shard-plan-id >>
            tuist auth login
            tuist test --without-building

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuistはシャードごとに1つのステップを含む`.tuist-shard-pipeline.yml`を生成します。`buildkite-agent pipeline upload`を使用してアップロードします：

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist test --build-only --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

生成された各ステップには環境変数として`TUIST_SHARD_INDEX`と`TUIST_SHARD_PLAN_ID`が設定されています。共有スクリプトを使用して、各シャードステップにテストコマンドを追加します：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagicは動的なマトリックスジョブをサポートしていないため、シャードごとに個別のワークフローを定義します。Tuistはビルドワークフロー内で使用するために`TUIST_SHARD_MATRIX`と`TUIST_SHARD_COUNT`を`CM_ENV`ファイルに書き込みます。Codemagicの`CM_ENV`はワークフロースコープであるため、正確なシャードプラン識別子はワークフローの境界を越えません。テストワークフローは参照ベースのシャード検索にフォールバックします：

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: mac_mini_m2
    environment:
      xcode: latest
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          tuist test --build-only --shard-total 5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: mac_mini_m2
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          tuist test --without-building

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitriseでは、Tuistは`.tuist-shard-matrix.json`（`shard_plan_id`を含む）を`BITRISE_DEPLOY_DIR`に書き込み、下流のパイプラインステージでビルド成果物として利用可能にします。各テストワークフローは`envman`を使用してダウンロードした成果物からプランIDを抽出し、テストコマンドの環境に渡します：

```yaml
# bitrise.yml
pipelines:
  test-pipeline:
    stages:
      - build-stage: {}
      - test-stage: {}

stages:
  build-stage:
    workflows:
      - build-shards: {}
  test-stage:
    workflows:
      - test-shard-0: {}
      - test-shard-1: {}
      - test-shard-2: {}
      - test-shard-3: {}
      - test-shard-4: {}

workflows:
  build-shards:
    steps:
      - script:
          title: Build and plan shards
          inputs:
            - content: |
                tuist auth login
                tuist test --build-only --shard-total 5
      - deploy-to-bitrise-io: {}

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - pull-intermediate-files: {}
      - script:
          title: Set shard plan ID from artifact
          inputs:
            - content: |
                PLAN_ID=$(jq -r '.shard_plan_id' "$BITRISE_DEPLOY_DIR/.tuist-shard-matrix.json")
                envman add --key TUIST_SHARD_PLAN_ID --value "$PLAN_ID"
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist test --without-building
  test-shard-1:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 1
  test-shard-2:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 2
  test-shard-3:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 3
  test-shard-4:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 4
```

> [!TIP]
> Bitriseは実行時の動的な並列ジョブ作成をサポートしていません。パイプラインステージで固定数のシャードワークフローを定義してください。ステージ内のワークフローは自動的に並列実行されます。

## 共有ボリューム {#shared-volumes}

デフォルトでは、ビルドフェーズは`.xctestproducts`バンドルをリモートストレージにアップロードし、各シャードランナーがそれをダウンロードします。CIプロバイダーが**共有ボリューム**（ジョブ間でマウントされる永続ストレージ）をサポートしている場合、テスト製品を共有ファイルシステム経由で渡すことで、このアップロード/ダウンロードを完全にスキップできます。

これにより、特に大規模なテストバンドルの場合、シャードの起動時間を大幅に短縮できます。

共有ボリュームを使用するには：

1. **ビルドフェーズ**で、共有ボリュームを指す`-testProductsPath`（`--`の後）を渡し、リモートアップロードをスキップするために`--shard-skip-upload`を追加します：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **テストフェーズ**で、同じ`-testProductsPath`を渡し、Tuistがテスト製品をダウンロードせずにローカルから読み取るようにします：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | テスト製品バンドルのリモートストレージへのアップロードをスキップします |

## 自己管理型アーティファクト {#self-managed-artifacts}

CIプロバイダーにすでにアーティファクトのアップロードおよびダウンロードステップがある場合、Tuistにアーカイブと展開を処理させ、CIに転送を処理させることができます。

1. **ビルドフェーズ**で、`--shard-archive-path`を渡し、Tuistがテスト製品をアップロードする代わりに最適化されたシャードアーカイブをローカルに書き込むようにします：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. CIのネイティブなアーティファクトステップを使用してそのアーカイブをアップロードします。

3. 各**テストフェーズ**ジョブで、アーカイブをダウンロードし、同じパスをTuistに渡します：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path`が設定されている場合、Tuistはリモートへのテスト製品の転送をスキップし、代わりにローカルアーカイブを使用します。`--shard-skip-upload`も指定した場合、アーカイブパスが優先されます。

実行するテストがない場合（例えば、選択的テストによってすべてのテストターゲットがスキップされた場合）、ビルドフェーズは空のシャードマトリックスを出力し、アーカイブは書き込まれません。マトリックスにシャードがある場合にのみ、アップロードステップを実行してください。

> [!IMPORTANT]
> 並列実行間の競合を避けるため、ワークフロー実行ごとに一意のパスを使用してください（例：CI実行IDを含める）。また、ランナー上に古いデータが蓄積しないよう、シャーディング完了後にシャードアーカイブをクリーンアップすることをお勧めします。

### Namespace {#namespace}

[Namespace](https://namespace.so)ランナーはGitHub Actionsアーティファクトと相性が良いです。`TUIST_TEST_SHARD_ARCHIVE_PATH`を一度設定することで、ビルドジョブがシャードアーカイブをローカルに書き込み、それをアップロードし、`tuist test`を実行する前に各シャードジョブでダウンロードできるようにします：

```yaml
name: Tests
on: [pull_request]

env:
  TUIST_TEST_SHARD_ARCHIVE_PATH: /tmp/shards/${{ github.run_id }}/bundle.aar

jobs:
  build:
    name: Build test shards
    runs-on: namespace-profile-default-macos
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5
      - if: toJSON(fromJSON(steps.build.outputs.matrix).shard) != '[]'
        uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: namespace-profile-default-macos
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
