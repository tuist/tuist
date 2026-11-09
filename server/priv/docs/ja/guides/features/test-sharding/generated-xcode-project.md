---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Shardingを使用して、Tuistで生成されたXcodeプロジェクト内のテストを複数のCIランナーに分散します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-test-sharding}

生成されたプロジェクトのテストシャーディングでは、ビルドフェーズとテストフェーズの両方で `tuist test` を使用します。

## 仕組み {#how-it-works}

テストシャーディングは2段階のワークフローに従います：

1. **ビルドフェーズ：** Tuistはビルド済みの `.xctestrun` ファイルからテストモジュールを読み取り、サーバー上で **シャーディング計画** を作成します。サーバーは過去30日間の履歴的なテスト実行時間データを使用して、各シャードの実行時間がほぼ同じになるようにテストを分散させます。ビルドフェーズは、CIシステムが並列ランナーを起動するために使用する **シャードマトリクス** を出力します。
2. **テストフェーズ：** 各CIランナーは **シャードインデックス** と正確な **シャーディング計画ID** を受け取り、その計画に基づいてテストを選択して実行します。

`--shard-granularity suite` が使用されている場合、サーバーは現在の `.xctestrun` 内の各モジュールについて、ブランチ上の最近のCI実行で報告されたスイートを使用し、ブランチの履歴がないモジュールについてはプロジェクトのデフォルトブランチにフォールバックします。複数の実行を組み合わせることで、シャーディング実行や選択的テスト実行によって最新のレポートから除外されていたスイートを保持できます。サーバーは過去30日間のスイート実行時間を使用して期間を推定します。

Tuistは既知のスイートを要求されたシャード数にわたって均等に配分し、最後のシャードをキャッチオールとして使用します。例えば、`--shard-total 5` はシャードインデックス `0` から `4` までを生成し、シャードインデックス `4` がキャッチオールとなります。通常のシャードは割り当てられたスイートに対して `-only-testing` を付けて実行されます。最後のシャードは `-only-testing` なしで実行され、以前のシャードに割り当てられたすべてのスイートに対して `-skip-testing` を渡すため、新たに追加されたスイート、名前が変更されたスイート、または履歴 inventory に存在しないスイートも実行されます。モジュール粒度では `.xctestrun` ファイルがモジュールリストを提供するため、キャッチオールは不要です。

## ビルドフェーズ {#build-phase}

