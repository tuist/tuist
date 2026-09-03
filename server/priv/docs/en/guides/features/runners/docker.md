---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux runners come with Docker ready to use. Each job gets its own Docker daemon inside the job's virtual machine, and the `docker` CLI, Buildx, and Compose are preinstalled. You don't need a setup action, and you don't need `sudo`.

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
> **Linux only**
>
> macOS runners don't provide a Docker daemon. Use a Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> for jobs that need one.

## Running a job in a container {#running-a-job-in-a-container}

Point `container` at the image your job should run in. Tuist pulls it and runs every step inside it:

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

## Service containers {#service-containers}

`services` works the same way it does on GitHub-hosted runners. Services are reachable on `localhost` at their mapped ports:

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

## Private registries {#private-registries}

Authenticate with the registry's own login action, or `docker login`, before pulling or pushing:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

For a job-level `container`, pass the same credentials through the `credentials` key instead, as in the example above.

## Image pulls {#image-pulls}

Docker Hub pulls are served through a pull-through cache that Tuist operates, so jobs don't consume Docker Hub's anonymous rate limit. Images from other registries are pulled directly.

Every job starts with an empty image store, so an image your workflow uses is pulled once per job rather than reused across jobs. If a job pulls a large custom image, keep the image small, or build it in the workflow with a cached Buildx builder:

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
