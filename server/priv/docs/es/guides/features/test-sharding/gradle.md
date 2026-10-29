---
{
  "title": "Gradle Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Gradle tests across multiple CI runners with Tuist Test Sharding."
}
---
# Fragmentación de tests de Gradle {#gradle-test-sharding}

El plugin de Tuist para Gradle incluye soporte integrado para la fragmentación de tests. Planifica las suites de tests que Tuist registró en ejecuciones anteriores de CI de las tareas de test de tus proyectos y utiliza el servidor de Tuist para crear planes de fragmentos equilibrados basados en datos históricos de tiempos.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">Test insights</.localized_link> debe estar configurado

## Cómo funciona {#how-it-works}

La fragmentación de tests sigue un flujo de trabajo de dos fases:

1. **Fase de compilación:** Tuist crea un **plan de fragmentos** en el servidor a partir de las suites de tests registradas para tus proyectos. El servidor utiliza datos históricos de tiempos de los últimos 30 días para distribuir los tests entre los fragmentos, de modo que cada fragmento tarde aproximadamente la misma cantidad de tiempo. La fase de compilación genera una **matriz de fragmentos** que tu sistema de CI utiliza para lanzar ejecutores en paralelo.
2. **Fase de test:** Cada ejecutor de CI recibe un **índice de fragmento** y ejecuta únicamente los tests asignados a ese fragmento. El último fragmento también ejecuta todas las suites de tests que no estén asignadas a otro fragmento.

## Fase de compilación {#build-phase}

Prepara los fragmentos de test utilizando la tarea `tuistPrepareTestShards`:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

Esta tarea:
1. Encuentra los proyectos que tienen la tarea de test a fragmentar, sin compilarlos
2. Crea un plan de fragmentos en el servidor de Tuist a partir de las suites de tests y los tiempos registrados para esos proyectos en los últimos 30 días
3. Genera una matriz de fragmentos para tu sistema de CI

Cuando aún no hay suites de tests registradas, por ejemplo en la primera ejecución, el plan tiene un único fragmento que ejecuta todos los tests.

### Opciones de compilación {#build-options}

Configura la fragmentación mediante propiedades del proyecto Gradle:

| Propiedad | Descripción |
|----------|-------------|
| `-PtuistShardMax=<N>` | Número máximo de fragmentos (predeterminado: 2) |
| `-PtuistShardMin=<N>` | Número mínimo de fragmentos |
| `-PtuistShardMaxDuration=<MS>` | Duración máxima objetivo por fragmento en milisegundos |
| `-PtuistShardTestTask=<NAME>` | Tarea de test cuyos tests se fragmentan, por ejemplo `testDebugUnitTest`. Por defecto, todas las tareas de test de la compilación |

Los proyectos Android con múltiples variantes de compilación tienen una tarea de test unitario por variante. Establece `-PtuistShardTestTask` a la variante que ejecutan tus fragmentos para que solo se planifiquen los proyectos que la tengan:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

La referencia del fragmento se deriva automáticamente de las variables de entorno de CI (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, etc.) o se puede establecer explícitamente mediante la variable de entorno `TUIST_SHARD_REFERENCE`.

## Fase de test {#test-phase}

Cada ejecutor de fragmento ejecuta sus tests asignados utilizando la tarea estándar `test`. Cuando `TUIST_SHARD_INDEX` está establecida, el plugin obtiene automáticamente la asignación de fragmentos del servidor y filtra la ejecución de tests para incluir solo las suites de tests asignadas. Las tareas de test en proyectos sin suites asignadas al fragmento se omiten.

El último fragmento ejecuta todas las tareas de test y excluye las suites asignadas a los otros fragmentos, por lo que las suites que aún no tienen ejecuciones registradas, como las recién añadidas, siguen ejecutándose.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

Si estableces `-PtuistShardTestTask` en la fase de compilación, ejecuta esa misma tarea en cada fragmento, por ejemplo `./gradlew testDebugUnitTest`.

## Integración continua {#continuous-integration}

Tuist detecta automáticamente los siguientes proveedores de CI:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

Para otros proveedores, consulta el archivo `.tuist-shard-matrix.json` para configurar trabajos paralelos.

### GitHub Actions {#github-actions}

Utiliza una estrategia de matriz para ejecutar fragmentos en paralelo:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - id: build
        run: ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist genera un `.tuist-shard-child-pipeline.yml` que activas como una [pipeline secundaria](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Define un trabajo de plantilla `.tuist-shard` que los trabajos de fragmento generados extienden:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
    - tuist auth login
    - ./gradlew tuistPrepareTestShards -PtuistShardMax=5
  artifacts:
    paths:
      - .tuist-shard-child-pipeline.yml

test-shards:
  stage: test
  needs: [build-shards]
  trigger:
    include:
      - artifact: .tuist-shard-child-pipeline.yml
        job: build-shards
    strategy: depend
```

La pipeline secundaria necesita una plantilla de trabajo `.tuist-shard`:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist genera un `.tuist-shard-continuation.json` con parámetros para el [orb de continuación](https://circleci.com/developer/orbs/orb/circleci/continuation):

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    docker:
      - image: cimg/openjdk:17.0
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: .tuist-shard-continuation.json

workflows:
  setup:
    jobs:
      - build-shards
```

```yaml
# .circleci/continue-config.yml
version: 2.1

parameters:
  shard-indices:
    type: string
    default: ""
  shard-count:
    type: integer
    default: 0

jobs:
  test-shard:
    docker:
      - image: cimg/openjdk:17.0
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            tuist auth login
            ./gradlew test

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist genera un `.tuist-shard-pipeline.yml` con un paso por fragmento. Súbelo con `buildkite-agent pipeline upload`:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

Cada paso generado tiene `TUIST_SHARD_INDEX` establecido en su entorno. Añade el comando de test a cada paso de fragmento utilizando un script compartido:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic no admite trabajos de matriz dinámicos, así que define un flujo de trabajo separado por fragmento. Tuist escribe `TUIST_SHARD_MATRIX` y `TUIST_SHARD_COUNT` en el archivo `CM_ENV` para su uso dentro de cada flujo de trabajo:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: linux_x2
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          ./gradlew test

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

En Bitrise, Tuist escribe `.tuist-shard-matrix.json` en el `BITRISE_DEPLOY_DIR`, haciéndolo disponible como artefacto de compilación para las etapas posteriores de la pipeline. Utiliza Bitrise Pipelines con flujos de trabajo paralelos predefinidos:

```yaml
# bitrise.yml
pipelines:
  test-pipeline:
    stages:
      - build-stage: {}
      - test-stage: {}

stages:
  build-stage:
    workflows:
      - build-shards: {}
  test-stage:
    workflows:
      - test-shard-0: {}
      - test-shard-1: {}
      - test-shard-2: {}
      - test-shard-3: {}
      - test-shard-4: {}

workflows:
  build-shards:
    steps:
      - script:
          title: Build and plan shards
          inputs:
            - content: |
                tuist auth login
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                ./gradlew test
  test-shard-1:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 1
  test-shard-2:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 2
  test-shard-3:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 3
  test-shard-4:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 4
```

> [!TIP]
> Bitrise no admite la creación dinámica de trabajos paralelos en tiempo de ejecución. Define un número fijo de flujos de trabajo de fragmentos en tus etapas de pipeline; los flujos de trabajo dentro de una etapa se ejecutan en paralelo automáticamente.
