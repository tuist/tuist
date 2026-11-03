---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上使用 Docker：構建同運行容器、容器工作、服務容器同私人註冊表。"
}
---
# Docker {#docker}

Linux runner 已預備好 Docker。每個 job 都會喺自己嘅虛擬機內獲得獨立嘅 Docker daemon，而 `docker` CLI、Buildx 同 Compose 亦已預先安裝。你唔需要執行 setup action，亦唔需要 `sudo`。

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
> macOS runner 不提供 Docker daemon。如果需要，請為 job 使用 Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link>。

## 喺容器內運行 job {#running-a-job-in-a-container}

將 `container` 指向 job 應該運行嘅映像檔。Tuist 會拉取該映像檔，並喺其中運行每一步驟：

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

`services` 嘅運作方式與 GitHub-hosted runner 相同。服務可透過映射嘅端口喺 `localhost` 上存取：

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

## 私人 Registry {#private-registries}

喺拉取或推送之前，請使用 registry 自身嘅登入 action 或 `docker login` 進行驗證：

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

Docker Hub 拉取請求會透過 Tuist 營運嘅 pull-through cache 提供，因此 job 不會消耗 Docker Hub 嘅匿名速率限制。來自其他 registry 嘅映像檔則會直接拉取。

每個 job 都以空白嘅映像檔儲存區開始，因此 workflow 使用嘅映像檔會按 job 拉取一次，而唔會喺不同 job 之間重用。如果 job 拉取大型自訂映像檔，請保持映像檔細小，或者喺 workflow 中使用帶有快取嘅 Buildx builder 進行建構：

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

如需喺原生 job 或容器 job 中使用持久依賴目錄，請參閱 <.localized_link href="/guides/features/runners/cache-volumes">cache volumes 指南</.localized_link>。
