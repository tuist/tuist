---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上使用 Docker：构建和运行容器、容器作业、服务容器以及私有注册表。"
}
---
# Docker {#docker}

Linux 运行器已预装 Docker，开箱即用。每个作业在其虚拟机内拥有独立的 Docker 守护进程，且已预安装 `docker` CLI、Buildx 和 Compose。你无需执行设置操作，也无需使用 `sudo`。

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
> **仅限 Linux**
>
> macOS 运行器不提供 Docker 守护进程。对于需要 Docker 的作业，请使用 Linux <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>。

## 在容器中运行作业 {#running-a-job-in-a-container}

将 `container` 指向作业应运行的镜像。Tuist 会拉取该镜像并在其中执行每一步：

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

## 服务容器 {#service-containers}

`services` 的工作方式与在 GitHub 托管的运行器上相同。可以通过 `localhost` 及其映射端口访问服务：

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

## 私有注册表 {#private-registries}

在拉取或推送之前，使用注册表自带的登录操作进行身份验证，或使用 `docker login`：

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

对于作业级别的 `container`，请改为通过 `credentials` 键传递相同的凭据，如上例所示。

## 镜像拉取 {#image-pulls}

Docker Hub 的拉取请求通过 Tuist 运营的透传缓存提供服务，因此作业不会消耗 Docker Hub 的匿名速率限制。来自其他注册表的镜像则直接拉取。

每个作业启动时镜像存储均为空，因此工作流使用的镜像会在每个作业中单独拉取，而不会在作业间复用。如果作业需要拉取大型自定义镜像，请尽量保持镜像小巧，或者在工作流中使用带缓存的 Buildx 构建器来构建它：

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

对于原生作业或容器作业中的持久化依赖目录，请参阅 <.localized_link href="/guides/features/runners/cache-volumes">缓存卷指南</.localized_link>。
