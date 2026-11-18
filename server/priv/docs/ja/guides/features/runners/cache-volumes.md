---
{
  "title": "キャッシュボリューム",
  "titleTemplate": ":title · ランナー · 機能 · ガイド · Tuist",
  "description": "GitHub Actions、Buildkite、GitLab CI を使用した Tuist Linux または macOS ランナーのジョブ間で、Xcode キャッシュ、モジュールキャッシュ、Gradle キャッシュ、およびその他のディレクトリを保持します。"
}
---
# キャッシュボリューム {#cache-volumes}

Tuistランナーはジョブ間でキャッシュを保持できるため、新しいランナーもウォームスタートします。各ジョブは、最後に保存された内容のプライベートな書き込み可能なコピーを受け取ります。

- **管理対象キャッシュ**は、Xcodeコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのキャッシュをそれぞれ1ステップで保持します。Tuistは各キャッシュの場所を把握し、ストレージ内で管理します。
- **カスタムボリューム**は、パッケージマネージャーのダウンロードキャッシュなど、任意のディレクトリを選択したキーの下に保持します。

チェックアウトの後、キャッシュを使用するコマンドの前にステップを追加してください。Tuistランナー以外のランナーでは何もしません。また、キャッシュの問題によってジョブが失敗することはありません。ステップは警告をログに記録し、ジョブは空のキャッシュで続行されます。

## 管理対象キャッシュ {#managed-caches}

これらのステップはキャッシュの保存先を決定するだけです。既存のキャッシュ設定を維持してください。`tuist setup cache`、またはコンパイルキャッシングを有効にするビルド設定（<.localized_link href="/guides/features/cache/xcode-cache">Xcodeキャッシュガイド</.localized_link>を参照）、モジュールキャッシュの認証、およびGradleのリモートビルドキャッシュ用の<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradleプラグイン</.localized_link>です。GitLab CIでは、`extends`が`before_script`を上書きするため、スニペットを`!reference`と組み合わせてください。

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

macOSランナー上でTuistのローカルキャッシュを保持します。<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link>のバイナリ、コンパイル済みマニフェスト、プラグイン、および選択的テストの結果です。

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

LinuxおよびmacOSランナー上のGradleユーザーホーム内の`caches`ディレクトリと`wrapper`ディレクトリを保持します。依存関係、変換されたJAR、コンパイル済みビルドスクリプト、およびGradleディストリビューションが含まれます。使用する場合は、ステップの前に`GRADLE_USER_HOME`を設定し、`actions/setup-java`上の`cache: gradle`など、それらのディレクトリに対する他のキャッシングを無効にしてください。

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

