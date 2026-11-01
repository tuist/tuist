---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests selectivos · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests de Xcode y del proyecto generado afectados por tus últimos cambios con los tests selectivos de Tuist, para que la integración continua te devuelva feedback en segundos."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

A medida que tu proyecto crece, también lo hace la cantidad de tests. Durante mucho tiempo, ejecutar todos los tests en cada PR o push a `main` ha llevado decenas de segundos. Pero esta solución no escala para los miles de tests que tu equipo podría tener.

En cada ejecución de tests en la CI, lo más probable es que vuelvas a ejecutar todos los tests, independientemente de los cambios. Los <.localized_link href="/guides/features/projects/hashing">tests selectivos</.localized_link> de Tuist te ayudan a acelerar drásticamente la ejecución de los propios tests ejecutando únicamente aquellos que han cambiado desde la última ejecución de tests exitosa, basándose en nuestro algoritmo de hashing.

Para ejecutar tests de forma selectiva con tu <.localized_link href="/guides/features/projects">proyecto generado</.localized_link>, utiliza el comando `tuist test`. Este comando <.localized_link href="/guides/features/projects/hashing">genera hashes</.localized_link> de tu proyecto del mismo modo que lo hace para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y, si tiene éxito, persiste esos hashes para determinar qué ha cambiado en futuras ejecuciones. En ejecuciones posteriores, `tuist test` utiliza los hashes de forma transparente para filtrar los tests y ejecutar solo aquellos que han cambiado desde la última ejecución de tests exitosa.

`tuist test` se integra directamente con la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> para utilizar tantos binarios como sea posible desde tu almacenamiento local o remoto y mejorar el tiempo de compilación al ejecutar tu suite de tests. La combinación de tests selectivos con la caché de módulos puede reducir drásticamente el tiempo necesario para ejecutar tests en tu CI.

## Jobs de compilación y tests separados {#separate-build-and-test-jobs}

Los tests selectivos admiten jobs de compilación y tests separados. Ejecuta `tuist test --build-only` en el job de compilación para que Tuist pueda persistir un archivo `selective-testing-graph.json` junto con los productos que genera la compilación. Ese grafo contiene los hashes necesarios para los tests selectivos, por lo que el job de tests no tiene que regenerar el proyecto ni resolver las dependencias de Swift Package para averiguar qué targets ejecutar.

Tuist escribe el grafo en dos lugares durante `--build-only`:

- Dentro del bundle `.xctestproducts` cuando pasas `-testProductsPath`.
- Junto a cada archivo `.xctestrun` bajo el directorio `Build/Products/` de los datos derivados.

Almacena en caché cualquiera de estas salidas junto con los productos compilados y pasa la misma ruta a `--without-building` en el job de tests. Ambas formas funcionan:

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
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Cuando Tuist no puede encontrar ese grafo junto a la entrada (por ejemplo, cuando el job de compilación usó simplemente `xcodebuild build-for-testing` en lugar de `tuist test --build-only`), recurre a regenerar el proyecto para poder calcular aún así los targets afectados. Esa alternativa requiere que las dependencias de Swift Package estén resueltas en el job de tests, así que ejecuta primero `tuist install` o almacena en caché `Tuist/.build` entre jobs.

El grafo refleja el árbol de fuentes tal como estaba en el momento de la compilación. Ejecuta el job de tests contra el mismo commit que el job de compilación; si el código fuente diverge entre ambos, los hashes quedarán desactualizados y los tests selectivos podrían omitir tests que realmente fallarían contra el código fuente más reciente.

### ¿Qué flag debo usar? {#which-flag-should-i-use}

`.xctestrun` y `.xctestproducts` son dos formatos de salida diferentes de Xcode, y ofrecen un equilibrio entre portabilidad y comodidad en el pipeline:

- **`-testProductsPath` (`.xctestproducts`) — recomendado para nuevos pipelines.** Es un directorio autocontenido: los binarios `.xctest` compilados y sus archivos `.xctestrun` viven dentro de él con rutas relativas a la raíz del bundle, por lo que sigue siendo válido dondequiera que termine. Además, es el formato que lleva más tiempo teniendo la vía rápida para tests selectivos, por lo que es la ruta más probada.
- **`-xctestrun` (`.xctestrun` raw) — úsalo si ya tienes un pipeline construido alrededor de los datos derivados.** `xcodebuild build-for-testing` escribe un `.xctestrun` en la parte superior de `<derivedData>/Build/Products/` por defecto y lo apunta a los bundles de tests que residen en otra parte de ese árbol. Reutilizarlo en otro job significa mantener intactas las rutas en `Build/Products/`.

Si estás empezando desde cero, prefiere `-testProductsPath`. Si estás integrando Tuist en un pipeline existente que ya almacena en caché los datos derivados, `-xctestrun` obtendrá ahora la misma vía rápida siempre que el job de compilación se ejecute a través de `tuist test --build-only`.

Cualquier modo de entrada es mutuamente excluyente con `-workspace`/`-project`/`-scheme`, por lo que Tuist omite esos flags cuando los argumentos de paso incluyen `-xctestrun` o `-testProductsPath`, y reenvía los targets seleccionados a través de `-only-testing`.

> [!WARNING]
> **Granularidad a nivel de módulo frente a archivo**
>
> Debido a la imposibilidad de detectar las dependencias en el código entre tests y fuentes, la granularidad máxima de los tests selectivos está a nivel de target. Por lo tanto, recomendamos mantener tus targets pequeños y enfocados para maximizar los beneficios de los tests selectivos.


> [!WARNING]
> **Cobertura de tests**
>
> Las herramientas de cobertura de tests asumen que toda la suite de tests se ejecuta a la vez, lo que las hace incompatibles con las ejecuciones de tests selectivos; esto significa que los datos de cobertura podrían no reflejar la realidad al usar la selección de tests. Esta es una limitación conocida y no significa que estés haciendo algo mal. Animamos a los equipos a reflexionar sobre si la cobertura sigue aportando información valiosa en este contexto y, si es así, ten la seguridad de que ya estamos pensando en cómo hacer que la cobertura funcione correctamente con ejecuciones selectivas en el futuro.


## Comentarios en pull/merge requests {#pullmerge-request-comments}

> [!WARNING]
> **Integración con plataforma Git requerida**
>
> Para recibir comentarios automáticos en las pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.


Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), y comiences a usar `tuist test` como parte de tu flujo de trabajo de CI, Tuist publicará un comentario directamente en tus pull/merge requests, indicando qué tests se ejecutaron y cuáles se omitieron: ![Comentario de la app de GitHub con un enlace a Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Investigación de fallos de caché en el dashboard {#investigating-misses-on-the-dashboard}

Cuando un target de test almacenado previamente en caché aparece como un fallo, la pestaña **Tests selectivos** en la página de una ejecución de tests te permite profundizar en las entradas que produjeron el hash. Al expandir una fila se revelan los subhashes por componente: fuentes, dependencias, variables de entorno, configuraciones del proyecto y del target, Info.plist, entitlements, headers, etc., para que puedas identificar la entrada que divergió entre ejecuciones.

Usa el botón **Copiar como JSON** en la parte superior de la tarjeta de Tests selectivos para exportar cada target de test selectivo con su hash y subhashes. Comparar el JSON entre dos ejecuciones es la forma más rápida de confirmar qué entrada cambió cuando el hash del target de test divergió.
