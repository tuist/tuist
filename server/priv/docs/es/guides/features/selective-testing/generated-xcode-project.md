---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests selectivos · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta solo los tests de Xcode y del proyecto generado afectados por tus últimos cambios con los tests selectivos de Tuist, para que la integración continua reciba feedback en segundos."
}
---
# Proyecto de Xcode generado {#generated-xcode-project}

A medida que tu proyecto crece, también lo hace la cantidad de tests. Durante mucho tiempo, ejecutar todos los tests en cada PR o push a `main` lleva decenas de segundos. Pero esta solución no escala a los miles de tests que tu equipo podría tener.

En cada ejecución de tests en la CI, lo más probable es que vuelvas a ejecutar todos los tests, independientemente de los cambios. Los tests selectivos de Tuist te ayudan a acelerar drásticamente la ejecución de los propios tests ejecutando solo aquellos que han cambiado desde la última ejecución exitosa, según nuestro <.localized_link href="/guides/features/projects/hashing">algoritmo de hashing</.localized_link>.

Para ejecutar tests de forma selectiva con tu <.localized_link href="/guides/features/projects">proyecto generado</.localized_link>, usa el comando `tuist test`. El comando <.localized_link href="/guides/features/projects/hashing">genera hashes</.localized_link> de tu proyecto del mismo modo que lo hace para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y, si tiene éxito, persiste esos hashes para determinar qué ha cambiado en futuras ejecuciones. En ejecuciones posteriores, `tuist test` utiliza los hashes de forma transparente para filtrar los tests y ejecutar solo los que han cambiado desde la última ejecución exitosa.

`tuist test` se integra directamente con la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> para utilizar tantos binarios como sea posible desde tu almacenamiento local o remoto y mejorar el tiempo de compilación al ejecutar tu suite de tests. La combinación de tests selectivos con caché de módulos puede reducir drásticamente el tiempo necesario para ejecutar tests en tu CI.

Si tus ejecuciones de tests solo apuntan a simuladores, pasa `--destination simulator` para que `tuist test` utilice y descargue únicamente las partes de simulador de los binarios almacenados en caché. Consulta la <.localized_link href="/guides/features/cache/module-cache#destination-selection">selección de destino</.localized_link>. Los hashes de los tests selectivos son los mismos para cada valor de `--destination`.

## Separar trabajos de compilación y de tests {#separate-build-and-test-jobs}

Los tests selectivos admiten trabajos de compilación y de tests separados. Ejecuta `tuist test --build-only` en el trabajo de compilación para que Tuist pueda persistir un archivo `selective-testing-graph.json` junto con los productos que emite la compilación. Ese grafo contiene los hashes que necesitan los tests selectivos, por lo que el trabajo de tests no tiene que regenerar el proyecto ni resolver las dependencias de Swift Package para averiguar qué targets ejecutar.

Tuist escribe el grafo en dos lugares durante `--build-only`:

- Dentro del bundle `.xctestproducts` cuando pasas `-testProductsPath`.
- Junto a cada archivo `.xctestrun` bajo el directorio `Build/Products/` de los datos derivados.

Almacena en caché cualquiera de estas salidas junto con los productos compilados y proporciona la misma ruta a `--without-building` en el trabajo de tests. Ambas formas funcionan:

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

Cuando Tuist no puede encontrar ese grafo junto a la entrada (por ejemplo, cuando el trabajo de compilación usó `xcodebuild build-for-testing` normal en lugar de `tuist test --build-only`), recurre a regenerar el proyecto para poder seguir calculando los targets afectados. Esa alternativa necesita que las dependencias de Swift Package estén resueltas en el trabajo de tests, así que ejecuta primero `tuist install` o almacena en caché `Tuist/.build` entre trabajos.

El grafo refleja el árbol de fuentes tal como estaba en el momento de la compilación. Ejecuta el trabajo de tests contra el mismo commit que el trabajo de compilación; si las fuentes divergen entre ambos, los hashes quedan desactualizados y los tests selectivos pueden omitir tests que realmente fallarían contra las fuentes más recientes.

