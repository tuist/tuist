---
{
  "title": "Xcode Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Xcode tests across multiple CI runners with Tuist Test Sharding."
}
---
# Xcode テストシャーディング {#xcode-test-sharding}

> [!WARNING]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode テストインサイト</.localized_link> が設定されていること。シャーディングは、過去 30 日間のテストインサイトのタイミングデータを使用してシャードの負荷を分散します。インサイトがない場合、すべてのシャードはスイートが不明であるかのように実行されます。

Xcode プロジェクトのテストシャーディングでは、`tuist xcodebuild build-for-testing` を使用してシャードプランを作成し、`tuist xcodebuild test` を使用して各シャードを実行します。

## 仕組み {#how-it-works}

テストシャーディングは 2 段階のワークフローに従います:

1. **ビルドフェーズ:** Tuist はビルドされた `.xctestrun` ファイルからテストモジュールを読み取り、サーバー上に **シャードプラン** を作成します。サーバーは過去 30 日間の履歴テストタイミングデータを使用して、各シャードの実行時間がほぼ同じになるようにテストをシャードに分散します。ビルドフェーズは、CI システムが並列ランナーを起動するために使用する **シャードマトリックス** を出力します。
2. **テストフェーズ:** 各継続的インテグレーションランナーは **シャードインデックス** と正確な **シャードプラン識別子** を受け取り、そのプランのテスト選択を実行します。

スイート粒度の場合、サーバーはモジュールごとに既知のスイートを選択します。現在の `.xctestrun` 内の各モジュールについて、ビルド対象ブランチでの直近数回の CI 実行のスイートを結合し、ブランチ履歴のないモジュールについてはプロジェクトのデフォルトブランチにフォールバックします。最新の実行だけでなく複数の実行を読み取ることが重要なのは、シャーディングされた実行では各シャードの完了時にシャードごとのテスト実行がアップロードされるため、最新の実行にはこれまでに取り込まれたモジュールの一部しか含まれないからです。また、最新のブランチ実行でスキップされたスイートが選択的テスト実行によって隠されないようにするためでもあります。

`--shard-granularity suite` が使用されると、Tuist は要求されたシャード数に合わせて既知のスイートを分散し、最後のシャードをキャッチオールとして使用します。例えば、`--shard-total 5` はシャードインデックス `0` から `4` を生成し、シャードインデックス `4` がキャッチオールとなります。通常のシャードは、割り当てられたスイートに対して `-only-testing` を指定して実行されます。最後のシャードは `-only-testing` なしで実行され、以前のシャードに割り当てられたすべてのスイートに対して `-skip-testing` を渡すため、計画されたスイートに加えて、新たに追加されたスイートや履歴インベントリに欠落しているスイートも実行されます。モジュール粒度では `.xctestrun` ファイルがモジュールリストを提供するため、キャッチオールは不要です。

## ビルドフェーズ {#build-phase}

テストをビルドし、シャードプランを作成します:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

このコマンドは以下の処理を行います:
1. `xcodebuild build-for-testing` でテストをビルドします
2. 履歴タイミングデータを使用して Tuist サーバー上にシャードプランを作成します
3. `.xctestproducts` バンドルをアップロードするか、シャードランナーが使用するシャードアーカイブを書き込みます
4. CI システム用のシャードマトリックスを出力します

### ビルドオプション {#build-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | シャードの最大数。`--shard-max-duration` と組み合わせてシャード数を制限します |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | シャードの最小数 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | シャードの正確な数 (`--shard-min`/`--shard-max` と排他)。スイート粒度の場合、最後のシャードがキャッチオールとなります |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | シャードあたりの目標最大期間 (ミリ秒) |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (デフォルト) はテストモジュール全体をシャードに分散します。`suite` はより細かな負荷分散のために個々のテストクラスを分散します |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子 (サポートされている CI プロバイダーで自動導出) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist がリモートストレージへのテスト製品のアップロードではなく、最適化されたシャードアーカイブを書き込むパス |

## テストフェーズ {#test-phase}

各シャードランナーは割り当てられたテストを実行します:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### テストオプション {#test-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 実行するシャードのゼロベースのインデックス |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ビルドフェーズによって出力される正確なシャードプラン識別子。生成されたプロバイダー出力にはこの値が自動的に含まれます |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子 (サポートされている CI プロバイダーで自動導出) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | ローカルで管理されるシャードアーカイブへのパス。Tuist はリモートストレージからテスト製品をダウンロードする代わりにこれを抽出します |

Tuist は `.xctestproducts` バンドルをダウンロードし、そのシャードに割り当てられたテストのみを含むようにフィルタリングします。

## 継続的インテグレーション {#continuous-integration}

Tuist は以下の CI プロバイダーを自動的に検出します:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

他のプロバイダーの場合は、`.tuist-shard-matrix.json` ファイルを参照して並列ジョブを設定してください。

### GitHub Actions {#github-actions}

