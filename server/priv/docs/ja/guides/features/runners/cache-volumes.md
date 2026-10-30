---
{
  "title": "キャッシュボリューム",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "GitHub Actions、Buildkite、GitLab CI を使用した Tuist Linux または macOS Runner ジョブ間で、Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、およびその他のディレクトリを維持します。"
}
---
# キャッシュボリューム {#cache-volumes}

Tuistランナーはジョブ間でキャッシュを保持できるため、新しいランナーでもウォームスタートできます。各ジョブは、最後に保存された内容のプライベートな書き込み可能なコピーを受け取ります。

- **管理対象キャッシュ**は、Xcodeコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのキャッシュをそれぞれ1ステップで保持します。Tuistは各キャッシュの場所を把握し、そのストレージ内に保持します。
- **カスタムボリューム**は、パッケージマネージャーのダウンロードキャッシュなど、任意のディレクトリを選択したキーの下に保持します。

チェックアウト後、キャッシュを使用するコマンドの前にステップを追加してください。Tuistランナー以外のランナーでは何も実行されず、キャッシュの問題によってジョブが失敗することはありません。ステップは警告をログに記録し、ジョブは空のキャッシュで続行されます。

## 管理対象キャッシュ {#managed-caches}

これらのステップはキャッシュの保存場所を決定するだけです。既存のキャッシュ設定を維持してください。`tuist setup cache`、またはコンパイルキャッシングを有効にするビルド設定（<.localized_link href="/guides/features/cache/xcode-cache">Xcodeキャッシュガイド</.localized_link>を参照）、モジュールキャッシュの認証、およびGradleのリモートビルドキャッシュ用の<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradleプラグイン</.localized_link>です。GitLab CIでは、`extends`が`before_script`を上書きするため、スニペットを`!reference`と組み合わせて使用してください。

### Xcodeキャッシュ {#xcode-cache}

macOSランナー上でXcodeのコンパイルキャッシュストアを保持します。

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### モジュールキャッシュ {#module-cache}

