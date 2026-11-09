---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests selectivos · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests de Xcode y del proyecto generado afectados por tus últimos cambios con Tuist Selective Testing, para que la integración continua reciba feedback en segundos."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

A medida que un proyecto crece, ejecutar todos los tests en cada push deja de ser escalable. Los tests selectivos de Tuist ejecutan solo los tests cuyos targets han cambiado desde la última ejecución exitosa, basándose en el <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link> de Tuist.

Para ejecutar tests de forma selectiva con tu <.localized_link href="/guides/features/projects">proyecto generado</.localized_link>, usa el comando `tuist test`. El comando <.localized_link href="/guides/features/projects/hashing">genera hashes</.localized_link> de tu proyecto de la misma manera que lo hace para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y, si tiene éxito, persiste los hashes para determinar qué ha cambiado en futuras ejecuciones. En ejecuciones posteriores, `tuist test` utiliza los hashes de forma transparente para filtrar los tests y ejecutar solo aquellos que han cambiado desde la última ejecución exitosa.

`tuist test` se integra directamente con la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> para utilizar tantos binarios como sea posible desde tu almacenamiento local o remoto, mejorando así el tiempo de compilación al ejecutar tu suite de tests. La combinación de tests selectivos con la caché de módulos puede reducir drásticamente el tiempo necesario para ejecutar tests en tu CI.

Si tus tests solo tienen como destino simuladores, pasa `--destination simulator` para que `tuist test` utilice y descargue únicamente las slices de simulador de los binarios en caché. Consulta la <.localized_link href="/guides/features/cache/module-cache#destination-selection">selección de destino</.localized_link>. Los hashes de los tests selectivos son los mismos para cada valor de `--destination`.

## Separar jobs de compilación y test {#separate-build-and-test-jobs}

Los tests selectivos admiten jobs de compilación y test separados. Ejecuta `tuist test --build-only` en el job de compilación para que Tuist pueda persistir un archivo `selective-testing-graph.json` junto con los productos que genera la compilación. Ese grafo contiene los hashes que necesitan los tests selectivos, por lo que el job de test no tiene que regenerar el proyecto ni resolver las dependencias de Swift Package para averiguar qué targets ejecutar.

Tuist escribe el grafo en dos lugares durante `--build-only`:

- Dentro del bundle `.xctestproducts` cuando pasas `-testProductsPath`.
- Junto a cada archivo `.xctestrun` bajo el directorio `Build/Products/` de los datos derivados.

Almacena en caché cualquiera de estas salidas junto con los productos compilados y proporciona la misma ruta a `--without-building` en el job de test. Ambas formas funcionan:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Cuando Tuist no puede encontrar ese grafo junto a la entrada (por ejemplo, cuando el job de compilación usó simplemente `xcodebuild build-for-testing` en lugar de `tuist test --build-only`), recurre a regenerar el proyecto para poder seguir calculando los targets afectados. Esa alternativa necesita que las dependencias de Swift Package estén resueltas en el job de test, así que ejecuta primero `tuist install` o almacena en caché `Tuist/.build` entre jobs.

El grafo refleja el árbol de fuentes tal como estaba en el momento de la compilación. Ejecuta el job de test contra el mismo commit que el job de compilación; si las fuentes divergen entre ambos, los hashes ya no coinciden con las fuentes y los tests selectivos pueden omitir tests que realmente fallarían contra las fuentes más recientes.

### ¿Qué flag debo usar? {#which-flag-should-i-use}

`.xctestrun` y `.xctestproducts` son dos formatos de salida de Xcode diferentes, y equilibran la portabilidad con la conveniencia del pipeline:

- **`-testProductsPath` (`.xctestproducts`) — recomendado para nuevos pipelines.** Es un directorio autocontenido: los binarios `.xctest` compilados y sus archivos `.xctestrun` viven dentro de él con rutas relativas a la raíz del bundle, por lo que sigue siendo válido dondequiera que termine.
- **`-xctestrun` (raw `.xctestrun`) — úsalo si ya tienes un pipeline construido alrededor de los datos derivados.** `xcodebuild build-for-testing` escribe un `.xctestrun` en la parte superior de `<derivedData>/Build/Products/` por defecto y lo apunta a los bundles de test que residen en otra parte de ese árbol. Reutilizarlo en otro job significa mantener intactas las rutas en `Build/Products/`.

Si estás empezando desde cero, prefiere `-testProductsPath`. Si estás integrando Tuist en un pipeline existente que ya almacena en caché los datos derivados, `-xctestrun` obtiene la misma vía rápida siempre que el job de compilación se ejecute a través de `tuist test --build-only`.

