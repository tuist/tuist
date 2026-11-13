---
{
  "title": "Xcode テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Sharding を使用して、Xcode のテストを複数の CI ランナーに分散します。"
}
---
# Xcodeテストのシャーディング {#xcode-test-sharding}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcodeテストインサイト</.localized_link>が設定されていること。シャーディングは過去30日間のテストインサイトのタイミングデータを使用してシャードを均等に配分します。インサイトがない場合、すべてのシャードはスイートが不明であるかのように実行されます。

Xcodeプロジェクトのテストシャーディングでは、`tuist xcodebuild build-for-testing`を使用してシャードプランを作成し、`tuist xcodebuild test`を使用して各シャードを実行します。

## 仕組み {#how-it-works}

テストシャーディングは2段階のワークフローに従います。

1. **ビルドフェーズ:** Tuistはビルドされた`.xctestrun`ファイルからテストモジュールを読み取り、サーバー上で**シャードプラン**を作成します。サーバーは過去30日間の履歴的なテストタイミングデータを使用して、各シャードの実行時間がほぼ同じになるようにテストをシャードに配分します。ビルドフェーズは、CIシステムが並列ランナーを生成するために使用する**シャードマトリックス**を出力します。
2. **テストフェーズ:** 各継続的インテグレーションランナーは**シャードインデックス**と正確な**シャードプラン識別子**を受け取り、そのプランのテスト選択を実行します。

スイート粒度の場合、サーバーは現在の`.xctestrun`内の各モジュールについて、ブランチ上の最近のCI実行で報告されたスイートを使用し、ブランチの履歴がないモジュールについてはプロジェクトのデフォルトブランチにフォールバックします。複数の実行を組み合わせることで、シャーディング実行や選択的実行によって最新のレポートから除外されたスイートを保持できます。

`--shard-granularity suite`を使用する場合、Tuistは既知のスイートを要求されたシャード数にわたって均等に配分し、最後のシャードをキャッチオールとして使用します。例えば、`--shard-total 5`はシャードインデックス`0`から`4`を生成し、シャードインデックス`4`をキャッチオールとします。通常のシャードは割り当てられたスイートに対して`-only-testing`を指定して実行されます。最後のシャードは`-only-testing`を指定せずに実行され、以前のシャードに割り当てられたすべてのスイートに対して`-skip-testing`を渡すため、計画されたスイートに加えて、新たに追加されたスイートや履歴インベントリに存在しないスイートも実行されます。モジュール粒度では`.xctestrun`ファイルがモジュールリストを提供するため、キャッチオールは不要です。

## ビルドフェーズ {#build-phase}

テストをビルドし、シャードプランを作成します。

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

このコマンドは次の処理を行います。
1. `xcodebuild build-for-testing`を使用してテストをビルドします
2. 履歴的なタイミングデータを使用してTuistサーバー上にシャードプランを作成します
3. `.xctestproducts`バンドルをアップロードするか、シャードランナーが使用するシャードアーカイブを書き出します
4. CIシステム用のシャードマトリックスを出力します

<!-- @snippet: ./_xcode-build-options -->

## テストフェーズ {#test-phase}

各シャードランナーは割り当てられたテストを実行します。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

<!-- @snippet: ./_xcode-test-options -->

## 継続的インテグレーション {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

マトリックス戦略を使用してシャードを並列に実行します。

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

Tuistは`.tuist-shard-child-pipeline.yml`を生成し、これを[子パイプライン](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines)としてトリガーできます。生成されたシャードジョブが拡張する`.tuist-shard`テンプレートジョブを定義します。

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

Tuistは[continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)用のパラメータを含む`.tuist-shard-continuation.json`を生成します。`shard-plan-id`パラメータは継続構成内で宣言する必要があります。

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

Tuistはシャードごとに1ステップを含む`.tuist-shard-pipeline.yml`を生成します。`buildkite-agent pipeline upload`を使用してアップロードします。

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

生成された各ステップには環境変数として`TUIST_SHARD_INDEX`と`TUIST_SHARD_PLAN_ID`が設定されています。共有スクリプトを使用して、各シャードステップにテストコマンドを追加します。

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagicは動的なマトリックスジョブをサポートしていないため、シャードごとに個別のワークフローを定義します。Tuistはビルドワークフロー内で使用するために`TUIST_SHARD_MATRIX`と`TUIST_SHARD_COUNT`を`CM_ENV`ファイルに書き込みます。Codemagicの`CM_ENV`はワークフロースコープであるため、正確なシャードプラン識別子はワークフローの境界を越えません。テストワークフローは参照ベースのシャード検索にフォールバックします。

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

Bitriseでは、Tuistは（`shard_plan_id`を含む）`.tuist-shard-matrix.json`を`BITRISE_DEPLOY_DIR`に書き込み、下流のパイプラインステージでビルド成果物として利用可能にします。各テストワークフローは、テストコマンドの環境に到達するように、`envman`を使用してダウンロードした成果物からプランIDを抽出します。

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
> Bitriseは実行時に動的な並列ジョブ作成をサポートしていません。パイプラインステージ内に固定数のシャードワークフローを定義してください。ステージ内のワークフローは自動的に並列で実行されます。

## 共有ボリューム {#shared-volumes}

デフォルトでは、ビルドフェーズは`.xctestproducts`バンドルをリモートストレージにアップロードし、各シャードランナーがそれをダウンロードします。CIプロバイダーが**共有ボリューム**（ジョブ間でマウントされる永続ストレージ）をサポートしている場合、テスト成果物を共有ファイルシステム経由で渡すことで、このアップロード/ダウンロードを完全にスキップできます。

これにより、特に大規模なテストバンドルの場合、シャードの起動時間を大幅に短縮できます。

共有ボリュームを使用するには:

1. **ビルドフェーズ**で、共有ボリュームを指す`-testProductsPath`を渡し、リモートアップロードをスキップするために`--shard-skip-upload`を追加します。

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **テストフェーズ**で、同じ`-testProductsPath`を渡すことで、Tuistがテスト成果物をダウンロードせずローカルで読み取るようにします。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> ワークフローの実行ごとに一意のパスを使用し（例: CI実行IDを含める）、同時実行間の競合を回避してください。また、シャード処理完了後にテスト成果物をクリーンアップし、ボリューム上に古いデータが蓄積されないようにする必要があります。

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | テスト成果物バンドルのリモートストレージへのアップロードをスキップ |

## セルフマネージドな成果物 {#self-managed-artifacts}

CIプロバイダーにすでに成果物のアップロードおよびダウンロードステップがある場合、アーカイブと展開はTuistに任せ、転送はCI側で処理できます。

1. **ビルドフェーズ**で`--shard-archive-path`を渡し、Tuistがテスト成果物をアップロードする代わりに最適化されたシャードアーカイブをローカルに書き込むようにします。

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. CIのネイティブな成果物ステップを使用して、そのアーカイブをアップロードします。

3. 各**テストフェーズ**ジョブでアーカイブをダウンロードし、同じパスをTuistに渡します。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path`が設定されている場合、Tuistはリモートへのテスト成果物の転送をスキップし、代わりにローカルアーカイブを使用します。`--shard-skip-upload`も同時に指定した場合は、アーカイブパスの設定が優先されます。

### Namespace {#namespace}

[Namespace](https://namespace.so)ランナーはGitHub Actionsの成果物とうまく連携します。`TUIST_TEST_SHARD_ARCHIVE_PATH`を一度設定することで、ビルドジョブがシャードアーカイブをローカルに書き込み、それをアップロードして、`tuist xcodebuild test`を実行する前に各シャードジョブでダウンロードできるようにします。

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
