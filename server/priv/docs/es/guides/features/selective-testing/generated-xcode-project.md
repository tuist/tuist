---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests selectivos · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests de Xcode y del proyecto generado afectados por tus últimos cambios con los tests selectivos de Tuist, para que la integración continua reciba feedback en segundos."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

A medida que un proyecto crece, ejecutar todos los tests en cada push deja de ser escalable. Los tests selectivos de Tuist ejecutan solo aquellos tests cuyos targets han cambiado desde la última ejecución exitosa, basándose en el <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link> de Tuist.

Para ejecutar tests de forma selectiva con tu <.localized_link href="/guides/features/projects">proyecto generado</.localized_link>, usa el comando `tuist test`. Este comando <.localized_link href="/guides/features/projects/hashing">genera hashes</.localized_link> de tu proyecto de la misma manera que lo hace para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y, si tiene éxito, persiste esos hashes para determinar qué ha cambiado en futuras ejecuciones. En ejecuciones posteriores, `tuist test` utiliza los hashes de forma transparente para filtrar los tests y ejecutar solo aquellos que han cambiado desde la última ejecución exitosa.

`tuist test` se integra directamente con la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> para utilizar tantos binarios como sea posible desde tu almacenamiento local o remoto, mejorando así el tiempo de compilación al ejecutar tu suite de tests. La combinación de tests selectivos con caché de módulos puede reducir drásticamente el tiempo necesario para ejecutar tests en tu CI.

Si tus tests solo apuntan a simuladores, pasa `--destination simulator` para que `tuist test` utilice y descargue únicamente las porciones de simulador de los binarios en caché. Consulta la <.localized_link href="/guides/features/cache/module-cache#destination-selection">selección de destino</.localized_link>. Los hashes de los tests selectivos son los mismos para cada valor de `--destination`.

## Separar jobs de compilación y test {#separate-build-and-test-jobs}

Los tests selectivos admiten jobs de compilación y test separados. Ejecuta `tuist test --build-only` en el job de compilación para que Tuist pueda persistir un archivo `selective-testing-graph.json` junto con los productos generados por la compilación. Ese grafo contiene los hashes necesarios para los tests selectivos, por lo que el job de test no necesita regenerar el proyecto ni resolver las dependencias de Swift Package para determinar qué targets ejecutar.

Tuist escribe el grafo en dos ubicaciones durante `--build-only`:

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

Cuando Tuist no encuentra ese grafo junto a la entrada (por ejemplo, cuando el job de compilación usó simplemente `xcodebuild build-for-testing` en lugar de `tuist test --build-only`), recurre a regenerar el proyecto para poder calcular aún así los targets afectados. Este mecanismo de respaldo requiere que las dependencias de Swift Package estén resueltas en el job de test, así que ejecuta primero `tuist install` o almacena en caché `Tuist/.build` entre jobs.

El grafo refleja el árbol de fuentes tal como estaba en el momento de la compilación. Ejecuta el job de test contra el mismo commit que el job de compilación; si el código fuente diverge entre ambos, los hashes ya no coinciden con el origen y los tests selectivos podrían omitir tests que realmente fallarían contra el código más reciente.

### ¿Qué flag debo usar? {#which-flag-should-i-use}

`.xctestrun` y `.xctestproducts` son dos formatos de salida diferentes de Xcode, y ofrecen un equilibrio entre portabilidad y conveniencia para el pipeline:

- **`-testProductsPath` (`.xctestproducts`) — recomendado para nuevos pipelines.** Es un directorio autocontenido: los binarios `.xctest` compilados y sus archivos `.xctestrun` residen dentro de él con rutas relativas a la raíz del bundle, por lo que sigue siendo válido dondequiera que se ubique.
- **`-xctestrun` (`.xctestrun` raw) — úsalo si ya tienes un pipeline construido alrededor de los datos derivados.** `xcodebuild build-for-testing` escribe un `.xctestrun` en la parte superior de `<derivedData>/Build/Products/` por defecto y lo apunta hacia bundles de test que viven en otra parte de ese árbol. Reutilizarlo en otro job implica mantener intactas las rutas en `Build/Products/`.

