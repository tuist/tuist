---
{
  "title": "Cobertura de código en Xcode",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Sube la cobertura de código de proyectos de Xcode a Tuist y consúltala por archivo y por commit."
}
---
# Cobertura de código en Xcode {#xcode-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. Tuist sube la cobertura por línea de cada ejecución de tests y consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada target y cada archivo. La página **Cobertura de código** del panel la muestra por commit y como tendencia para cada rama.

> [!TIP]
> Si generas tu proyecto con Tuist, sigue la <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">guía de proyectos generados</.localized_link>: mide el código que proviene de la caché binaria y mantiene la cobertura de los targets de test que los tests selectivos omiten.

## Configuración {#setup}

### Recopilar cobertura {#collect-coverage}

Activa la subida de cobertura en tu `Tuist.swift`. Está desactivada por defecto:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

La variable de entorno `TUIST_COVERAGE_UPLOAD` (`1` o `0`) tiene prioridad sobre la opción, por ejemplo para desactivar la subida en trabajos que ejecutan pull requests desde forks.

Luego activa **Cobertura de código** en la acción de test de tu esquema (**Editar esquema › Test › Opciones**), o pasa `-enableCodeCoverage YES` a la ejecución, y ejecuta tus tests mediante `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist sube la cobertura recopilada por la ejecución junto con sus resultados de test.

### Completar cada commit en CI {#complete-each-commit}

La cobertura de un commit suele provenir de varios trabajos: uno por esquema, por fragmento o por plataforma. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Una vez que haya terminado cada trabajo de test de un commit, ejecuta esto en un trabajo que dependa de todos ellos:

```sh
tuist coverage complete
```

Hasta que un commit esté completo, su cobertura se muestra como **En progreso** y queda fuera de la tendencia de su rama. La <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">guía de proyectos generados</.localized_link> describe cada estado.

## Tests omitidos {#skipped-tests}

Cuando una ejecución omite tests con `-skip-testing`, mide menos de lo que cubren los tests del commit, y Tuist no puede arrastrar esos tests desde una ejecución anterior. La cobertura del commit es **Incompleta**, a menos que otra ejecución en el commit los haya ejecutado. Para mantener un commit completo, ejecuta cada test en al menos una ejecución por commit.

Los tests que la cuarentena omite no forman parte de la cobertura en absoluto, por lo que nunca hacen que un commit sea **Incompleto**.

## Impacto en el rendimiento {#performance-impact}

Recopilar cobertura añade sobrecarga, principalmente después de que finalicen los tests, mientras Xcode escribe su informe de cobertura y Tuist exporta la cobertura. Compilar y ejecutar los tests lleva aproximadamente el mismo tiempo que sin ella.

## Consultar cobertura {#querying}

Los comandos `tuist coverage` leen lo que muestra el panel. Sin `--commit`, leen el último commit completo de `--branch`, o de tu rama predeterminada:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

Todos aceptan `--json` para scripting.
