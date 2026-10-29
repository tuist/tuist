---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux runner 已預備好 Docker 供即時使用。每個 job 都會在其虛擬機器內擁有專屬的 Docker daemon，而 `docker` CLI、Buildx 和 Compose 均已預先安裝。你無須執行設定 action，亦無須使用 `sudo`。

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
> **僅限 Linux**
>
> macOS runner 不提供 Docker daemon。如需 Docker daemon，請為相關 job 使用 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>。

## 在容器中執行 job {#running-a-job-in-a-container}

將 `container` 指向你的 job 應執行的映像檔。Tuist 會拉取該映像檔，並在其中執行每一個步驟：

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

`services` 的運作方式與在 GitHub-hosted runner 上相同。你可以透過對應的連接埠在 `localhost` 上存取這些服務：

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

在拉取或推送之前，請使用註冊表本身的登入 action 或 `docker login` 進行驗證：

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

對於 job 層級的 `container`，請改為透過 `credentials` 金鑰傳遞相同的憑證，如上例所示。

## 映像檔拉取 {#image-pulls}

Docker Hub 的拉取請求會透過 Tuist 運作的穿透式快取提供，因此 job 不會消耗 Docker Hub 的匿名速率限制。來自其他註冊表的映像檔則會直接拉取。

每個 job 啟動時都具備空的映像檔儲存區，因此你的工作流程所使用的映像檔會在每個 job 中拉取一次，而不會在不同 job 之間重複使用。如果某個 job 需要拉取大型自訂映像檔，請盡量保持映像檔小巧，或在工作流程中使用已快取的 Buildx builder 來建構它：

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

如要在原生 job 或容器 job 中使用持久化的依賴項目目錄，請參閱 <.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區指南</.localized_link>。