Cualquier modo de entrada es mutuamente excluyente con `-workspace`/`-project`/`-scheme`, por lo que Tuist omite esos flags cuando los argumentos de paso incluyen `-xctestrun` o `-testProductsPath`, y reenvía los targets seleccionados a través de `-only-testing`.

> [!WARNING]
> **Granularidad a nivel de módulo frente a archivo**
>
> Debido a la imposibilidad de detectar las dependencias en el código entre tests y fuentes, la granularidad máxima de los tests selectivos por defecto está a nivel de target. La [estrategia de cobertura](#coverage-based-test-selection) la reduce a tests individuales de XCTest. Por lo tanto, recomendamos mantener tus targets pequeños y enfocados para maximizar los beneficios de los tests selectivos.


## Selección de tests basada en cobertura {#coverage-based-test-selection}

> [!NOTE]
> **Acceso anticipado**
>
> La selección de tests basada en cobertura está en acceso anticipado. Contáctanos para habilitarla en tu cuenta. Hasta que esté habilitada, la estrategia se comporta como los tests selectivos por defecto.

Por defecto, los tests selectivos omiten targets de test completos cuyo hash ya pasó. La estrategia `.coverage()` va más allá: en los targets de test restantes, también omite los tests de XCTest y XCUITest cuya cobertura de código en una ejecución anterior no incluye ninguno de los archivos que tocó tu cambio. Habilítala en `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

La estrategia requiere:

- **Subidas de cobertura.** Tuist selecciona tests según la cobertura que subieron ejecuciones anteriores, por lo que `tuist test` falla al cargar un manifiesto que establece `.coverage()` con `upload: false`.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 o posterior** enlazado por tus targets de test. Registra qué archivos ejecuta cada test y omite los tests que Tuist no seleccionó. Un target sin esto solo se omite completo, como ocurre por defecto.
- **Ejecuciones de test en tu rama por defecto sin selección.** Ejecuta `tuist test --no-selective-testing` allí, y en cualquier otra rama donde no deban omitirse tests. Esas ejecuciones ejecutan cada test y se convierten en las líneas base con las que comparan las ejecuciones posteriores.

Con la estrategia activada, `tuist test` omite los targets cuyo hash ya pasó, luego pregunta a Tuist qué tests de los targets restantes puede afectar tu cambio. Los targets sin ningún test afectado no se compilan. Los tests nuevos, los tests que fallaron la última vez, los tests en un archivo de test cambiado y los tests sin cobertura registrada siempre se ejecutan. Los tests de Swift Testing se ejecutan siempre que se ejecute su target.

A veces la cobertura no se aplica, y la salida indica por qué: se ejecuta cada test de los targets cuyo hash no pasó, como ocurre con los tests selectivos por defecto. Esto sucede sin una línea base reciente en la misma plataforma, cuando el cambio afecta a más de 5.000 archivos, o cuando cambia un archivo que puede afectar a cualquier test, como `Package.resolved`, `Project.swift` o un `.xcconfig`. Para ejecutar cada test, pasa `--no-selective-testing`.

> [!NOTE]
> **Cobertura de tests**
>
> Las herramientas de cobertura que leen el informe de una sola ejecución, incluida la de Xcode, asumen que se ejecutó toda la suite de tests, por lo que el informe de una ejecución selectiva omite los tests que saltó. La <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">cobertura de código</.localized_link> de Tuist arrastra la cobertura de los targets de test omitidos desde una ejecución anterior, utilizando la <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">cobertura a nivel de target</.localized_link> que registra en cada ejecución.


## Comentarios en pull/merge request {#pullmerge-request-comments}

> [!WARNING]
> **Integración con Git forge requerida**
>
> Para obtener comentarios automáticos en pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.


Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), y comiences a usar `tuist test` como parte de tu flujo de trabajo de CI, Tuist publicará un comentario directamente en tus pull/merge requests, indicando qué tests se ejecutaron y cuáles se omitieron: ![Comentario de la app de GitHub con un enlace a Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Investigación de fallos en el dashboard {#investigating-misses-on-the-dashboard}

Cuando un target de test previamente almacenado en caché aparece como fallo, la pestaña **Tests selectivos** en la página de una ejecución de test te permite analizar las entradas que generaron el hash. Al expandir una fila se revelan los subhashes por componente —fuentes, dependencias, variables de entorno, configuraciones del proyecto y del target, Info.plist, entitlements, cabeceras, etc.— para que puedas identificar la entrada que cambió entre ejecuciones.

Usa el botón **Copiar como JSON** en la parte superior de la tarjeta de Tests selectivos para exportar cada target de test selectivo con su hash y subhashes. Comparar el JSON entre dos ejecuciones es la forma más rápida de confirmar qué entrada cambió cuando el hash del target de test varió.
