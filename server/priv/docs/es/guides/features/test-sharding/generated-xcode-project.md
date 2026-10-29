---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Test sharding · Features · Guides · Tuist",
  "description": "Distribute tests in a Tuist-generated Xcode project across multiple CI runners with Tuist Test Sharding."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-test-sharding}

La fragmentación de tests para proyectos generados utiliza `tuist test` tanto para las fases de compilación como de test.

## Cómo funciona {#how-it-works}

La fragmentación de tests sigue un flujo de trabajo de dos fases:

1. **Fase de compilación:** Tuist lee los módulos de test desde el archivo `.xctestrun` compilado y crea un **plan de fragmentos** en el servidor. El servidor utiliza datos históricos de tiempos de ejecución de tests de los últimos 30 días para distribuir los tests entre los fragmentos, de modo que cada fragmento tarde aproximadamente la misma cantidad de tiempo. La fase de compilación genera una **matriz de fragmentos** que tu sistema de CI utiliza para lanzar ejecutores en paralelo.
2. **Fase de test:** Cada ejecutor de integración continua recibe un **índice de fragmento** y el **identificador exacto del plan de fragmentos**, y luego ejecuta la selección de tests de ese plan.

Cuando se usa `--shard-granularity suite`, Tuist no inicia todos los bundles de test para enumerar las suites durante la fase de compilación. En su lugar, el archivo `.xctestrun` actual proporciona la lista de módulos, y el servidor elige las suites conocidas por módulo: para cada módulo, une las suites de las últimas ejecuciones de CI en la rama que se está compilando. Si un módulo no tiene historial en esa rama, el servidor recurre a la rama predeterminada del proyecto. Leer varias ejecuciones en lugar de solo la más reciente es importante porque una ejecución fragmentada sube una ejecución de test por fragmento a medida que cada fragmento finaliza, por lo que la ejecución más reciente contiene solo la fracción del módulo que se ha procesado hasta el momento, y porque evita que las ejecuciones de testing selectivo oculten suites que se omitieron en la última ejecución de la rama. El servidor sigue utilizando los tiempos de ejecución de suites de los últimos 30 días para estimar las duraciones.

Tuist equilibra esas suites conocidas entre la cantidad de fragmentos solicitada y utiliza el último fragmento como comodín. Por ejemplo, `--shard-total 5` produce índices de fragmento `0` hasta `4`, siendo el índice de fragmento `4` el comodín. Los fragmentos regulares se ejecutan con `-only-testing` para sus suites asignadas. El último fragmento se ejecuta sin `-only-testing` y pasa `-skip-testing` para cada suite asignada a los fragmentos anteriores, por lo que también ejecuta suites recién añadidas, suites renombradas o suites que faltan en el inventario histórico. La granularidad por módulo no necesita un comodín porque el archivo `.xctestrun` proporciona la lista de módulos.

## Fase de compilación {#build-phase}

Genera tu proyecto, compila tus tests y crea un plan de fragmentos:

```sh
tuist test --build-only --shard-total 5
```

La bandera `--build-only` indica a Tuist que compile los tests sin ejecutarlos. Tuist muestra un error si pasas banderas de planificación de fragmentos (`--shard-min`/`--shard-max`/`--shard-total`) sin `--build-only`.

Este comando:
1. Genera el proyecto de Xcode a partir de tus manifiestos
2. Compila tus tests
3. Crea un plan de fragmentos en el servidor de Tuist utilizando datos históricos de tiempos de ejecución
4. Sube el bundle `.xctestproducts` o escribe un archivo de fragmentos para su uso por los ejecutores de fragmentos
5. Genera una matriz de fragmentos para tu sistema de CI
6. Persiste el grafo de <.localized_link href="/guides/features/selective-testing">pruebas selectivas</.localized_link> (si corresponde) para que los ejecutores de fragmentos no necesiten regenerar el proyecto

### Opciones de compilación {#build-options}

