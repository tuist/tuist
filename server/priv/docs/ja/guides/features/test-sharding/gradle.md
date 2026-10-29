---
{
  "title": "Gradle Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Gradle tests across multiple CI runners with Tuist Test Sharding."
}
---
# Gradle テストシャーディング {#gradle-test-sharding}

Tuist Gradle プラグインには、テストシャーディングの組み込みサポートが含まれています。プロジェクトのテストタスクの以前の CI 実行で Tuist が記録したテストスイートを計画し、Tuist サーバーを使用して過去のタイミングデータに基づいてバランスの取れたシャードプランを作成します。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">テストインサイト</.localized_link> を構成する必要があります

## 動作原理 {#how-it-works}

テストシャーディングは 2 段階のワークフローに従います：

1. **ビルドフェーズ：** Tuist は、プロジェクト用に記録されたテストスイートからサーバー上で **シャードプラン** を作成します。サーバーは過去 30 日間のテストタイミングデータを使用して、各シャードがほぼ同じ時間になるようにテストをシャード間で分散させます。ビルドフェーズは、CI システムが並列ランナーを生成するために使用する **シャードマトリックス** を出力します。
2. **テストフェーズ：** 各 CI ランナーは **シャードインデックス** を受け取り、そのシャードに割り当てられたテストのみを実行します。最後のシャードは、他のシャードに割り当てられていないすべてのテストスイートも実行します。

## ビルドフェーズ {#build-phase}

`tuistPrepareTestShards` タスクを使用してテストシャードを準備します：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

このタスクは：
1. コンパイルせずに、シャーディング対象のテストタスクを持つプロジェクトを検出します
2. 過去 30 日間にそれらのプロジェクトに対して記録されたテストスイートとタイミングから、Tuist サーバー上でシャードプランを作成します
3. CI システム用のシャードマトリックスを出力します

テストスイートがまだ記録されていない場合（例：初回実行時）、プランにはすべてのテストを実行する単一のシャードが含まれます。

### ビルドオプション {#build-options}

Gradle プロジェクトプロパティを通じてシャーディングを構成します：

| プロパティ | 説明 |
|----------|-------------|
| `-PtuistShardMax=<N>` | 最大シャード数（デフォルト：2） |
| `-PtuistShardMin=<N>` | 最小シャード数 |
| `-PtuistShardMaxDuration=<MS>` | シャードあたりの目標最大期間（ミリ秒単位） |
| `-PtuistShardTestTask=<NAME>` | テストがシャーディングされるテストタスク（例：`testDebugUnitTest`）。デフォルトではビルド内のすべてのテストタスクが対象です |

複数のビルドバリアントを持つ Android プロジェクトでは、バリアントごとに 1 つのユニットテストタスクがあります。シャードが実行するバリアントに `-PtuistShardTestTask` を設定し、そのバリアントを持つプロジェクトのみが計画されるようにします：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

シャード参照は CI 環境変数（`GITHUB_RUN_ID`、`CI_PIPELINE_ID` など）から自動的に導出されるか、`TUIST_SHARD_REFERENCE` 環境変数を通じて明示的に設定できます。

## テストフェーズ {#test-phase}

各シャードランナーは標準の `test` タスクを使用して割り当てられたテストを実行します。`TUIST_SHARD_INDEX` が設定されている場合、プラグインはサーバーからシャード割り当てを自動的に取得し、割り当てられたテストスイートのみを含むようにテスト実行をフィルタリングします。シャードに割り当てられたスイートがないプロジェクトのテストタスクはスキップされます。

最後のシャードはすべてのテストタスクを実行し、他のシャードに割り当てられたスイートを除外するため、新規追加されたものなど、まだ実行が記録されていないスイートも実行されます。

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

ビルドフェーズで `-PtuistShardTestTask` を設定した場合、各シャードで同じタスクを実行します（例：`./gradlew testDebugUnitTest`）。

## 継続的インテグレーション {#continuous-integration}

Tuist は以下の CI プロバイダーを自動的に検出します：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

他のプロバイダーの場合は、`.tuist-shard-matrix.json` ファイルを参照して並列ジョブを設定してください。

### GitHub Actions {#github-actions}

マトリックス戦略を使用してシャードを並列に実行します：

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - id: build
        run: ./gradlew tuistPrepareTestShards -PtuistShardMax=5

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
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist は `.tuist-shard-child-pipeline.yml` を生成し、これを [子パイプライン](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) としてトリガーします。生成されたシャードジョブが拡張する `.tuist-shard` テンプレートジョブを定義します：

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
    - tuist auth login
    - ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

子パイプラインには `.tuist-shard` ジョブテンプレートが必要です：

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist は [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 用のパラメーターを含む `.tuist-shard-continuation.json` を生成します：

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    docker:
      - image: cimg/openjdk:17.0
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

jobs:
  test-shard:
    docker:
      - image: cimg/openjdk:17.0
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            tuist auth login
            ./gradlew test

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist はシャードごとに 1 つのステップを含む `.tuist-shard-pipeline.yml` を生成します。`buildkite-agent pipeline upload` でアップロードしてください：

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

生成された各ステップには環境に `TUIST_SHARD_INDEX` が設定されています。共有スクリプトを使用して、各シャードステップにテストコマンドを追加します：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic は動的なマトリックスジョブをサポートしていないため、シャードごとに個別のワークフローを定義します。Tuist は各ワークフロー内で使用するために `TUIST_SHARD_MATRIX` と `TUIST_SHARD_COUNT` を `CM_ENV` ファイルに書き込みます：

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: linux_x2
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          ./gradlew test

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitrise では、Tuist は `.tuist-shard-matrix.json` を `BITRISE_DEPLOY_DIR` に書き込み、下流のパイプラインステージでビルド成果物として利用できるようにします。事前定義された並列ワークフローを持つ Bitrise Pipelines を使用します：

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                ./gradlew test
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
> Bitrise は実行時に動的な並列ジョブ作成をサポートしていません。パイプラインステージで固定数のシャードワークフローを定義してください。ステージ内のワークフローは自動的に並列で実行されます。
