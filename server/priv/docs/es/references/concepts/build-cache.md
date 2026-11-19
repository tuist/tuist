---
{
  "title": "¿Qué es una caché de compilación? Cachés de compilación locales y remotas explicadas",
  "titleTemplate": ":title · Tuist",
  "description": "Una caché de compilación reutiliza los resultados de compilaciones anteriores. Cómo funcionan las cachés de compilación locales y remotas en Xcode, Gradle y Bazel, qué son las cachés de Xcode y cuándo merece la pena usar la caché."
}
---
# ¿Qué es una caché de compilación? {#what-is-a-build-cache}

Una caché de compilación almacena los resultados de pasos individuales de la compilación, como archivos objeto compilados, módulos, bibliotecas o resultados de tests, bajo una clave calculada a partir de todo lo que interviene en su producción: archivos de código fuente, flags del compilador, dependencias, entorno y versión del toolchain. Cuando una compilación posterior necesita un paso cuyas entradas generan la misma clave, el sistema de compilación toma el resultado almacenado en lugar de volver a ejecutar el paso. Una **caché de compilación local** reside en una máquina y acelera las compilaciones posteriores de esa máquina. Una **caché de compilación remota** es un servidor compartido al que muchas máquinas leen y escriben, de modo que un trabajo de CI, un compañero de equipo o un agente de programación pueden reutilizar resultados que otra persona ya compiló.

## Caché de compilación, compilación incremental y caché de CI {#build-cache-incremental-build-and-ci-cache}

Tres conceptos suelen llamarse «la caché», pero se comportan de forma distinta:

- **Las compilaciones incrementales** reutilizan los resultados que ya están en tu directorio de compilación y solo recompilan lo que ha cambiado desde la última compilación en ese directorio. Suelen basarse en marcas de tiempo de archivos o en un grafo de dependencias asociado a los productos de la compilación. Cambiar de rama, mover el checkout o empezar desde una máquina nueva hace que se pierda ese estado.
- **Una caché de compilación** busca los resultados por el contenido de sus entradas, no por lo que se haya compilado último en el mismo directorio. Esto permite reutilizar los resultados entre ramas, checkouts y máquinas, siempre que las entradas coincidan.
- **La caché de directorios de CI** (por ejemplo `actions/cache` en GitHub Actions) guarda un directorio al final de un trabajo y lo restaura al inicio del siguiente, bajo una clave que eliges, como el hash de un lockfile. Es una transferencia de archivos, no una caché de compilación: el sistema de compilación sigue decidiendo qué recompilar, y un directorio restaurado puede estar parcial o totalmente desactualizado.

Las cachés de dependencias, como los paquetes descargados o la caché de paquetes de Gradle o Swift, son otro concepto distinto: guardan la descarga por red, no la compilación.

## Cómo funciona una caché de compilación {#how-a-build-cache-works}

Los sistemas de compilación que admiten caché dividen la compilación en pasos (Bazel los llama acciones, Gradle los llama tareas) y hacen lo mismo con cada uno:

1. **Calcular una clave de caché.** El sistema de compilación genera un hash de cada entrada que pueda afectar al resultado: el contenido de los archivos de entrada, la línea de comandos o la configuración de la tarea, las variables de entorno relevantes y el toolchain.
2. **Buscar la clave.** Comprueba primero la caché local y, si está configurada, la caché remota.
3. **Acierto o fallo.** En caso de acierto, descarga o copia los resultados almacenados y omite el paso. En caso de fallo, ejecuta el paso y, si está permitido, sube los resultados bajo esa clave.

La mayoría de las cachés almacenan los resultados en un **almacenamiento direccionable por contenido** (CAS), donde cada blob se guarda bajo el hash de su propio contenido, más un índice separado que va de las claves de caché a los resultados que produjeron. Los archivos idénticos se almacenan una sola vez y un cliente puede verificar lo que ha descargado.

El modelo tiene un requisito estricto: la clave debe incluir todas las entradas que cambian el resultado. Si un paso lee una entrada que el sistema de compilación desconoce, como un archivo no declarado, una variable de entorno, la hora actual o una herramienta instalada en la máquina, la caché puede devolver un resultado que no coincide con las entradas actuales. Los sistemas de compilación llaman **herméticos** a los pasos que solo dependen de entradas declaradas. El problema opuesto es más común y menos peligroso: una clave que incluye algo irrelevante, como una ruta absoluta o una marca de tiempo, produce una clave distinta en cada máquina, por lo que la caché nunca acierta.

