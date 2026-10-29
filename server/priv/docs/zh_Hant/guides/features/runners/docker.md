---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux 執行器已預先安裝 Docker，可直接使用。每個作業在其虛擬機器內都有專屬的 Docker daemon，且已預先安裝 `docker` CLI、Buildx 與 Compose。您不需要設定動作，也不需要 `sudo`。

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
> macOS 執行器不提供 Docker daemon。若作業需要 Docker daemon，請使用 Linux <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>。

## 在容器中執行作業 {#running-a-job-in-a-container}

將 `container` 指向您的作業應執行的映像檔。Tuist 會拉取該映像檔，並在其中執行每一個步驟：

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

`services` 的運作方式與 GitHub 託管執行器相同。服務可透過其對應的連接埠在 `localhost` 上存取：

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

在拉取或推送之前，請使用註冊表專屬的登入動作或 `docker login` 進行驗證：

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

針對作業層級的 `container`，請改為透過 `credentials` 金鑰傳遞相同的憑證，如上例所示。

## 映像檔拉取 {#image-pulls}

Docker Hub 的拉取請求會透過 Tuist 營運的穿透式快取提供，因此作業不會消耗 Docker Hub 的匿名速率限制。來自其他註冊表的映像檔則會直接拉取。

每個作業開始時都擁有空的映像檔儲存區，因此工作流程使用的映像檔會在每個作業中拉取一次，而非跨作業重複使用。如果作業拉取了大型的自訂映像檔，請保持映像檔小巧，或在工作流程中使用已快取的 Buildx 建構器來建構它：

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

若需在原生作業或容器作業中使用持續性的相依性目錄，請參閱 <.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區指南</.localized_link>。