macOSランナー上でTuistのローカルキャッシュを保持します：<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>バイナリ、コンパイル済みマニフェスト、プラグイン、および選択的テストの結果。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradleキャッシュ {#gradle-cache}

LinuxおよびmacOSランナー上のGradleユーザーホーム内の`caches`および`wrapper`ディレクトリを保持します：依存関係、変換済みJAR、コンパイル済みビルドスクリプト、およびGradle配布物。使用する場合は、ステップの前に`GRADLE_USER_HOME`を設定し、`actions/setup-java`上の`cache: gradle`など、それらのディレクトリの他のキャッシングを無効にしてください。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## カスタムボリューム {#custom-volumes}

安定した`key`と`path`を選択し、依存関係をインストールする前にボリュームをアタッチしてください。パスは空であるか、存在しない必要があります。同じディレクトリに書き込むアーカイブキャッシュやアーティファクトの復元を削除してください。1つのボリュームに複数のディレクトリを保持する方法については、[1つのボリューム内の複数のディレクトリ](#several-directories-in-one-volume)を参照してください。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### 1つのボリューム内の複数のディレクトリ {#several-directories-in-one-volume}

1つのボリュームで複数のディレクトリを保持できます。GitHub Actionsでは1行に1つのパスをリストします。Buildkiteでは`path`をリストに設定します。GitLab CIでは、ディレクトリごとに1回ずつ`--path`を渡します。空行と周囲の空白は無視されます。

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **共有容量。** すべてのパスはボリュームの容量を共有し、一緒に復元および保存されます。
- **小さく関連性の高いディレクトリをグループ化します。** 大容量または頻繁に変更されるディレクトリには独自のボリュームを用意してください。
- **ネスト不可。** 1つのボリューム内のパスは互いを含んではなりません。
- **リストの変更はコールドスタートになります。** 各パスはボリューム内の独自のディレクトリに保存され、パスの記述方法によって識別されます。1つのパスから複数のパスへ切り替えたり、パスを追加、削除、書き換えたりすると、そのレイアウトが変更されます。変更後の最初のジョブは、影響を受けるパスに対してコールドスタートになります。リストから除外されたパスの内容は、クリアするまでボリューム内に残ります。

### キーの仕組み {#how-keys-work}

キーは時間とともに変化するボリュームに名前を付けます。`actions/cache`キーのような固定スナップショットの名前ではありません。

- **キーごとに1つのボリューム。** 各キーはリポジトリ（Buildkiteではパイプライン、GitLab CIではプロジェクト）、プラットフォーム、CPUアーキテクチャ、およびユーザーの範囲でスコープされます。それをアタッチするすべてのジョブは最後に保存された内容から開始し、対象となるジョブはその変更を同じボリュームに保存し戻します。
- **キーを安定させてください。** バージョンやロックファイルのハッシュをキーに入れないでください。`actions/cache`では、`deps-${{ hashFiles('Package.resolved') }}`のようなキーは変更ごとに新しいエントリを作成し、`restore-keys`は古いエントリにフォールバックします。ここでは、新しいキーは新しい空のボリュームです。変更後の最初のジョブはコールドスタートになり、古いボリュームは期限切れになるまで残ります。キーを維持し、ツールに内容の更新を任せてください。パッケージマネージャーは依然として有効なものを再利用します。
- **部分一致なし。** 復元キーはありません。まだ保存されていないキーは空から開始します。
- **意図的に最初からやり直す。** ジョブを空の状態から開始したい場合は、キーを変更するか、ダッシュボードでボリュームをクリアしてください。
- **`tuist-`キーはTuist用に予約されています。** 管理対象キャッシュは`tuist-`で始まるキーを使用するため、独自のボリュームには異なる名前を選んでください。

Linuxでは、パスは通常のディレクトリとしてマウントされるため、ツールは`deps`、`_build`、`node_modules`などの通常の場所を使用できます。通常の`.gitignore`ルールを維持してください。macOSでは、パスはシンボリックリンクです。`~/.npm`などのダウンロードキャッシュを使用してください。`node_modules`やキャッシュディレクトリを置き換えるツールはサポートされていません。`.gitignore`で末尾のスラッシュがないワークスペースリンクを無視してください。

## 変更の保存 {#saving-changes}

管理対象キャッシュとカスタムボリュームは、任意のブランチにおいて、独自のリポジトリからの成功したジョブの変更を保存します。

| プロバイダー | 変更を保存するジョブ |
| --- | --- |
| GitHub Actions | リポジトリ自体からのプッシュ、スケジュール、手動ディスパッチ、およびプルリクエストジョブ |
| Buildkite | パイプラインのリポジトリのWebhookおよびスケジュールビルド（プルリクエストを含む） |
| GitLab CI | プロジェクトのプッシュ、スケジュール、およびWebパイプライン、そして接続に<.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">APIアクセストークン</.localized_link>がある場合の独自のマージリクエストのパイプライン |

他のジョブもキャッシュを使用できますが、それらの変更は破棄されます。これには、フォークからのプルリクエスト、`pull_request_target`ジョブ、APIまたはダッシュボードから開始されたBuildkiteビルド、フォークからのマージリクエストやAPIアクセストークンがないGitLabマージリクエスト、およびタグが含まれます。ボリュームを変更しないジョブは、保存されたバージョンをそのまま残します。ランナープロファイルで保存するブランチを絞り込むことができます。[保存するブランチを選択](#choose-which-branches-save)をご覧ください。

並列ジョブは独立して動作し、異なるジョブからの変更はマージされません。認証情報や代替不可能なデータをキャッシュしないでください。

### 保存するブランチを選択 {#choose-which-branches-save}

管理対象キャッシュとカスタムボリュームを保存するブランチを変更できます。**Runners → Profiles**を開き、ジョブが使用するプロファイルを編集して、**Save cache from**を展開してください。ジョブは要求したプロファイルを使用します。GitHub Actionsでは`runs-on:`、Buildkiteではキュー、GitLab CIでは`tags:`として指定します。設定はそのプロファイル上のジョブが使用するすべてのボリューム（後で作成されたものを含む）に適用されます。

![Default branchをオンにし、developとrelease/*を追加のブランチとして追加した、Save cache fromセクションを展開したランナープロファイルフォーム](/images/guides/features/runners/save-cache-from.png)

デフォルトでは、リポジトリからのすべての成功したジョブが変更を保存します。特定のブランチからのみ保存するには、**Limit to specific branches**をオンにしてください。

- **Default branch**を有効にすると、各リポジトリのデフォルトブランチ上のジョブが保存できるようになります。追加のブランチからのみ保存するには、これをオフにしてください。
- **Additional branches**の下に、保存を行う最大20個のブランチ名を追加します。`*`をワイルドカードとして使用します。`release/*`は`release/1.0`に一致します。

[変更の保存](#saving-changes)に記載されているジョブは、ブランチが一致する場合に変更を保存します。GitHub Actionsのプッシュおよび手動ディスパッチの実行では、一致する名前のタグも一致対象となります。

他のブランチ上のジョブもキャッシュを使用できますが、それらの変更は破棄されます。フォークからのプルリクエストなど、決して保存を行わないジョブは、一致するブランチ上でも保存しません。これらの設定を狭めたりプロファイルを削除したりすると、許可されなくなった保留中の変更は破棄されます。削除されたプロファイルは、すべてのブランチから保存するというデフォルト動作に戻ります。

## 容量と保持 {#capacity-and-retention}

Xcodeキャッシュは初期状態で**30 GB**です。モジュールキャッシュ、Gradleキャッシュ、および各カスタムボリュームは初期状態で**20 GB**です。キャッシュやボリュームに別の容量を設定するには、`1gb`から`100gb`までのGB単位の整数を指定してください。

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradleキャッシュとカスタムボリュームは同じ`size`入力を受け取ります（GitLab CIでは`TUIST_GRADLE_CACHE_SIZE`および`TUIST_VOLUME_SIZE`、`tuist-cache-volume`の場合は`--size`）。サイズを大きくすると、次のジョブからコンテンツを維持したままボリュームが拡大します。サイズを小さくした場合、それはボリュームが次にクリアまたは期限切れになった後に適用されます。ジョブが同じキャッシュに対して異なるサイズを要求した場合、最大のサイズが適用されるため、各サイズは一箇所で宣言してください。

これらはすべて、**ジョブのマウントがない状態が7日間続くと**期限切れになり、期限切れ後の次のジョブは空のボリュームから開始します。TuistはXcodeキャッシュとモジュールキャッシュを容量に合わせて整理し、Gradleキャッシュステップでは、各ビルド後に7日間使用されていないエントリをGradleに削除させます。

カスタムボリュームは古い依存関係を自動で整理しません。ツールのクリーンアップ設定を使用してサイズを小さく保ってください。満杯のボリュームへの書き込みはジョブを失敗させる可能性があります。保存されたコンテンツがボリューム容量の**80%** に達し、ジョブがスペース不足になった場合、次のジョブは空のボリュームから開始し、その変更は新しい保存状態として始まります。

## ボリュームの検査とクリア {#inspecting-and-clearing-volumes}

**Runners → Volumes**を開いて、使用済みスペース、キャッシュヒット率、およびジョブ履歴を確認してください。アカウント管理者は**Clear volume**を選択して、将来のジョブを空の状態から開始させることができます。実行中のジョブはプライベートコピーを保持しますが、それを保存し戻すことはできません。Xcodeキャッシュとモジュールキャッシュもここに表示されますが、クリアすることはできません。
