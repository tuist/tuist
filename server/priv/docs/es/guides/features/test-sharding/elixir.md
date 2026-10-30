---
{
  "title": "Sharding de tests en Elixir",
  "titleTemplate": ":title · Sharding de tests · Funcionalidades · Guías · Tuist",
  "description": "Distribuye los tests de tu proyecto Elixir entre varios runners de CI con el sharding de tests de Tuist."
}
---
# Fragmentación de tests en Elixir {#elixir-test-sharding}

El paquete Hex de Tuist incluye soporte integrado para fragmentar los tests de un proyecto Elixir. Utiliza el servidor de Tuist para crear planes de fragmentación equilibrados basados en datos históricos de tiempos de ejecución, y compila tu proyecto una sola vez para que cada runner pueda pasar directamente a ejecutar los tests.

> [!IMPORTANT] REQUIREMENTS
> - Completa la <.localized_link href="/guides/get-started/elixir-project">configuración compartida de Elixir</.localized_link> antes de configurar tus jobs de fragmentación en CI

## Cómo funciona {#how-it-works}

La fragmentación de tests sigue un flujo de trabajo de dos fases:

1. **Fase de compilación:** Tuist compila tu proyecto para tests, enumera tus archivos de test y crea un **plan de fragmentación** en el servidor. El servidor utiliza datos históricos de tiempos de ejecución de los últimos 30 días para distribuir los tests entre las fragmentaciones de modo que cada una tarde aproximadamente lo mismo. La fase de compilación sube la build y genera una **matriz de fragmentación** que tu sistema de CI utiliza para lanzar runners en paralelo.
2. **Fase de tests:** Cada runner de CI recibe un **índice de fragmentación**, descarga la build y ejecuta únicamente los tests asignados a esa fragmentación.

Las subidas de builds envían hasta cuatro partes simultáneamente e intentan hasta tres veces en caso de fallos transitorios en alguna parte. En los runners Linux de Tuist inscritos, las builds de fragmentación pueden usar almacenamiento local de artefactos. Todas las fragmentaciones que consuman dicha build deben ejecutarse en runners inscritos en el mismo sitio; vuelve a ejecutar la build con el almacenamiento local desactivado al mover el flujo de trabajo a otros runners.

Los tests se distribuyen por archivo: todos los tests de un archivo se ejecutan en la misma fragmentación. Los tests que Tuist aún no ha visto reciben una estimación, por lo que los primeros planes de un proyecto están menos equilibrados que los posteriores.

## Fase de compilación {#build-phase}

Prepara las fragmentaciones de test utilizando la tarea `tuist.test.build`:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

Compila a través del alias instalado por la configuración compartida antes de invocar la tarea de fragmentación. En un checkout limpio, Mix puede compilar dependencias mientras descubre `tuist.test.build`, antes de que la caché de dependencias de Tuist tenga oportunidad de restaurarlas. La compilación explícita se ejecuta en el mismo entorno de test que la tarea de fragmentación.

Esta tarea:
1. Compila el proyecto en el entorno de test
2. Crea un plan de fragmentación en el servidor de Tuist usando datos históricos de tiempos
3. Sube la build para que las fragmentaciones no vuelvan a compilar
4. Genera una matriz de fragmentación para tu sistema de CI

### Opciones de build {#build-options}

| Opción | Descripción |
|--------|-------------|
| `--shard-max <N>` | Número máximo de fragmentaciones (predeterminado: 2) |
| `--shard-min <N>` | Número mínimo de fragmentaciones |
| `--shard-total <N>` | Número exacto de fragmentaciones, en lugar de un rango |
| `--shard-max-duration <MS>` | Duración máxima objetivo por fragmentación en milisegundos |
| `--shard-reference <REF>` | Nombre con el que las fragmentaciones encuentran el plan |
| `--no-upload` | Planifica las fragmentaciones sin subir la build; cada fragmentación compila por su cuenta |

Cualquier otro argumento se reenvía a `mix compile`.

La referencia de fragmentación se deriva automáticamente de las variables de entorno de CI (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, `CIRCLE_WORKFLOW_ID`, `BUILDKITE_BUILD_ID`) o puede establecerse explícitamente mediante la variable de entorno `TUIST_SHARD_REFERENCE`. Fuera de esos proveedores debes establecerla con un valor que compartan la fase de compilación y las fragmentaciones de una misma ejecución de pipeline. En GitHub Actions, las referencias también incluyen el intento de ejecución: al volver a ejecutar solo los jobs fallidos, pasa la referencia del job de build original en lugar de derivar una nueva en los jobs de fragmentación.