Si estás empezando de cero, prefiere `-testProductsPath`. Si estás integrando Tuist en un pipeline existente que ya almacena en caché los datos derivados, `-xctestrun` obtiene la misma vía rápida siempre que el job de compilación se ejecute mediante `tuist test --build-only`.

Cualquier modo de entrada es mutuamente excluyente con `-workspace`/`-project`/`-scheme`, por lo que Tuist omite esas flags cuando los argumentos de paso incluyen `-xctestrun` o `-testProductsPath`, y reenvía los targets seleccionados a través de `-only-testing`.

> [!WARNING]
> **Granularidad a nivel de módulo frente a archivo**
>
> Debido a la imposibilidad de detectar las dependencias en el código entre tests y fuentes, la granularidad máxima de los tests selectivos por defecto está a nivel de target. La [estrategia de cobertura](#coverage-based-test-selection) la reduce hasta tests individuales. Por lo tanto, recomendamos mantener tus targets pequeños y enfocados para maximizar los beneficios de los tests selectivos.


## Selección de tests basada en cobertura {#coverage-based-test-selection}

> [!NOTE]
> **Acceso anticipado**
>
> La selección de tests basada en cobertura está en acceso anticipado. Contáctanos para habilitarla en tu cuenta. Hasta que esté habilitada, la estrategia se comporta como los tests selectivos por defecto.

Por defecto, los tests selectivos omiten targets de test completos cuyo hash ya pasó. La estrategia `.coverage()` va más allá: en los targets de test restantes, también omite los tests cuya cobertura de código en una ejecución anterior no incluye ninguno de los archivos que tu cambio tocó. Funciona con tests XCTest y XCUITest, y con tests de [Swift Testing](#swift-testing) en suites configuradas para ello. Habilítalo en `Tuist.swift`:

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

- **Cargas de cobertura.** Tuist selecciona tests según la cobertura que subieron ejecuciones anteriores, por lo que `tuist test` falla al cargar un manifiesto que establece `.coverage()` con `upload: false`.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 o posterior** [vinculado por tus targets de test](#linking-testcoverageattribution). Registra qué archivos ejecuta cada test y omite los tests que Tuist no seleccionó. Un target sin esta dependencia solo se omite por completo, como ocurre por defecto.
- **Ejecuciones completas de tests, con suficiente frecuencia.** Una ejecución con `tuist test --no-selective-testing` ejecuta todos los tests y se convierte en una línea base. Una ejecución selectiva compara contra una reciente en el historial de su commit en la misma plataforma, y no aplica cobertura sin una. Dónde y con qué frecuencia ejecutarlas depende de cómo trabaja tu equipo, como en cada commit de tu rama principal, nightly o en ramas de release. Recomendamos la rama principal: una ejecución completa allí también detecta, antes de que un cambio se publique, lo que la cobertura no puede ver, como un fixture o un servicio del que depende un test.

Con la estrategia activada, `tuist test` omite los targets cuyo hash ya pasó, luego pregunta a Tuist qué tests de los targets restantes puede afectar tu cambio. Los targets sin ningún test afectado no se compilan. Los tests nuevos, los que fallaron la última vez, los tests en un archivo de test modificado y los tests sin cobertura registrada siempre se ejecutan.

A veces no se aplica la cobertura y la salida indica el motivo: se ejecutan todos los tests de los targets cuyo hash no pasó, como ocurre con los tests selectivos por defecto. Esto sucede cuando no hay una línea base reciente en la misma plataforma, cuando el cambio afecta a más de 5.000 archivos o cuando cambia un archivo que puede afectar a cualquier test, como `Package.resolved`, `Project.swift` o un `.xcconfig`. Para ejecutar todos los tests, pasa `--no-selective-testing`.

> [!NOTE]
> **Cobertura de tests**
>
> Las herramientas de cobertura que leen el informe de una sola ejecución, incluida la de Xcode, asumen que se ejecutó toda la suite de tests, por lo que el informe de una ejecución selectiva omite los tests que saltó. La <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">cobertura de código</.localized_link> de Tuist arrastra la cobertura de los targets de test omitidos desde una ejecución anterior, usando la <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">cobertura a nivel de target</.localized_link> que registra en cada ejecución.

### Vinculación de TestCoverageAttribution {#linking-testcoverageattribution}

Añade el paquete a `Tuist/Package.swift`, fijado a su versión menor, ya que una release menor 0.x puede cambiar lo que registra:

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

Luego añádelo a tus targets de test, y nunca a un target de app:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Por defecto, Tuist vincula los paquetes como frameworks estáticos. Un target solo de XCTest no referencia nada del paquete, por lo que el enlazador lo descarta y, con ello, el registro y la omisión. Añade `-ObjC` a las `OTHER_LDFLAGS` del target de test, o vincula el paquete dinámicamente en `Tuist/Package.swift`:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing no tiene una API de observación a la que pueda adjuntarse una biblioteca, por lo que sus tests necesitan el trait `.coverageAttribution` de TestCoverageAttribution en su suite. El trait se aplica a las suites anidadas en la que lo tiene. Los tests en suites sin él no registran cobertura por test, por lo que se ejecutan siempre que se ejecute su target.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Los tests no deben solaparse.** Swift Testing ejecuta los tests de un proceso en paralelo por defecto, y los contadores de cobertura no pueden distinguir tests que se ejecutan al mismo tiempo, por lo que esos tests no registran cobertura propia y siempre se ejecutan. `.serialized` solo ordena los tests de una suite, por lo que basta únicamente cuando el target tiene una sola suite. XCTest no necesita nada: las pruebas paralelas ejecutan cada clon de test en su propio proceso.
- **Desactiva la paralelización por target de test.** Xcode aplica la configuración a cada target de test, por lo que puedes desactivarla solo para los targets cuyos tests quieres seleccionar uno a uno, mientras los demás targets del esquema siguen ejecutándose en paralelo. No hace falta un esquema separado. Configúralo en el target testeable, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, lo que también ejecuta los tests XCTest de ese target sin clones. Los esquemas que genera Tuist toman esta opción de las `testingOptions` del proyecto, desactivada a menos que incluyan `.parallelizable` o `.swiftTestingOnlyParallelizable`. Pasar `-parallel-testing-enabled YES` o `NO` a `tuist test` sobrescribe la configuración de todos los targets para esa ejecución.
- **La omisión requiere Swift 6.3 (Xcode 26.4) o posterior.** El trait cancela los tests que Tuist no seleccionó y los informa como omitidos. Con versiones anteriores, los tests siguen registrando cobertura, pero los que Tuist no seleccionó se ejecutan de todos modos.

### Tests que siempre se ejecutan {#tests-that-always-run}

La cobertura solo ve el código que ejecuta un test. Un test cuyas entradas reales son fixtures, recursos, la red o el entorno puede fallar sin que cambie ningún código cubierto. Márcalo como no omitible y se ejecutará incluso cuando Tuist no lo seleccione:

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

Solo se aplica en targets de test que se ejecutan. Un target cuyo hash ya pasó, o del cual Tuist no seleccionó ningún test, se omite por completo y nunca se inicia, por lo que sus tests no omitibles tampoco se ejecutan.

Consulta el [README de TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) para ver todas las opciones.


## Comentarios en pull/merge requests {#pullmerge-request-comments}

> [!WARNING]
> **Integración con forja Git requerida**
>
> Para obtener comentarios automáticos en pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una forja Git: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> o <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), y empieces a usar `tuist test` como parte de tu flujo de CI, Tuist publicará un comentario directamente en tus pull/merge requests, indicando qué tests se ejecutaron y cuáles se omitieron: ![Comentario de la app de GitHub con un enlace a Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Investigación de fallos en el dashboard {#investigating-misses-on-the-dashboard}

Cuando un target de test previamente almacenado en caché aparece como fallo, la pestaña **Tests selectivos** en la página de una ejecución de tests te permite profundizar en las entradas que generaron el hash. Al expandir una fila se revelan los subhashes por componente —fuentes, dependencias, variables de entorno, configuraciones de proyecto y target, Info.plist, entitlements, cabeceras, etc.—, para que puedas identificar la entrada que varió entre ejecuciones.

Usa el botón **Copiar como JSON** en la parte superior de la tarjeta de Tests selectivos para exportar todos los targets de tests selectivos con su hash y subhashes. Comparar el JSON entre dos ejecuciones es la forma más rápida de confirmar qué entrada cambió cuando varió el hash del target de test.
