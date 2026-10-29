---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux-раннеры поставляются с готовым к использованию Docker. Каждое задание получает собственный демон Docker внутри виртуальной машины задания, а CLI `docker`, Buildx и Compose предустановлены. Вам не нужно действие для настройки, и вам не нужен `sudo`.

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
> **Только Linux**
>
> macOS-раннеры не предоставляют демон Docker. Используйте Linux-<.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> для заданий, которым он нужен.

## Запуск задания в контейнере {#running-a-job-in-a-container}

Укажите `container` на образ, в котором должно выполняться ваше задание. Tuist загружает его и выполняет каждый шаг внутри него:

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

## Сервисные контейнеры {#service-containers}

`services` работает так же, как и на раннерах, размещенных на GitHub. Сервисы доступны на `localhost` по их сопоставленным портам:

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

## Приватные реестры {#private-registries}

Выполните аутентификацию с помощью собственного действия входа в реестр или `docker login`, прежде чем выполнять pull или push:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

Для `container` на уровне задания передайте те же учетные данные через ключ `credentials`, как показано в примере выше.

## Загрузка образов {#image-pulls}

Загрузки из Docker Hub обслуживаются через сквозной кэш, который управляет Tuist, поэтому задания не потребляют анонимный лимит скорости Docker Hub. Образы из других реестров загружаются напрямую.

Каждое задание начинается с пустого хранилища образов, поэтому образ, используемый вашим workflow, загружается один раз для каждого задания, а не используется повторно между заданиями. Если задание загружает большой пользовательский образ, сделайте образ небольшим или соберите его в workflow с использованием кэшированного сборщика Buildx:

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

Для постоянных директорий зависимостей в нативных заданиях или заданиях в контейнерах см. <.localized_link href="/guides/features/runners/cache-volumes">руководство по томам кэша</.localized_link>.