## Cómo funcionan las cachés de compilación según el sistema de compilación {#how-it-works-per-build-system}

### Caché de compilación de Gradle {#gradle}

La [caché de compilación de Gradle](https://docs.gradle.org/current/userguide/build_cache.html) almacena los resultados de tareas cacheables, como la compilación de Java y Kotlin y la ejecución de tests, indexadas por el tipo de tarea, su implementación, las propiedades de entrada y los archivos de entrada normalizados. Está desactivada por defecto. Actívala con `org.gradle.caching=true` en `gradle.properties` o con `--build-cache` para una única compilación.

- **Local.** La caché local integrada es un directorio en el home del usuario de Gradle (`~/.gradle` por defecto). Se activa cuando la caché de compilación está habilitada y Gradle elimina periódicamente las entradas que no se han usado recientemente.
- **Remota.** Una caché remota se configura en `settings.gradle(.kts)`, por ejemplo con `HttpBuildCache`. Gradle descarga los resultados de la caché remota cuando hay un fallo en la caché local y los guarda localmente para la próxima vez. La caché remota no acepta subidas por defecto; una configuración habitual permite que CI haga push (`isPush = true` cuando se ejecuta en CI) y que las máquinas de desarrollo solo lean.

Gradle informa de una tarea restaurada desde la caché como `FROM-CACHE`, que es distinto de `UP-TO-DATE`: up-to-date significa que la compilación incremental de Gradle encontró los resultados de la tarea ya presentes, sin consultar la caché. La caché de configuración es una tercera funcionalidad independiente que cachea el resultado de la fase de configuración, no los resultados de las tareas.

### Caché remota de Bazel {#bazel}

Bazel cachea cada acción. Su caché de acciones mapea la clave de una acción, un digest de su línea de comandos, entorno y archivos de entrada, a los resultados de la acción, y los propios resultados viven en un almacén direccionable por contenido.

- **Local.** Bazel mantiene una caché de acciones y los resultados de la compilación en su base de salida, lo que te ofrece compilaciones incrementales rápidas en un único workspace. `--disk_cache=<path>` añade una caché en disco que se comparte entre workspaces y ramas en la misma máquina.
- **Remota.** `--remote_cache=grpcs://…` (o `https://…`) apunta Bazel a una caché remota que implementa la [API de Ejecución Remota](https://github.com/bazelbuild/remote-apis) o una caché HTTP simple. `--remote_upload_local_results=false` convierte una máquina en solo lectura, que es como muchos equipos evitan que las máquinas de desarrollo escriban en la caché compartida. `--remote_download_minimal` o `--remote_download_toplevel` («build without the bytes») evita descargar resultados intermedios que la compilación local nunca necesita.

Bazel también cachea los resultados de los tests: un test cuyas entradas no han cambiado se informa como `(cached) PASSED` sin ejecutarse. Una caché remota no es lo mismo que la ejecución remota, donde las acciones también se ejecutan en máquinas remotas; una caché solo almacena resultados.

### ¿Qué son las cachés de Xcode? {#xcode}

Xcode utiliza varias cachés y directorios que son fáciles de confundir. Los que afectan a los tiempos de compilación son:

- **DerivedData** (`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`) contiene los productos de compilación, archivos intermedios, índice, registros y paquetes Swift resueltos de cada proyecto. Es el estado que reutilizan las compilaciones incrementales. Eliminarlo es seguro, pero la siguiente compilación de ese proyecto será una recompilación completa, y el indexado y la resolución de paquetes se ejecutarán de nuevo.
- **La caché de módulos de Clang** (`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`) contiene módulos de Clang precompilados (archivos `.pcm`) para módulos de C y Objective-C importados y frameworks del SDK, compartidos entre proyectos. Con los módulos construidos explícitamente habilitados, Xcode construye los módulos como tareas de compilación normales y los mantiene junto con los intermedios de cada proyecto. Eliminarla es seguro; los módulos se reconstruyen bajo demanda.
- **La caché de compilación** (Xcode 26 y posteriores, `CompilationCache.noindex` dentro de DerivedData por defecto, configurable con `COMPILATION_CACHE_CAS_PATH`) contiene resultados de compilación direccionables por contenido para Swift, C y Objective-C cuando `COMPILATION_CACHE_ENABLE_CACHING = YES`. Eliminarla es seguro; las compilaciones que podrían haberse reproducido se ejecutan de nuevo.
- **La caché de Swift Package Manager** (`~/Library/Caches/org.swift.swiftpm/`) contiene repositorios de paquetes descargados y manifiestos compartidos entre proyectos. Eliminarla es seguro; los paquetes se vuelven a descargar.

Otros directorios grandes bajo `~/Library/Developer` no son cachés de compilación, pero suelen aparecer al limpiar espacio en disco: `Xcode/Archives` contiene compilaciones de apps archivadas y sus símbolos de depuración (conserva los que puedas necesitar para simbolizar crashes), `Xcode/iOS DeviceSupport` contiene símbolos para las versiones del SO de los dispositivos conectados, y `CoreSimulator/Devices` contiene simuladores y sus datos (`xcrun simctl delete unavailable` elimina los simuladores de entornos de ejecución que ya no están instalados).

DerivedData es el estado de compilación incremental de Xcode, no una caché direccionable por contenido: está vinculado a la ubicación del proyecto en el disco y a las marcas de tiempo de los archivos. Restaurar DerivedData desde una caché de CI en una ruta diferente, o después de un checkout limpio que cambia la hora de modificación de cada archivo, a menudo provoca una recompilación completa de todos modos.

La **caché de compilación**, introducida en Xcode 26, es la caché de compilación de Xcode en el sentido de esta página. Almacena los resultados de compilación según el contenido de sus entradas y los reproduce en caso de acierto, por lo que los resultados sobreviven a cambios de rama y a la limpieza de productos de compilación. Cachea la compilación, no cada paso de la compilación: el enlazado, el procesamiento de recursos y las fases de script siguen ejecutándose. Por defecto, el almacén es local a una máquina y reside dentro de DerivedData, por lo que eliminar todo DerivedData lo descarta; eliminar solo los productos de compilación de un proyecto lo mantiene. Xcode también puede conectar la caché de compilación a un servicio de caché remota mediante un plugin (`COMPILATION_CACHE_ENABLE_PLUGIN` y `COMPILATION_CACHE_REMOTE_SERVICE_PATH`), lo que la convierte en una caché remota compartida.

Antes de la caché de compilación, los proyectos de Xcode reutilizaban trabajo entre máquinas principalmente mediante **caché binaria** de módulos completos: construyendo dependencias como frameworks precompilados o XCFrameworks y enlazándolos en lugar de compilar las fuentes. Esto funciona a nivel de granularidad de módulo en lugar de compilación, y cambia cómo se construye el proyecto.

## Latencia, tamaño de blob y cantidad de blobs {#latency-blob-size-and-blob-count}

Un acierto en una caché remota no es gratuito. Obtener un resultado tiene un coste de retraso fijo por cada solicitud que debe esperar a la anterior, más el tiempo para transferir sus bytes:

**tiempo ≈ R × L + S / B**

donde *R* es el número de idas y vueltas que no pueden superponerse, *L* es la latencia de ida y vuelta a la caché, *S* es el número de bytes transferidos y *B* es el ancho de banda. Qué término domina depende de cómo el sistema de compilación divide su trabajo en blobs:

- **Pocos blobs grandes están limitados por el ancho de banda.** Las cachés que almacenan resultados gruesos, como los resultados empaquetados de una tarea de Gradle o un framework precompilado en una caché de módulos binarios, realizan menos solicitudes que mueven megabytes cada una. Un conjunto de resultados de 200 MB tarda unos 16 segundos a 100 Mbit/s y menos de 2 segundos a 1 Gbit/s, mientras que unos milisegundos extra de latencia apenas importan.
- **Muchos blobs pequeños están limitados por la latencia.** Las cachés de grano fino, como la caché por acción de Bazel y la caché de compilación de Xcode, realizan miles de solicitudes para blobs de unos pocos kilobytes, muchas de ellas solo para preguntar si existe una clave. Con 2.000 búsquedas, 8 en vuelo a la vez y 40 ms de latencia, una compilación espera unos 10 segundos solo en idas y vueltas, independientemente de lo pequeños que sean los blobs. Con 2 ms de latencia, las mismas búsquedas tardan aproximadamente medio segundo. Más ancho de banda no ayuda aquí; una caché más cercana sí.
- **Los fallos también cuestan una ida y vuelta.** Cada búsqueda que falla añade latencia sin ahorrar ningún trabajo. Una caché distante con una tasa de aciertos baja puede hacer que una compilación sea más lenta que no tener ninguna caché remota.
- **El volumen multiplica ambos factores.** El número de blobs crece con la estructura del proyecto: un grafo de muchos módulos o targets pequeños produce más resultados, pero más pequeños, que unos pocos grandes. Dividir un proyecto mejora el paralelismo y la invalidación, pero hace que la compilación sea más sensible a la latencia de la caché.

Un acierto solo merece la pena cuando obtener el resultado es más rápido que recalculándolo, y esa comparación cambia con la distancia. Una compilación que tarda 50 ms localmente es un buen acierto desde una caché en la misma red y uno pobre desde una caché en otro continente. Por eso, las palancas para las cachés remotas tienen que ver principalmente con la latencia y el número de solicitudes más que con el ancho de banda bruto:

- **Coloca la caché cerca de donde se ejecutan las compilaciones**, en la misma región o red que los runners de CI, y tan cerca como sea posible de los desarrolladores.
- **Superpón las solicitudes.** La API de Ejecución Remota de Bazel agrupa las comprobaciones de existencia (`FindMissingBlobs`) y las lecturas pequeñas, y `--remote_max_connections` limita la concurrencia. `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` de Xcode ejecuta las búsquedas en la caché de compilación junto con el resto de la compilación en lugar de en sus carriles de ejecución. HTTP/2 multiplexa muchas solicitudes sobre una única conexión.
- **Descarga menos.** `--remote_download_minimal` de Bazel omite los resultados intermedios, y una capa de caché local, como `--disk_cache` de Bazel o la caché de compilación local de Gradle, sirve aciertos repetidos sin una solicitud de red.
- **Comprime los blobs grandes.** `--remote_cache_compression` de Bazel utiliza zstd cuando la caché lo admite, lo que ayuda a las transferencias limitadas por ancho de banda y hace poco por las limitadas por latencia.

## Errores comunes {#common-pitfalls}

- **Entradas no declaradas.** Un paso lee un archivo, una variable de entorno o una herramienta que no forma parte de su clave. La caché puede entonces devolver resultados construidos a partir de entradas diferentes. En Gradle, declara todas las entradas de las tareas personalizadas; en Bazel, mantén las acciones herméticas y considera `--incompatible_strict_action_env` para que el `PATH` del host no se filtre.
- **Claves específicas de la máquina.** Las rutas absolutas, los nombres de usuario y las marcas de tiempo de compilación incrustadas en las entradas o salidas hacen que las claves difieran entre máquinas, por lo que la caché remota nunca acierta. La sensibilidad a las rutas de Gradle, las rutas de ejecución relativas de Bazel y la configuración de mapeo de prefijos de Clang y Swift en Xcode existen para eliminar esas diferencias.
- **Entradas volátiles cerca de la raíz del grafo.** Incluir un número de compilación, un hash de commit o una fecha en un módulo del que todo depende invalida todo lo que está por encima en cada compilación. Inyecta los valores volátiles lo más tarde posible, idealmente solo en las compilaciones de release.
- **Incompatibilidades de toolchain.** Diferentes versiones del compilador, JDK o Xcode producen claves distintas. Ese es el comportamiento correcto, pero una flota con versiones mezcladas efectivamente divide la caché.
- **Escrituras envenenadas o no confiables.** Una máquina de desarrollo con cambios sin confirmar o una configuración no hermética puede subir resultados que otros reutilizan luego. Muchos equipos permiten que solo la CI en ramas confiables escriba en la caché remota y hacen que todas las demás máquinas sean de solo lectura. Las compilaciones de pull requests no confiables no deben escribir en una caché que leen las compilaciones confiables.
- **Ignorar el coste de transferencia.** Un paso que tarda 50 milisegundos en ejecutarse puede tardar más en obtenerse desde una caché distante. Consulta [Latencia, tamaño de blob y recuento de blobs](#latency-blob-size-and-blob-count).
- **Ejecuciones de tests ocultas.** Almacenar en caché los resultados de los tests es correcto cuando los tests son deterministas, pero también significa que un test intermitente que pasó una vez sigue pasando sin ejecutarse. Consulta <.localized_link href="/references/concepts/flaky-test">¿Qué es un test intermitente?</.localized_link>.

## Cómo medir una caché de compilación {#how-to-measure-a-build-cache}

Una caché vale lo que ahorra de principio a fin, no solo su tasa de aciertos:

- **Tasa de aciertos, ponderada por el trabajo.** Cuenta los aciertos y fallos por paso, pero ponles peso según cuánto tarda en ejecutarse cada paso. Una tasa de aciertos del 95% en pasos baratos puede ahorrar menos que una tasa del 50% en las compilaciones más lentas.
- **Compilaciones en frío, en caliente y típicas.** Compara una compilación con una caché vacía, una compilación con una caché totalmente caliente y las compilaciones que la gente ejecuta realmente, como la CI en un pull request tras un pequeño cambio. Este último es el número que importa.
- **Tiempo dedicado a la propia caché.** Mide el recuento de solicitudes, la latencia, los bytes y el tiempo dedicado a descargar y subir. Si la mayor parte de ese tiempo se espera en muchas solicitudes pequeñas, una caché más cercana ayuda más que más ancho de banda; si se mueven unos pocos blobs grandes, el ancho de banda y la compresión importan más.
- **Por qué ocurren los fallos.** Compara las claves de caché para el mismo paso en dos máquinas. Gradle puede imprimir las entradas detrás de cada clave con `-Dorg.gradle.caching.debug=true`, Bazel puede escribir registros de ejecución (`--execution_log_compact_file`) que puedes comparar entre dos compilaciones, y Xcode informa de aciertos y fallos de la caché de compilación en el registro de compilación cuando `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES`.

## Cuándo no merece la pena {#when-it-isnt-worth-it}

Una caché de compilación añade infraestructura, un límite de seguridad y una nueva clase de bugs. No siempre es la herramienta adecuada:

- **Compilaciones pequeñas o rápidas.** Si una compilación limpia tarda un minuto, una caché remota ahorra poco, y las idas y vueltas de red pueden hacerla más lenta.
- **Compilaciones que fallan por diseño.** Si la mayoría de las compilaciones cambian una entrada cerca de la raíz del grafo, la caché no puede ayudar hasta que eso se arregle. Arregla primero la invalidación; una caché solo omite el trabajo cuyas entradas coinciden.
- **Máquinas de compilación persistentes.** Una máquina de CI que mantiene su directorio de compilación entre trabajos en la misma rama ya obtiene compilaciones incrementales. Una caché compartida ayuda cuando las máquinas son efímeras, cuando hay muchas ramas o cuando los desarrolladores y la CI deberían reutilizar el trabajo de los demás.
- **Compilaciones no herméticas que aún no puedes arreglar.** Una caché que ocasionalmente devuelve resultados incorrectos cuesta más confianza de la que ahorra tiempo. Haz que los pasos que almacenas en caché sean reproducibles primero, o deja sin caché los problemáticos (por ejemplo, con la etiqueta `no-remote-cache` de Bazel).
- **Redes lentas o distantes.** Si la caché está lejos de donde se ejecutan las compilaciones, mide el tiempo de transferencia antes de implementarla para todos.

## Caché de compilación con Tuist {#build-caching-with-tuist}

[Tuist](https://tuist.dev) proporciona una caché remota que se integra con la caché propia de cada sistema de compilación, de modo que las máquinas de los desarrolladores, la CI y los agentes de programación reutilizan los resultados de los demás, y registra aciertos, fallos y tiempos de transferencia para que puedas medir el efecto:

- <.localized_link href="/guides/features/cache/xcode-cache">Caché de Xcode</.localized_link> conecta la caché de compilación de Xcode a una caché remota compartida, para cualquier proyecto de Xcode en Xcode 26 o posterior.
- <.localized_link href="/guides/features/cache/module-cache">Caché de módulos</.localized_link> sustituye módulos completos por binarios precompilados en proyectos generados con Tuist.
- <.localized_link href="/guides/features/cache/gradle-cache">Caché de Gradle</.localized_link> y <.localized_link href="/guides/features/cache/bazel-cache">caché de Bazel</.localized_link> sirven como caché de compilación remota de Gradle y como caché de la API de Ejecución Remota para Bazel.
- <.localized_link href="/guides/features/cache">Caché</.localized_link> enumera todos los sistemas de compilación compatibles, incluidos Elixir y Once.
- [Compilaciones lentas](https://tuist.dev/solutions/slow-builds) es una guía práctica para encontrar el trabajo que merece la pena eliminar antes de elegir una caché.
- [La física de los sistemas de compilación](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) y [Kura](https://tuist.dev/blog/2026/09/14/kura) explican, con mediciones de la caché de Tuist, cómo difieren el tamaño de los artefactos y el volumen de solicitudes entre la caché de módulos, la caché de compilación de Xcode, Bazel y Gradle.
