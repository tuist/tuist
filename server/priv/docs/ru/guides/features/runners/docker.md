---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Возможности · Руководства · Tuist",
  "description": "Используйте Docker на раннерах Tuist: собирайте и запускайте контейнеры, контейнерные задачи, сервисные контейнеры и работайте с приватными реестрами."
}
---
# Docker {#docker}

Linux-раннеры поставляются с готовым к использованию Docker. Каждое задание получает собственный демон Docker внутри виртуальной машины задания, а CLI `docker`, Buildx и Compose предустановлены. Вам не нужны действия для настройки, и вам не нужен `sudo`.

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
> macOS-раннеры не предоставляют демон Docker. Используйте Linux-<.localized_link href="/guides/features/runners/profiles">профиль</.localized_link> для заданий, которым он требуется.

## Запуск задания в контейнере {#running-a-job-in-a-container}

Укажите в `container` образ, в котором должно выполняться ваше задание. Tuist загружает его и выполняет каждый шаг внутри него:

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

`services` работает так же, как на раннерах, размещенных в GitHub. Сервисы доступны на `localhost` по их сопоставленным портам:

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

## Частные реестры {#private-registries}

Выполните аутентификацию с помощью собственного действия входа в реестр или `docker login` перед извлечением или отправкой образов:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

Для `container` на уровне задания передайте те же учетные данные через ключ `credentials`, как показано в примере выше.

## Извлечение образов {#image-pulls}

Запросы к Docker Hub обслуживаются через сквозной кэш, управляемый Tuist, поэтому задания не расходуют анонимный лимит скорости Docker Hub. Образы из других реестров извлекаются напрямую.

Каждое задание начинается с пустого хранилища образов, поэтому образ, используемый вашим workflow, извлекается один раз за задание, а не используется совместно между заданиями. Если задание извлекает большой пользовательский образ, сделайте образ небольшим или соберите его в workflow с помощью кэшированного сборщика Buildx:

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

Информацию о постоянных директориях зависимостей в нативных заданиях или заданиях в контейнерах см. в <.localized_link href="/guides/features/runners/cache-volumes">руководстве по томам кэша</.localized_link>.
