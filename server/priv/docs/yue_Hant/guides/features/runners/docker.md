---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上使用 Docker：構建同運行容器、容器工作、服務容器，以及私人註冊表。"
}
---
# Docker {#docker}

Linux runner 已預備好 Docker，隨時可用。每個 job 都會喺自己嘅虛擬機入面運行獨立嘅 Docker daemon，而且 `docker` CLI、Buildx 同 Compose 已經預先安裝。你唔需要執行 setup action，亦都唔需要 `sudo`。

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
> **只限 Linux**
>
> macOS runner 不提供 Docker daemon。如果 job 需要 Docker daemon，請使用 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>。

## 喺容器內運行 job {#running-a-job-in-a-container}

將 `container` 指向 job 應該運行嘅映像檔。Tuist 會拉取該映像檔，並喺其中執行每一個 step：

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

## 服務容器 {#service-containers}

`services` 嘅運作方式同 GitHub-hosted runner 一樣。你可以透過 `localhost` 及對應嘅連接埠存取服務：

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

## 私人註冊表 {#private-registries}

喺拉取或推送之前，請使用註冊表專屬嘅登入 action，或者 `docker login` 進行認證：

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

對於 job 層級嘅 `container`，請改為透過 `credentials` 金鑰傳遞相同嘅憑證，如上例所示。

## 映像檔拉取 {#image-pulls}

Docker Hub 嘅拉取請求會經由 Tuist 營運嘅 pull-through cache 提供，因此 job 不會消耗 Docker Hub 嘅匿名速率限制。來自其他註冊表嘅映像檔則會直接拉取。

每個 job 開始時映像檔儲存區都係空白，因此你嘅 workflow 所用嘅映像檔會喺每個 job 中拉取一次，而唔會喺不同 job 之間重用。如果 job 需要拉取大型自訂映像檔，請盡量保持映像檔細小，或者喺 workflow 中使用帶有快取嘅 Buildx builder 進行建構：

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

如需喺原生 job 或容器 job 中使用持久化依賴目錄，請參閱<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區指南</.localized_link>。