マトリックス戦略を使用してシャードを並列に実行します:

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
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
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

### GitLab CI {#gitlab-ci}

Tuist は `.tuist-shard-child-pipeline.yml` を生成し、これを [子パイプライン](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) としてトリガーできます。生成されたシャードジョブが継承する `.tuist-shard` テンプレートジョブを定義します:

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
    - |
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
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
    - |
      tuist xcodebuild test \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16'
```

### CircleCI {#circleci}

Tuist は [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 用のパラメーターを含む `.tuist-shard-continuation.json` を生成します。`shard-plan-id` パラメーターは継続設定で宣言する必要があります:

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
            tuist xcodebuild build-for-testing \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16' \
              --shard-total 5
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
            tuist xcodebuild test \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16'

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist はシャードごとに 1 ステップを含む `.tuist-shard-pipeline.yml` を生成します。`buildkite-agent pipeline upload` でアップロードします:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

生成された各ステップには環境変数として `TUIST_SHARD_INDEX` と `TUIST_SHARD_PLAN_ID` が設定されます。共有スクリプトを使用して、各シャードステップにテストコマンドを追加します:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic は動的なマトリックスジョブをサポートしていないため、シャードごとに個別のワークフローを定義します。Tuist は `TUIST_SHARD_MATRIX` と `TUIST_SHARD_COUNT` を `CM_ENV` ファイルに書き込み、ビルドワークフロー内で使用できるようにします。Codemagic の `CM_ENV` はワークフロー単位のスコープであるため、正確なシャードプラン識別子はワークフローの境界を越えません。テストワークフローは参照ベースのシャード検索にフォールバックします:

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
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

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
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'

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

Bitrise では、Tuist は `shard_plan_id` (を含む `.tuist-shard-matrix.json`) を `BITRISE_DEPLOY_DIR` に書き込み、下流のパイプラインステージでビルド成果物として利用できるようにします。各テストワークフローは `envman` を使用してダウンロードした成果物からプラン ID を抽出し、テストコマンドの環境に渡します:

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
                tuist xcodebuild build-for-testing \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16' \
                  --shard-total 5
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
                tuist xcodebuild test \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16'
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
> Bitrise はランタイムでの動的な並列ジョブ作成をサポートしていません。パイプラインステージで固定数のシャードワークフローを定義してください。ステージ内のワークフローは自動的に並列で実行されます。

## 共有ボリューム {#shared-volumes}

デフォルトでは、ビルドフェーズが `.xctestproducts` バンドルをリモートストレージにアップロードし、各シャードランナーがそれをダウンロードします。CI プロバイダーが **共有ボリューム** (ジョブ間でマウントされる永続ストレージ) をサポートしている場合、テスト製品を共有ファイルシステム経由で渡すことで、このアップロード/ダウンロードを完全にスキップできます。

これにより、特に大規模なテストバンドルの場合、シャードの起動時間を大幅に短縮できます。

共有ボリュームを使用するには:

1. **ビルドフェーズ** で、共有ボリュームを指す `-testProductsPath` を渡し、リモートアップロードをスキップするために `--shard-skip-upload` を追加します:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **テストフェーズ** で、同じ `-testProductsPath` を渡すことで、Tuist がテスト製品をダウンロードする代わりにローカルから読み取ります:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> 同時実行間の競合を避けるために、ワークフロー実行ごとに一意のパスを使用してください (例: CI 実行 ID を含める)。また、シャード処理完了後にテスト製品をクリーンアップし、ボリューム上に古いデータが蓄積しないようにしてください。

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | テスト製品バンドルのリモートストレージへのアップロードをスキップ |

## セルフマネージド成果物 {#self-managed-artifacts}

CI プロバイダーにすでに成果物のアップロードおよびダウンロードステップがある場合、アーカイブと展開は Tuist に任せ、転送は CI に任せることができます。

1. **ビルドフェーズ** で、`--shard-archive-path` を渡すことで、Tuist がテスト製品をアップロードする代わりに最適化されたシャードアーカイブをローカルに書き込むようにします:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. CI のネイティブな成果物ステップを使用してそのアーカイブをアップロードします。

3. 各 **テストフェーズ** ジョブで、アーカイブをダウンロードし、同じパスを Tuist に渡します:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path` が設定されている場合、Tuist はリモートのテスト製品転送をスキップし、代わりにローカルアーカイブを使用します。`--shard-skip-upload` も同時に渡した場合、アーカイブパスが優先されます。

### Namespace {#namespace}

[Namespace](https://namespace.so) ランナーは GitHub Actions の成果物と相性が良いです。`TUIST_TEST_SHARD_ARCHIVE_PATH` を一度設定することで、ビルドジョブがシャードアーカイブをローカルに書き込み、それをアップロードして、各シャードジョブで `tuist xcodebuild test` を実行する前にダウンロードできるようにします:

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5
      - uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
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
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