| Bandera | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Número máximo de fragmentos. Se usa con `--shard-max-duration` para limitar la cantidad de fragmentos |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Número mínimo de fragmentos |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Número exacto de fragmentos (excluyente con `--shard-min`/`--shard-max`). Con granularidad de suite, el último fragmento es el comodín |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Duración máxima objetivo por fragmento en milisegundos |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (predeterminado) distribuye módulos de test completos entre los fragmentos; `suite` distribuye clases de test individuales para un equilibrio más fino |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Identificador único para el plan de fragmentos (derivado automáticamente en proveedores de CI compatibles) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Ruta donde Tuist escribe el archivo de fragmentos optimizado en lugar de subir los productos de test al almacenamiento remoto |

## Fase de test {#test-phase}

Cada ejecutor de fragmento ejecuta sus tests asignados:

```sh
tuist test --without-building
```

La bandera `--without-building` indica a Tuist que ejecute los tests utilizando los productos compilados previamente en lugar de recompilar. Tuist muestra un error si `TUIST_SHARD_INDEX` / `--shard-index` está configurado sin `--without-building`.

### Opciones de test {#test-options}

| Bandera | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Índice basado en cero del fragmento a ejecutar |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Identificador exacto del plan de fragmentos emitido por la fase de compilación. Las salidas generadas por el proveedor incluyen este valor automáticamente |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Identificador único para el plan de fragmentos (derivado automáticamente en proveedores de CI compatibles) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Ruta a un archivo de fragmentos gestionado localmente; Tuist lo extrae en lugar de descargar los productos de test desde el almacenamiento remoto |

Tuist descarga el bundle `.xctestproducts` y lo filtra para incluir solo los tests asignados a ese fragmento.

