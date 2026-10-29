---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux 러너는 Docker를 즉시 사용할 수 있는 상태로 제공됩니다. 각 작업은 가상 머신 내부에서 자체 Docker 데몬을 가지며, `docker` CLI, Buildx 및 Compose가 사전 설치되어 있습니다. 별도의 설정 액션이 필요하지 않으며, `sudo`도 필요하지 않습니다.

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
> **Linux 전용**
>
> macOS 러너는 Docker 데몬을 제공하지 않습니다. Docker 데몬이 필요한 작업에는 Linux <.localized_link href="/guides/features/runners/profiles">프로필</.localized_link>을 사용하세요.

## 컨테이너에서 작업 실행하기 {#running-a-job-in-a-container}

작업이 실행될 이미지를 `container`에 지정하세요. Tuist가 해당 이미지를 가져와서 모든 단계를 그 안에서 실행합니다:

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

## 서비스 컨테이너 {#service-containers}

`services`는 GitHub 호스팅 러너에서와 동일하게 작동합니다. 서비스는 매핑된 포트에서 `localhost`로 접근할 수 있습니다:

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

## 비공개 레지스트리 {#private-registries}

이미지를 가져오거나 푸시하기 전에 레지스트리의 자체 로그인 액션 또는 `docker login`을 사용하여 인증하세요:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

작업 수준 `container`의 경우, 위의 예시와 같이 `credentials` 키를 통해 동일한 자격 증명을 전달하세요.

## 이미지 풀 {#image-pulls}

Docker Hub 풀은 Tuist에서 운영하는 풀스루 캐시를 통해 제공되므로, 작업이 Docker Hub의 익명 속도 제한을 소모하지 않습니다. 다른 레지스트리의 이미지는 직접 가져옵니다.

모든 작업은 빈 이미지 저장소로 시작하므로, 워크플로우에서 사용하는 이미지는 작업 간에 재사용되지 않고 작업당 한 번씩 가져옵니다. 작업에서 큰 규모의 custom 이미지를 가져오는 경우, 이미지를 작게 유지하거나 캐시된 Buildx 빌더를 사용하여 워크플로우 내에서 빌드하세요:

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

네이티브 작업 또는 컨테이너 작업에서 영구적인 종속성 디렉토리를 사용하려면 <.localized_link href="/guides/features/runners/cache-volumes">캐시 볼륨 가이드</.localized_link>를 참조하세요.