プロジェクトを生成し、テストをビルドして、シャーディング計画を作成します：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` フラグは、テストを実行せずにビルドするようTuistに指示します。シャード計画作成フラグ（`--shard-min`/`--shard-max`/`--shard-total`）を `--build-only` なしで指定すると、Tuistはエラーになります。

このコマンドは次のことを行います：
1. マニフェストからXcodeプロジェクトを生成します
2. テストをビルドします
3. 履歴的なタイミングデータを使用してTuistサーバー上にシャーディング計画を作成します
4. `.xctestproducts` バンドルをアップロードするか、シャードランナーが使用するシャードアーカイブを書き込みます
5. CIシステム用のシャードマトリクスを出力します
6. 適用可能な場合、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link> グラフを永続化し、シャードランナーがプロジェクトを再生成する必要がないようにします

<!-- @snippet: ./_xcode-build-options -->

## テストフェーズ {#test-phase}

各シャードランナーは割り当てられたテストを実行します：

```sh
tuist test --without-building
```

`--without-building` フラグは、再ビルドではなく以前にビルド済みのプロダクトを使用してテストを実行するようTuistに指示します。`--without-building` なしで `TUIST_SHARD_INDEX` / `--shard-index` が設定されている場合、Tuistはエラーになります。

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **選択的テスト**
>
> テストシャーディングは <.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link> とシームレスに連携します。選択的テストグラフはビルドフェーズ中に永続化され、各シャードで復元されるため、ランナーはプロジェクトを再生成する必要がありません。

## 継続的インテグレーション {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

マトリクス戦略を使用してシャードを並列に実行します：

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

Tuistは `.tuist-shard-child-pipeline.yml` を生成し、これを [子パイプライン](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines) としてトリガーできます。生成されたシャードジョブが拡張する `.tuist-shard` テンプレートジョブを定義します：

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

Tuistは [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) のパラメータを含む `.tuist-shard-continuation.json` を生成します。`shard-plan-id` パラメータは継続設定で宣言する必要があります：

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

Tuistはシャードごとに1ステップを含む `.tuist-shard-pipeline.yml` を生成します。`buildkite-agent pipeline upload` でアップロードします：

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

生成された各ステップには環境変数として `TUIST_SHARD_INDEX` と `TUIST_SHARD_PLAN_ID` が設定されています。共有スクリプトを使用して、各シャードステップにテストコマンドを追加します：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagicは動的なマトリクスジョブをサポートしていないため、シャードごとに個別のワークフローを定義します。Tuistは `TUIST_SHARD_MATRIX` と `TUIST_SHARD_COUNT` を `CM_ENV` ファイルに書き込み、ビルドワークフロー内で使用できるようにします。Codemagicの `CM_ENV` はワークフロースコープであるため、正確なシャーディング計画IDはワークフロー境界を越えません。テストワークフローは参照ベースのシャード検索にフォールバックします：

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

Bitriseでは、Tuistは `.tuist-shard-matrix.json`（`shard_plan_id` を含む）を `BITRISE_DEPLOY_DIR` に書き込み、下流のパイプラインステージでビルド成果物として利用できるようにします。各テストワークフローは `envman` を使用してダウンロードした成果物から計画IDを抽出し、テストコマンドの環境に渡します：

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
> Bitriseは実行時に動的な並列ジョブ作成をサポートしていません。パイプラインステージ内に固定数のシャードワークフローを定義してください。ステージ内のワークフローは自動的に並列で実行されます。

## 共有ボリューム {#shared-volumes}

デフォルトでは、ビルドフェーズは `.xctestproducts` バンドルをリモートストレージにアップロードし、各シャードランナーがそれをダウンロードします。CIプロバイダーが **共有ボリューム**（ジョブ間でマウントされる永続ストレージ）をサポートしている場合、テストプロダクトを共有ファイルシステム経由で渡すことで、このアップロード/ダウンロードを完全にスキップできます。

特に大きなテストバンドルの場合、シャードの起動時間を大幅に短縮できます。

共有ボリュームを使用するには：

1. **ビルドフェーズ**で、`--` の後に `-testProductsPath` を指定して共有ボリュームを指し示し、リモートアップロードをスキップするために `--shard-skip-upload` を追加します：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **テストフェーズ**で、同じ `-testProductsPath` を指定し、Tuistがテストプロダクトをダウンロードせずローカルから読み込むようにします：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | テストプロダクトバンドルのリモートストレージへのアップロードをスキップ |

## 自己管理の成果物 {#self-managed-artifacts}

CIプロバイダーにすでに成果物のアップロードおよびダウンロードステップがある場合、アーカイブと展開はTuistに任せ、転送はCI側で処理できます。

1. **ビルドフェーズ**で、`--shard-archive-path` を指定し、Tuistがテストプロダクトをアップロードする代わりに最適化されたシャードアーカイブをローカルに書き込むようにします：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. そのアーカイブをCIのネイティブな成果物ステップを使用してアップロードします。

3. 各 **テストフェーズ** ジョブで、アーカイブをダウンロードし、同じパスをTuistに渡します：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path` が設定されている場合、Tuistはリモートへのテストプロダクト転送をスキップし、代わりにローカルアーカイブを使用します。`--shard-skip-upload` も指定した場合、アーカイブパスが優先されます。

実行するテストがない場合（例えば、選択的テストによってすべてのテストターゲットがスキップされた場合）、ビルドフェーズは空のシャードマトリクスを出力し、アーカイブは書き込みません。マトリクスにシャードが含まれている場合のみ、アップロードステップを実行してください。

> [!IMPORTANT]
> 同時実行間の競合を避けるため、ワークフロー実行ごとに一意のパスを使用してください（例：CI実行IDを含める）。また、ランナー上に古いデータが蓄積しないよう、シャーディング完了後にシャードアーカイブをクリーンアップすることをお勧めします。

### Namespace {#namespace}

[Namespace](https://namespace.so) ランナーはGitHub Actionsの成果物と相性が良いです。`TUIST_TEST_SHARD_ARCHIVE_PATH` を一度設定し、ビルドジョブでシャードアーカイブをローカルに書き込み、それをアップロードして、各シャードジョブで `tuist test` を実行する前にダウンロードします：

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