### ¿Qué flag debo usar? {#which-flag-should-i-use}

`.xctestrun` y `.xctestproducts` son dos formatos de salida de Xcode diferentes, y equilibran la portabilidad con la conveniencia del pipeline:

- **`-testProductsPath` (`.xctestproducts`) — recomendado para nuevos pipelines.** Es un directorio autocontenido: los binarios `.xctest` compilados y sus archivos `.xctestrun` viven dentro de él con rutas relativas a la raíz del bundle, por lo que sigue siendo válido dondequiera que termine. También es el formato que ha tenido la vía rápida de tests selectivos durante más tiempo, por lo que es la ruta más probada.
- **`-xctestrun` (`.xctestrun` raw)** — úsalo si ya tienes un pipeline construido alrededor de los datos derivados. `xcodebuild build-for-testing` escribe un `.xctestrun` en la parte superior de `<derivedData>/Build/Products/` por defecto y lo apunta a los bundles de test que viven en otra parte de ese árbol. Reutilizarlo en otro trabajo significa mantener intactas las rutas en `Build/Products/`.

Si estás empezando de cero, prefiere `-testProductsPath`. Si estás integrando Tuist en un pipeline existente que ya almacena en caché los datos derivados, `-xctestrun` ahora obtendrá la misma vía rápida siempre que el trabajo de compilación se ejecute a través de `tuist test --build-only`.

Cualquier modo de entrada es mutuamente excluyente con `-workspace`/`-project`/`-scheme`, por lo que Tuist omite esos flags cuando los argumentos de paso incluyen `-xctestrun` o `-testProductsPath`, y reenvía los targets seleccionados a través de `-only-testing`.

> [!WARNING]
> **Granularidad a nivel de módulo frente a archivo**
>
> Debido a la imposibilidad de detectar las dependencias en el código entre tests y fuentes, la granularidad máxima de los tests selectivos está a nivel de target. Por lo tanto, recomendamos mantener tus targets pequeños y enfocados para maximizar los beneficios de los tests selectivos.


> [!NOTE]
> **Cobertura de tests**
>
> Las herramientas de cobertura que leen el informe de una única ejecución, incluida la de Xcode, asumen que se ejecutó toda la suite de tests, por lo que el informe de una ejecución selectiva omite los tests que se saltaron. La <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">cobertura de código</.localized_link> de Tuist arrastra la cobertura de los targets de test omitidos desde una ejecución anterior, utilizando la <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">cobertura a nivel de target</.localized_link> que registra en cada ejecución.


## Comentarios en pull/merge requests {#pullmerge-request-comments}

> [!WARNING]
> **Integración con plataforma Git requerida**
>
> Para recibir comentarios automáticos en las pull/merge requests, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto de Tuist</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.


Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), y comiences a usar `tuist test` como parte de tu flujo de trabajo de CI, Tuist publicará un comentario directamente en tus pull/merge requests, incluyendo qué tests se ejecutaron y cuáles se omitieron: ![Comentario de la app de GitHub con un enlace a Tuist Preview](/images/guides/features/selective-testing/github-app-comment.png)


## Investigación de fallos de caché en el dashboard {#investigating-misses-on-the-dashboard}

Cuando un target de test previamente almacenado en caché aparece como un fallo, la pestaña **Tests selectivos** en la página de una ejecución de tests te permite profundizar en las entradas que produjeron el hash. Al expandir una fila se revelan los subhashes por componente —fuentes, dependencias, variables de entorno, configuraciones de proyecto y target, Info.plist, entitlements, headers, etc.— para que puedas identificar la entrada que divergió entre ejecuciones.

Usa el botón **Copiar como JSON** en la parte superior de la tarjeta de Tests selectivos para exportar cada target de test selectivo con su hash y subhashes. Comparar el JSON entre dos ejecuciones es la forma más rápida de confirmar qué entrada cambió cuando el hash del target de test divergió.