安定した`key`と`path`を選択し、依存関係をインストールする前にボリュームをアタッチしてください。パスは空であるか、存在しない必要があります。同じディレクトリに書き込むアーカイブキャッシュやアーティファクトの復元を削除してください。1つのボリュームに複数のディレクトリを保持するには、[1つのボリュームに複数のディレクトリ](#several-directories-in-one-volume)を参照してください。

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

### 1つのボリュームに複数のディレクトリ {#several-directories-in-one-volume}

1つのボリュームに複数のディレクトリを格納できます。GitHub Actionsでは、パスを1行ずつリストします。Buildkiteでは、`path`をリストに設定します。GitLab CIでは、ディレクトリごとに1回ずつ`--path`を渡します。空行と周囲の空白は無視されます。

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
- **小さく関連性のあるディレクトリをグループ化します。** 大きい、または頻繁に変更されるディレクトリには専用のボリュームを与えてください。
- **ネスト不可。** 1つのボリューム内のパスは互いを含んではなりません。
- **リストの変更はコールドスタートになります。** 各パスは、パスの記述方法で識別されるボリューム内の独自のディレクトリに保存されます。1つのパスから複数のパスへ切り替えたり、パスの追加、削除、書き換えを行うと、そのレイアウトが変更されます。変更後の最初のジョブは、影響を受けるパスに対してコールドスタートします。リストから除外されたパスの内容は、削除するまでボリューム内に残ります。

### キーの仕組み {#how-keys-work}

キーは時間とともに変化するボリュームに名前を付けます。`actions/cache`キーのような固定スナップショットの名前ではありません。

- **キーごとに1つのボリューム。** 各キーは、リポジトリ（Buildkiteではパイプライン、GitLab CIではプロジェクト）、プラットフォーム、CPUアーキテクチャ、およびユーザーのスコープを持ちます。それをアタッチするすべてのジョブは、最後に保存された内容から開始し、資格のあるジョブは変更を同じボリュームに保存し戻します。
- **キーを安定させます。** バージョンやロックファイルのハッシュをキーに入れないでください。`actions/cache`では、`deps-${{ hashFiles('Package.resolved') }}`のようなキーは変更ごとに新しいエントリを作成し、`restore-keys`は古いものにフォールバックします。ここでは、新しいキーは新しい空のボリュームです。変更後の最初のジョブはコールドスタートし、古いボリュームは期限切れになるまで残ります。キーを維持し、ツールに内容の更新を任せてください。パッケージマネージャーは、まだ有効なものを再利用します。
- **部分一致なし。** 復元キーはありません。まだ保存されていないキーは空で始まります。
- **`tuist-`で始まるキーは予約されています**。これらはTuist独自のキャッシュ用であり、ボリュームがアタッチされる前に拒否されます。
- **意図的にリセットします。** ジョブを空の状態で開始したい場合は、キーを変更するか、ボリュームを削除してください。
- **`tuist-`キーはTuistに任せます。** 管理対象キャッシュは`tuist-`で始まるキーを使用するため、独自のボリュームには異なる名前を選択してください。

Linuxでは、パスは通常のディレクトリとしてマウントされるため、ツールは`deps`、`_build`、`node_modules`などの通常の場所を使用できます。通常の`.gitignore`ルールを維持してください。macOSでは、パスはシンボリックリンクです。`~/.npm`などのダウンロードキャッシュを使用してください。`node_modules`やキャッシュディレクトリを置き換えるツールはサポートされていません。`.gitignore`で末尾のスラッシュのないワークスペースリンクを無視してください。

## 変更の保存 {#saving-changes}

管理対象キャッシュとカスタムボリュームは、任意のブランチにおいて、独自のリポジトリからの成功したジョブの変更を保存します。

| プロバイダー | 変更を保存するジョブ |
| --- | --- |
| GitHub Actions | リポジトリ自体からのプッシュ、スケジュール、手動ディスパッチ、プルリクエストジョブ |
| Buildkite | パイプラインのリポジトリのWebhookおよびスケジュールビルド（プルリクエストを含む） |
| GitLab CI | プロジェクトのプッシュ、スケジュール、Webパイプライン、および接続に<.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">APIアクセストークン</.localized_link>がある場合のマージリクエストのパイプライン |

他のジョブもキャッシュを使用できますが、変更は破棄されます。これには、フォークからのプルリクエスト、`pull_request_target`ジョブ、APIまたはダッシュボードから開始されたBuildkiteビルド、フォークからのマージリクエストやAPIアクセストークンがないGitLabマージリクエスト、タグが含まれます。ボリュームを変更しないジョブは、保存されたバージョンをそのまま残します。ランナープロファイルで保存するブランチを絞り込むことができます。[保存するブランチを選択](#choose-which-branches-save)をご覧ください。

並行ジョブは独立して動作し、異なるジョブからの変更はマージされません。認証情報や代替不可能なデータをキャッシュしないでください。

### 保存するブランチを選択 {#choose-which-branches-save}

管理対象キャッシュとカスタムボリュームを保存するブランチを変更できます。**Runners → Profiles**を開き、ジョブが使用するプロファイルを編集して、**Save cache from**を展開します。ジョブは要求したプロファイルを使用します。GitHub Actionsでは`runs-on:`、Buildkiteではキュー、GitLab CIでは`tags:`として指定します。設定は、そのプロファイル上のジョブが使用するすべてのボリューム（後で作成されたものも含む）に適用されます。

![Default branchをオンにし、developとrelease/*を追加ブランチとして追加した、Save cache fromセクションを展開したランナープロファイルフォーム](/images/guides/features/runners/save-cache-from.png)

デフォルトでは、リポジトリからのすべての成功したジョブが変更を保存します。一部のブランチのみから保存するには、**Limit to specific branches**をオンにします。

- **Default branch**を有効にすると、各リポジトリのデフォルトブランチ上のジョブが保存を行います。追加ブランチのみから保存するには、これをオフにします。
- **Additional branches**の下に、保存を行う最大20個のブランチ名を追加します。`*`をワイルドカードとして使用します。`release/*`は`release/1.0`に一致します。

[変更の保存](#saving-changes)に記載されているジョブは、ブランチが一致する場合に変更を保存します。GitHub Actionsのプッシュおよび手動ディスパッチ実行では、一致する名前のタグも一致とみなされます。

他のブランチ上のジョブもキャッシュを使用できますが、変更は破棄されます。フォークからのプルリクエストなど、決して保存を行わないジョブは、一致するブランチ上でも保存しません。これらの設定を絞り込んだりプロファイルを削除したりすると、許可されなくなった保留中の変更は破棄されます。削除されたプロファイルは、すべてのブランチから保存するというデフォルト動作に戻ります。

## 容量と保持 {#capacity-and-retention}

Xcodeキャッシュは**30 GB**から始まります。モジュールキャッシュ、Gradleキャッシュ、および各カスタムボリュームは**20 GB**から始まります。キャッシュまたはボリュームに別の容量を設定するには、`1gb`から`100gb`までのGB単位の整数値を指定します。

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

Gradleキャッシュとカスタムボリュームは同じ`size`入力を受け取ります（GitLab CIでは`TUIST_GRADLE_CACHE_SIZE`および`TUIST_VOLUME_SIZE`、`tuist-cache-volume`の場合は`--size`）。大きいサイズを指定すると、次のジョブから内容を保ったままボリュームが拡大します。小さいサイズは、ボリュームが次に削除または期限切れになった後に適用されます。ジョブが同じキャッシュに対して異なるサイズを要求した場合、最大のサイズが適用されるため、サイズは1箇所で宣言してください。

すべては**ジョブのマウントがない状態が7日間続くと**期限切れになり、期限切れ後の次のジョブは空のボリュームで開始します。TuistはXcodeキャッシュとモジュールキャッシュを容量に合わせてプルーニングし、Gradleキャッシュステップは各ビルド後に7日間使用されていないエントリをGradleに削除させます。

カスタムボリュームは古い依存関係をプルーニングしません。ツールのクリーンアップ設定を使用して小さく保ってください。満杯のボリュームへの書き込みはジョブを失敗させる可能性があります。保存された内容がボリューム容量の**80%** に達し、ジョブがスペースを使い果たした場合、次のジョブは空のボリュームで開始し、その変更は新しい保存状態を開始します。

## ボリュームの検査と削除 {#inspecting-and-clearing-volumes}

使用済みスペース、キャッシュヒット率、ジョブ履歴を確認するには、**Runners → Volumes**を開きます。Xcode、モジュール、Gradleキャッシュもここに表示されます。

アカウント管理者は**Delete volume**を選択して、ボリュームとその保存された内容を削除できます。実行中のジョブはプライベートコピーを保持しますが、それらを保存し戻すことはできず、同じキーを使用する次のジョブは空のボリュームで開始します。削除されたボリュームはリストに表示されなくなります。

ターミナルまたはワークフローからボリュームを削除するには、そのIDを検索して`tuist runner volume delete`に渡します。

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

同じ操作は、[API](https://tuist.dev/api/docs#tag/runners)を通じて`DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`として、また[MCPサーバー](/guides/features/agentic-coding/mcp)を通じて`delete_runner_volume`として利用可能です。これらすべてには、アカウント管理権限または`account:runners:write`スコープを持つトークンが必要です。
