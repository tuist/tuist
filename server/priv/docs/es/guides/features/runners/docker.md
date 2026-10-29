---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Los runners de Linux vienen con Docker listo para usar. Cada trabajo obtiene su propio daemon de Docker dentro de la máquina virtual del trabajo, y la CLI de `docker`, Buildx y Compose están preinstalados. No necesitas una acción de configuración ni `sudo`.

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
> **Solo Linux**
>
> Los runners de macOS no proporcionan un daemon de Docker. Usa un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Linux para los trabajos que lo necesiten.

## Ejecutar un trabajo en un contenedor {#running-a-job-in-a-container}

Apunta `container` a la imagen en la que debe ejecutarse tu trabajo. Tuist la extrae y ejecuta cada paso dentro de ella:

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

## Contenedores de servicio {#service-containers}

`services` funciona de la misma manera que en los runners alojados en GitHub. Los servicios son accesibles en `localhost` en sus puertos asignados:

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

## Registros privados {#private-registries}

Autentícate con la acción de inicio de sesión propia del registro o con `docker login` antes de extraer o enviar imágenes:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

Para un `container` a nivel de trabajo, pasa las mismas credenciales a través de la clave `credentials`, como en el ejemplo anterior.

## Extracción de imágenes {#image-pulls}

Las extracciones de Docker Hub se sirven a través de una caché pull-through operada por Tuist, por lo que los trabajos no consumen el límite de tasa anónimo de Docker Hub. Las imágenes de otros registros se extraen directamente.

Cada trabajo comienza con un almacén de imágenes vacío, por lo que una imagen que usa tu flujo de trabajo se extrae una vez por trabajo en lugar de reutilizarse entre trabajos. Si un trabajo extrae una imagen personalizada grande, mantén la imagen pequeña o constrúyela en el flujo de trabajo con un builder de Buildx en caché:

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

Para directorios de dependencias persistentes en trabajos nativos o en contenedores, consulta la <.localized_link href="/guides/features/runners/cache-volumes">guía de volúmenes de caché</.localized_link>.
