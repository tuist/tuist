---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Tuist RunnersでDockerを使用: コンテナのビルドと実行、コンテナジョブ、サービスコンテナ、プライベートレジストリ。"
}
---
# Docker {#docker}

Linuxランナーには、すぐに使えるDockerが用意されています。各ジョブは仮想マシン内で独自のDockerデーモンを持ち、`docker` CLI、Buildx、Composeがあらかじめインストールされています。セットアップアクションや`sudo`は不要です。

```yaml
jobs:
  build:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t my-app .
      - run: docker run --rm my-app ./run-checks.sh
```

> [!NOTE]
> **Linuxのみ**
>
> macOSランナーはDockerデーモンを提供しません。Dockerデーモンが必要なジョブには、Linuxの<.localized_link href="/guides/features/runners/profiles">プロファイル</.localized_link>を使用してください。

## コンテナ内でのジョブ実行 {#running-a-job-in-a-container}

ジョブを実行するイメージを`container`で指定します。Tuistがそのイメージをプルし、すべてのステップをその中で実行します。

```yaml
jobs:
  test:
    runs-on: tuist-linux
    container:
      image: ghcr.io/my-org/android-ci:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: ./gradlew test
```

## サービスコンテナ {#service-containers}

`services`はGitHubホスト型ランナーと同じように動作します。サービスはマッピングされたポートで`localhost`からアクセスできます。

```yaml
jobs:
  test:
    runs-on: tuist-linux
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - run: mix test
```

## プライベートレジストリ {#private-registries}

プルまたはプッシュの前に、レジストリ固有のログインアクションまたは`docker login`を使用して認証してください。

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

ジョブレベルの`container`の場合、上記の例のように、代わりに`credentials`キーを通じて同じ認証情報を渡してください。

## イメージのプル {#image-pulls}

Docker Hubからのプルは、Tuistが運用するプルスルーキャッシュ経由で提供されるため、ジョブはDocker Hubの匿名レート制限を消費しません。他のレジストリのイメージは直接プルされます。

すべてのジョブは空のイメージストアから開始されるため、ワークフローで使用されるイメージはジョブ間で再利用されず、ジョブごとに1回プルされます。ジョブが大きなカスタムイメージをプルする場合は、イメージを小さくするか、キャッシュされたBuildxビルダーを使用してワークフロー内でビルドしてください。

```yaml
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          tags: my-app:latest
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

ネイティブジョブまたはコンテナジョブで永続的な依存関係ディレクトリを使用するには、<.localized_link href="/guides/features/runners/cache-volumes">キャッシュボリュームガイド</.localized_link>をご覧ください。