> [!TIP]
> **Pruebas selectivas**
>
> La fragmentación de tests funciona perfectamente con las <.localized_link href="/guides/features/selective-testing">pruebas selectivas</.localized_link>. El grafo de pruebas selectivas se persiste durante la fase de compilación y se restaura para cada fragmento, por lo que los ejecutores no necesitan regenerar el proyecto.

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
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuist genera un `.tuist-shard-child-pipeline.yml` que activas como una [tubería secundaria](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Define un trabajo de plantilla `.tuist-shard` que extiendan los trabajos de fragmentos generados:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --build-only --shard-total 5
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

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --without-building
```

### CircleCI {#circleci}

Tuist genera un `.tuist-shard-continuation.json` con parámetros para el [orb de continuación](https://circleci.com/developer/orbs/orb/circleci/continuation). El parámetro `shard-plan-id` debe declararse en tu configuración de continuación:

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    macos:
      xcode: "16.0"
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            tuist test --build-only --shard-total 5
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
  shard-plan-id:
    type: string
    default: ""

jobs:
  test-shard:
    macos:
      xcode: "16.0"
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            export TUIST_SHARD_PLAN_ID=<< pipeline.parameters.shard-plan-id >>
            tuist auth login
            tuist test --without-building

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
      tuist test --build-only --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

Cada paso generado tiene `TUIST_SHARD_INDEX` y `TUIST_SHARD_PLAN_ID` configurados en su entorno. Añade el comando de test a cada paso de fragmento utilizando un script compartido:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic no admite trabajos de matriz dinámicos, así que define un flujo de trabajo separado por fragmento. Tuist escribe `TUIST_SHARD_MATRIX` y `TUIST_SHARD_COUNT` en el archivo `CM_ENV` para su uso dentro del flujo de trabajo de compilación. El `CM_ENV` de Codemagic está limitado al flujo de trabajo, por lo que el identificador exacto del plan de fragmentos no cruza los límites del flujo de trabajo; los flujos de trabajo de test recurren a la búsqueda de fragmentos basada en referencias:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: mac_mini_m2
    environment:
      xcode: latest
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          tuist test --build-only --shard-total 5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: mac_mini_m2
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          tuist test --without-building

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

En Bitrise, Tuist escribe `.tuist-shard-matrix.json` (incluyendo `shard_plan_id`) en el `BITRISE_DEPLOY_DIR`, haciéndolo disponible como artefacto de compilación para las etapas posteriores de la tubería. Cada flujo de trabajo de test extrae el ID del plan del artefacto descargado utilizando `envman` para que llegue al entorno del comando de test:

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
                tuist test --build-only --shard-total 5
      - deploy-to-bitrise-io: {}

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - pull-intermediate-files: {}
      - script:
          title: Set shard plan ID from artifact
          inputs:
            - content: |
                PLAN_ID=$(jq -r '.shard_plan_id' "$BITRISE_DEPLOY_DIR/.tuist-shard-matrix.json")
                envman add --key TUIST_SHARD_PLAN_ID --value "$PLAN_ID"
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist test --without-building
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
> Bitrise no admite la creación dinámica de trabajos paralelos en tiempo de ejecución. Define un número fijo de flujos de trabajo de fragmentos en tus etapas de la tubería; los flujos de trabajo dentro de una etapa se ejecutan en paralelo automáticamente.

## Volúmenes compartidos {#shared-volumes}

De forma predeterminada, la fase de compilación sube el bundle `.xctestproducts` al almacenamiento remoto y cada ejecutor de fragmentos lo descarga. Si tu proveedor de CI admite **volúmenes compartidos** (almacenamiento persistente montado entre trabajos), puedes omitir por completo esta subida/descarga pasando los productos de test a través de un sistema de archivos compartido.

Esto puede reducir significativamente el tiempo de inicio de los fragmentos, especialmente para bundles de test grandes.

Para usar volúmenes compartidos:

1. En la **fase de compilación**, pasa `-testProductsPath` (después de `--`) apuntando a un volumen compartido y añade `--shard-skip-upload` para omitir la subida remota:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. En la **fase de test**, pasa el mismo `-testProductsPath` para que Tuist lea los productos de test localmente en lugar de descargarlos:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| Bandera | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Omitir la subida del bundle de productos de test al almacenamiento remoto |

## Artefactos autogestionados {#self-managed-artifacts}

Si tu proveedor de CI ya tiene pasos de subida y descarga de artefactos, puedes dejar que Tuist gestione el archivo y la extracción mientras tu CI gestiona el transporte.

1. En la **fase de compilación**, pasa `--shard-archive-path` para que Tuist escriba su archivo de fragmentos optimizado localmente en lugar de subir los productos de test:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Sube ese archivo utilizando el paso nativo de artefactos de tu CI.

3. En cada trabajo de la **fase de test**, descarga el archivo y pasa la misma ruta de vuelta a Tuist:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

Cuando se establece `--shard-archive-path`, Tuist omite la transferencia remota de productos de test y utiliza el archivo local en su lugar. Si también pasas `--shard-skip-upload`, la ruta del archivo tiene prioridad.

Cuando no hay tests que ejecutar, por ejemplo porque las pruebas selectivas omitieron todos los destinos de test, la fase de compilación genera una matriz de fragmentos vacía y no escribe ningún archivo. Ejecuta el paso de subida solo cuando la matriz tenga fragmentos.

> [!IMPORTANT]
> Usa una ruta única por ejecución de flujo de trabajo (por ejemplo, incluye el ID de ejecución de CI) para evitar colisiones entre ejecuciones concurrentes. También debes limpiar el archivo de fragmentos después de completar la fragmentación para evitar acumular datos obsoletos en el ejecutor.

### Namespace {#namespace}

Los ejecutores de [Namespace](https://namespace.so) funcionan bien con los artefactos de GitHub Actions. Establece `TUIST_TEST_SHARD_ARCHIVE_PATH` una vez para que el trabajo de compilación escriba el archivo de fragmentos localmente, súbelo y descárgalo en cada trabajo de fragmento antes de ejecutar `tuist test`:

```yaml
name: Tests
on: [pull_request]

env:
  TUIST_TEST_SHARD_ARCHIVE_PATH: /tmp/shards/${{ github.run_id }}/bundle.aar

jobs:
  build:
    name: Build test shards
    runs-on: namespace-profile-default-macos
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5
      - if: toJSON(fromJSON(steps.build.outputs.matrix).shard) != '[]'
        uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: namespace-profile-default-macos
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