## Fase de tests {#test-phase}

Cuando `TUIST_SHARD_INDEX` está definida, el paquete obtiene la asignación de fragmentación desde el servidor, descarga la build y ejecuta únicamente los archivos de test asignados sin compilar. En un runner limpio, inicializa el SDK y carga sus rutas antes de invocar la tarea:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

Compilar el SDK en los procesos worker de Mix no lo carga en el proceso padre. El paso explícito `deps.loadpaths` evita que la descubierta de tareas compile las dependencias restantes antes de descargar la build. Esta forma de comando único preserva el alias de preparación de tests de tu proyecto. Si sus comandos de configuración desencadenan la compilación, usa la secuencia de configuración separada que aparece más abajo.

Cualquier archivo o directorio de test que pases reduce aún más la fragmentación: solo se ejecutan los archivos que están tanto en la fragmentación como en tu selección. Una fragmentación que queda sin tests finaliza con éxito.

Los resultados de todas las fragmentaciones llegan al dashboard como una única ejecución de tests, y su sección **Fragmentaciones** muestra cuánto tardó cada una.

Si la configuración debe ejecutarse antes de los tests, descarga primero la build sin iniciar la aplicación:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

Ejecuta tu configuración en un proceso separado con la compilación desactivada. Por ejemplo, un proyecto Ecto puede crear y migrar sus bases de datos usando:

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

Mantén cualquier otra preparación específica del proyecto en esta fase. Tu alias de compilación también debe respetar `--no-compile` antes de realizar el trabajo de inicialización: Mix solo reenvía flags a la última tarea de un alias de lista, por lo que un `deps.compile` incondicional anterior sigue ejecutándose. Consulta el alias protegido en <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">integración manual de compilación</.localized_link>.

Luego carga el SDK restaurado sin compilación antes de ejecutar la fragmentación. Esto también evita que la descubierta de tareas compile una dependencia de ruta cuando sus fuentes son más recientes que la build descargada:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

Ambos comandos necesitan la misma referencia de fragmentación. `--prepare-only` requiere una build subida, y `--no-download` falla si falta el artefacto de aplicación preparado. `--no-download` omite explícitamente el alias de preparación de tests de tu proyecto, incluso en reintentos, e imprime un aviso cuando omite pasos de configuración. Las ejecuciones normales mantienen sus aliases, incluso cuando reenvías `--no-compile --no-deps-check`. Mantener las migraciones de base de datos en un proceso separado también evita advertencias de redefinición de módulos cuando los tests de regresión de migraciones cargan esos módulos por sí mismos.

Al probar diferentes entornos, pasa una etiqueta `--scheme` estable, como `--scheme clickhouse-current` o `--scheme clickhouse-floor`. Los resultados con etiquetas diferentes no se tratan como reejecuciones inestables de la misma configuración.

### Qué necesitan las fragmentaciones {#what-the-shards-need}

La build subida es el directorio `_build/test`. Cada runner de fragmentación aún necesita:
- El mismo checkout que la fase de build
- Las mismas versiones de Elixir y Erlang/OTP
- Las fuentes de las dependencias, obtenidas con `mix deps.get`

La fragmentación desde la raíz de un proyecto umbrella aún no está soportada. Ejecuta ambas fases dentro de una de sus aplicaciones.

## Integración continua {#continuous-integration}

### GitHub Actions {#github-actions}

En GitHub Actions, la fase de build escribe los índices de fragmentación en la salida `matrix` de su paso. Usa una estrategia de matriz para ejecutar las fragmentaciones en paralelo:

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

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
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### Otros proveedores {#other-providers}

Fuera de GitHub Actions, la fase de build escribe el plan en `.tuist-shard-matrix.json`:

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

Usa `shard_count` para configurar tus trabajos paralelos y asigna a cada trabajo su `TUIST_SHARD_INDEX`, desde `0` hasta `shard_count - 1`. En un proveedor del que Tuist no deriva la referencia, asigna también a cada trabajo el mismo `TUIST_SHARD_REFERENCE`.
