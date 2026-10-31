---
{
  "title": "Caché de Xcode",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Acelera las compilaciones de Xcode en local y en CI con la integración de caché de Xcode de Tuist."
}
---
# Caché de Xcode {#xcode-cache}

Tuist ofrece compatibilidad con la caché de compilación de Xcode, lo que permite a los equipos compartir artefactos de compilación aprovechando las capacidades de caché del sistema de compilación.

La caché de Xcode se introdujo en Xcode 26. También puedes verla referida como la caché de compilación de Xcode; reutiliza artefactos de compilación indexados por sus entradas, y la caché remota de Tuist hace que esos artefactos sean compartibles entre máquinas.

> [!TIP]
> **Combínala con la caché de módulos**
>
> La caché de Xcode y la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> funcionan a distintos niveles de granularidad y se complementan. La caché de módulos sustituye módulos completos por `.xcframework` precompilados antes de ejecutar la compilación, mientras que la caché de Xcode reutiliza los resultados de compilación durante la compilación.

> [!TIP]
> **En las máquinas de desarrollo, mantén `CompilationCache.noindex` al limpiar**
>
> De forma predeterminada, el almacén de la caché de compilación reside dentro de `DerivedData`, por lo que eliminar `DerivedData` lo descarta junto con los productos de compilación. En una máquina de desarrollo, es preferible eliminar solo los productos de compilación: así, la recompilación se reproduce desde el almacén en disco sin descargar nada.

## Configuración {#setup}

Si aún no tienes una cuenta y un proyecto en Tuist, puedes crearlos ejecutando:

```bash
tuist init
```

Una vez que tengas un archivo `Tuist.swift` que haga referencia a tu `fullHandle`, puedes configurar la caché para tu proyecto ejecutando:

```bash
tuist setup cache
```

Este comando crea un [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) para ejecutar un servicio local de caché al inicio, que el [sistema de compilación](https://github.com/swiftlang/swift-build) de Swift utiliza para compartir artefactos de compilación. Ejecútalo inicialmente en tu máquina de desarrollo y como parte de la configuración de cada trabajo de CI.

Para configurar la caché en CI, asegúrate de estar <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticado</.localized_link>.

### Actualización de los componentes de la caché {#updating-the-cache-components}

El proxy de caché utiliza un lanzador estable en lugar de una ruta anclada a la instalación de Tuist que ejecutó por última vez la configuración. Una vez instalado, `tuist setup cache` y `tuist generate` con caché habilitada avanzan un objetivo utilizable hacia versiones más recientes de Tuist. Por lo tanto, los proyectos anclados a una versión anterior de Tuist no revierten el proxy compartido. La generación solo actualiza un objetivo de lanzador existente: no instala un servicio, no autentica, no reemplaza el complemento ni reinicia el proxy. Las personalizaciones de complemento, proxy, socket o registro omiten el avance automático.

El proxy en ejecución adopta el nuevo objetivo solo después de al menos 30 segundos sin solicitudes de caché, sin solicitudes ni trabajo en segundo plano en curso y con sus colas de publicación vacías. Entonces sale y launchd inicia la CLI seleccionada, conservando los argumentos y el entorno de credenciales del servicio. Solo el proxy que realmente adopta el objetivo actualiza atómicamente el complemento en disco desde su paquete; la configuración no instala un complemento más reciente mientras el proxy anterior sigue vaciándose. Si falta el complemento instalado, una configuración explícita en reposo reinicia el proxy seleccionado para volver a intentar su actualización. Sigue habiendo un único proxy propietario del registro y de las colas. Un objetivo no disponible o cargas sin vaciar posponen el cambio en lugar de interrumpir las solicitudes activas. La actualización de credenciales sigue a la CLI seleccionada incluso antes del cambio, por lo que eliminar una instalación anterior de la CLI no deja cargas esperando a vaciarse.

Una instalación existente creada antes del lanzador estable necesita una migración explícita. Ejecuta lo siguiente cuando no haya compilaciones en ejecución:

```bash
tuist setup cache
```

Tras esa migración, actualizar Tuist y ejecutar tu habitual `tuist generate` es suficiente para avanzar el proxy y el complemento instalado; no necesitas volver a ejecutar la configuración para cada lanzamiento de la CLI. Aún se requiere una configuración explícita para seleccionar un Xcode diferente, incluido un Xcode actualizado en la misma ruta. La configuración puede reemplazar el servicio compartido cuando cambia su configuración, así que espera primero a que finalicen todas las compilaciones en la máquina. El proxy admite tanto el protocolo de complemento anterior como el actual, por lo que un complemento compatible ya cargado en Xcode sigue funcionando tras una actualización del proxy. Cierra completamente y vuelve a abrir Xcode para cargar el complemento más reciente, pero un complemento compatible cargado no requiere un reinicio inmediato. Regenera los proyectos cuando un lanzamiento cambie la configuración de compilación generada.

Mantén disponible la instalación de Tuist seleccionada: el lanzador la usa para el inicio, la configuración y la actualización de credenciales. Las instalaciones anteriores pueden eliminarse una vez que el lanzador haya avanzado. Si el ejecutable seleccionado se eliminó o ya no es ejecutable, `tuist setup cache` puede reparar el objetivo usando una instalación disponible, incluso una versión anterior, sin desmantelar primero la caché. Los alias estables de ejecutables se conservan entre actualizaciones del gestor de paquetes; los enlaces simbólicos se resuelven solo al comparar la identidad de la instalación. Al inicio, el proxy registra la versión realmente lanzada, incluidas las actualizaciones in situ o las reversiones deliberadas, mientras conserva la versión más alta utilizada para evitar que copias antiguas no relacionadas cambien una instalación utilizable.

Las CLI compiladas desde el código fuente sin una versión de lanzamiento y las configuraciones explícitas de `TUIST_CAS_PLUGIN_PATH` o `TUIST_CAS_PROXY_PATH` utilizan una configuración de lanzamiento explícita en lugar de la selección automática de versión. Vuelve a ejecutar la configuración después de recompilar esos componentes. La configuración comprueba su vigencia y deshabilita el avance gestionado del objetivo solo cuando su reemplazo está listo.

`tuist teardown cache` detiene el servicio antes de eliminar el objetivo del lanzador, mientras conserva el complemento estable para los proyectos existentes. Si no se logra detener el servicio, su lanzador permanece disponible para reiniciarlo e intentar otro desmontaje. La generación no puede recrear el servicio después de un desmontaje exitoso.

### Configurar ajustes de compilación de Xcode {#configure-xcode-build-settings}

Para un proyecto de Xcode existente, copia los ajustes de compilación impresos por `tuist setup cache` en los Build Settings de tu proyecto o en un archivo `.xcconfig` existente. El comando imprime la configuración para tu cuenta; no genera un archivo de configuración ni edita tu proyecto de Xcode. Mantén `$(inherited)` al extender `OTHER_SWIFT_FLAGS` para conservar otras opciones del compilador.

Los ajustes incluyen:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

Ten en cuenta que `COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` y `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` deben añadirse como **ajustes de compilación definidos por el usuario** porque no están expuestos directamente en la interfaz de ajustes de compilación de Xcode.

> [!NOTE]
> **Ruta del complemento**
>
> `libtuist_cas_plugin.dylib` es el complemento de caché de compilación que se distribuye con Tuist, junto al ejecutable `tuist`. `tuist setup cache` lo copia a `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`, y `COMPILATION_CACHE_PLUGIN_PATH` apunta a esa copia. La ruta es la misma en cada máquina y no cambia cuando actualizas Tuist, por lo que puedes confirmar el ajuste junto con tu proyecto. La configuración y el proxy recién iniciado actualizan la copia desde el paquete de Tuist seleccionado; ejecutar la configuración desde una copia antigua no revierte un complemento más nuevo.

> [!NOTE]
> **Un socket para cada proyecto**
>
> `tuist setup cache` instala un único proxy de caché por máquina, por lo que cada proyecto utiliza el mismo `COMPILATION_CACHE_REMOTE_SERVICE_PATH`. La opción de complemento `tuist-instance` es la que identifica el proyecto.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` es lo que comparte C y Objective-C**
>
> Es fácil interpretar este ajuste como "dónde reside el servicio de caché" y tratarlo como opcional. También es el interruptor que decide si se comparten o no C, Objective-C, módulos precompilados y cabeceras precompiladas: el sistema de compilación solo ejecuta su caché para ellos cuando se configura un servicio de caché remoto. Si lo omites, seguirás compartiendo las compilaciones de Swift, pero cada archivo C/Objective-C y cada módulo se recompilará en cualquier máquina que no haya compilado el proyecto antes.

> [!NOTE]
> **Búsquedas de caché concurrentes**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` ejecuta las búsquedas de caché remota que el sistema de compilación realiza para cada compilación junto con el resto de la compilación, en lugar de hacerlas de pocas en pocas en los carriles de ejecución de la compilación. Las compilaciones que fallan o restauran muchas compilaciones desde una caché distante finalizan antes.

También puedes especificar estos ajustes al ejecutar `xcodebuild` añadiendo las siguientes banderas, como:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Mapeo de prefijos en Xcode 27 y posteriores**
>
> En Xcode 27 y posteriores, `tuist setup cache` también imprime `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` y `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`. Hacen que las claves de caché de compilación sean independientes de dónde residen el proyecto y `DerivedData`. Añádelos como ajustes de compilación definidos por el usuario. Habilitarlos cambia cada clave de caché, por lo que la siguiente compilación vuelve a poblar la caché. `tuist generate` los configura por ti cuando `enableCaching` está activado.
>
> El compilador también escribe las rutas mapeadas en los datos de cobertura de código, y Xcode no puede resolverlas, por lo que un informe de cobertura omitiría todo el código fuente compilado con mapeo de prefijos. Los ajustes impresos, junto con los de `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`, desactivan el mapeo de prefijos en las compilaciones que recopilan cobertura de código. `tuist generate` hace lo mismo. Esas compilaciones siguen utilizando la caché de compilación, pero sus claves de caché dependen de las rutas del proyecto y de `DerivedData`.
>
> Cuando pasas estos ajustes a `xcodebuild` en la línea de comandos, encierra entre comillas simples los valores que contengan `$(...)`, como con `OTHER_SWIFT_FLAGS` arriba. De lo contrario, el shell los expande a cadenas vacías y el mapeo de prefijos se desactiva:
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **Proyectos generados**
>
> No es necesario configurar los ajustes manualmente si tu proyecto es generado por Tuist.
>
> En ese caso, todo lo que necesitas es añadir `enableCaching: true` a tu archivo `Tuist.swift`:
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### Cobertura con mapeo de prefijos {#coverage-with-prefix-mapping}

Por defecto, los proyectos generados desactivan el mapeo de prefijos para las compilaciones de cobertura para mantener funcionales los informes de cobertura de Xcode y `xccov`. Puedes activarlo para mantener las compilaciones de cobertura compartibles entre diferentes copias:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

La variable de entorno `TUIST_COVERAGE_PREFIX_MAPPING` (`1` o `0`) tiene prioridad sobre `prefixMapping`. Esta opción se aplica en Xcode 27 y posteriores y requiere `enableCaching`. La carga de cobertura de `tuist test` la admite: Tuist mide la ejecución con `llvm-cov`, que lee los fuentes con rutas mapeadas y los vincula de nuevo a los archivos de tu repositorio. El propio informe de cobertura de Xcode y `xccov` pueden seguir omitiendo esos fuentes, al igual que una carga que recurra al informe `xccov` del paquete de resultados porque falló la exportación de `llvm-cov`. Los valores de `#filePath` mapeados también pueden afectar a los tests que ubican fixtures en relación con los archivos de origen; resuelve los fixtures mediante rutas explícitas de copia en tiempo de ejecución en su lugar. Si procesas la cobertura tú mismo, empareja cada binario instrumentado con el `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` de su objetivo, que mapea los prefijos virtuales de vuelta a los directorios locales. No reutilices el mapa de un objetivo para cada binario cuando el mapeo por proyecto esté habilitado.

Los ajustes de prefijo de cobertura participan en los hashes de caché binaria y de testing selectivo porque controlan las rutas escritas en los artefactos de cobertura. Cambiar esta opción, o establecer `TUIST_COVERAGE_PREFIX_MAPPING` de forma diferente, invalida esos hashes incluso para compilaciones ordinarias. Mantén el valor consistente entre desarrolladores y trabajos de CI si deben compartir cachés binarias y resultados de testing selectivo.

### Depuración de proyectos generados {#debugging-generated-projects}

Los módulos nativos restaurados necesitan información de depuración enlazada, así como acceso a la caché de compilación. Tuist prepara los módulos Debug y Release con dSYMs y metadatos de identidad de origen por segmento, luego verifica los metadatos frente a los fuentes declarados por el consumidor antes de reemplazar un objetivo. Los metadatos faltantes o incompatibles conservan los fuentes de ese objetivo. Los fuentes `.generated(...)` generados por scripts tienen huellas digitales de declaración en lugar de sumas de verificación de contenido verificables, por lo que esos objetivos permanecen compilados desde el origen y no se publican en la caché de módulos nativos. Los accesores de recursos generados con sumas de verificación de contenido reales siguen siendo elegibles. La información de depuración no compatible omite la publicación del objetivo afectado sin bloquear productos no relacionados; la mutación de fuentes y la cancelación aún hacen fallar la preparación. El formato de caché cambia, por lo que los artefactos preparados por versiones anteriores necesitan volver a prepararse.

Para reemplazos verificados, Tuist prepara reubicaciones de origen en listas plist de UUID de dSYM propiedad del consumidor y enlaza complementos solo para depuración para código estático en caché. No reescribe los binarios en caché ni instala rutas de origen del productor en el mapa global persistente de LLDB. Los inicializadores explícitos del depurador y los ajustes del cargador de módulos siguen siendo autoritativos. Los símbolos de depuración y la reubicación de origen no reparan el acceso a archivos en tiempo de ejecución relativo al origen ni los informes de cobertura nativos de Xcode; la selección de variantes de cobertura y la exportación de LLVM siguen siendo características separadas.

Con `enableCaching: true`, Tuist configura los mapas de origen de LLDB para las acciones Run y Test. Cuando una acción tiene un inicializador personalizado de LLDB, Tuist escribe primero su mapa de origen resuelto y luego carga el inicializador personalizado para que pueda extender o anular el mapa. De lo contrario, carga `~/.lldbinit-Xcode` si el archivo existe, con fallback a `~/.lldbinit`, antes de reemplazar el mapa de origen. Carga solo un archivo de inicio, restaurando la configuración del depurador por usuario sin cargarlo dos veces. El reemplazo elimina las asignaciones obsoletas de ejecuciones anteriores y tiene prioridad sobre los mapas de origen del archivo de inicio; coloca las entradas del mapa de origen que deban conservarse en el inicializador personalizado de la acción. Otras configuraciones del archivo de inicio se conservan. Las rutas de búsqueda de módulos específicas de la caché de Tuist, la configuración del cargador y las banderas de Clang se aplican después y tienen prioridad sobre los valores de usuario para esas configuraciones. Los errores del archivo de inicio permanecen visibles sin detener la carga de comandos posteriores, y los comandos no se repiten. Esta preservación del inicializador también se aplica cuando Tuist configura la depuración para binarios restaurados desde la caché de módulos, incluso sin `enableCaching` y en versiones anteriores de Xcode.

En Xcode 27 y posteriores, los proyectos generados dejan desactivadas las asignaciones de prefijo por proyecto de Xcode (`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` y `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`) a menos que un proyecto las configure. Sus prefijos, como `/^src`, nombran un directorio diferente en cada proyecto, y LLDB los resuelve únicamente frente al proyecto del objetivo que se está depurando. Los fuentes se registran bajo prefijos de todo el espacio de trabajo: `/^root` para el directorio raíz de Tuist, `/^spm` para el directorio temporal del paquete Swift, y `/^intermediates` y `/^products` para los resultados de compilación. Cada uno nombra el mismo directorio en todos los proyectos, por lo que los puntos de interrupción se resuelven en fuentes de cualquier proyecto del espacio de trabajo.

Las rutas fuera de la raíz de Tuist no se asignan. Las claves de caché de un proyecto fuera de la raíz dependen de dónde se haya hecho checkout, por lo que otros checkouts y máquinas no encontrarán la caché para él. Para mantener sus claves independientes de la ubicación del checkout, activa las asignaciones por proyecto en el manifiesto de ese proyecto:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

Pasa estas configuraciones a ese `Project`. Cuando depures un objetivo de otro proyecto, LLDB no podrá encontrar los fuentes de ese proyecto. Las configuraciones base del proyecto en el manifiesto tienen prioridad sobre los valores xcconfig a nivel de proyecto, así que configúralas en el propio manifiesto.

Cambiar estas configuraciones modifica las claves de la caché de compilación, los hashes de la caché binaria y los hashes de pruebas selectivas, por lo que esas cachés necesitan volver a prepararse. Mantén la elección consistente en todo tu equipo.

### Política de subida a caché {#cache-upload-policy}

De forma predeterminada, el servicio de caché descarga y sube artefactos a la caché remota. Puedes controlar esto con la opción `xcodeCache` en tu archivo `Tuist.swift` para habilitar el modo de solo lectura, donde los artefactos se descargan pero nunca se suben:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Un patrón común es subir artefactos solo desde CI, donde las compilaciones son reproducibles, mientras se mantienen los entornos locales en modo de solo lectura. Puedes lograrlo usando `Environment.isCI`, que verifica la variable de entorno `CI` establecida por la mayoría de los proveedores de CI:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Con esta configuración, las compilaciones locales se benefician de artefactos en caché sin subirlos, mientras que las compilaciones de CI pueblan la caché para el resto del equipo.

La política de subida se registra por proyecto en la máquina que ejecuta `tuist setup cache`. Para cambiarla, actualiza `upload` y ejecuta `tuist setup cache` de nuevo, y también `tuist generate` si Tuist genera tu proyecto. Las subidas posteriores siguen la nueva política sin reiniciar la caché en esa máquina. Los trabajos para el mismo proyecto que se ejecutan en una máquina al mismo tiempo comparten su política, por lo que el `tuist setup cache` más reciente decide por todos ellos.

### Límite de tamaño de almacén {#store-size-limit}

Un almacén de caché de compilación crece con cada compilación. Para limitar los almacenes del proyecto, establece `storeSizeLimit` en tu archivo `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Mientras no se esté ejecutando ninguna compilación, Tuist revisa cada uno de los almacenes del proyecto cada 10 minutos. Elimina las salidas en caché más antiguas de un almacén una vez que las compilaciones más recientes han escrito aproximadamente la mitad del límite, por lo que el almacén se estabiliza alrededor del límite. Un almacén puede ser mayor que el límite mientras se ejecutan compilaciones, y un almacén que ya era mayor cuando estableciste el límite se reduce una vez que las nuevas compilaciones han escrito esa cantidad. Cuando varios proyectos usan el mismo almacén, como ocurre con su ubicación predeterminada, se aplica el menor de sus límites. El límite se aplica en cada máquina donde ejecutes `tuist setup cache`, así que ejecútalo de nuevo después de cambiar el límite.

### Hashes de la caché de módulos {#module-cache-hashes}

Las configuraciones de la caché de compilación no forman parte de los <.localized_link href="/guides/features/projects/hashing">hashes de la caché de módulos</.localized_link>. Tuist excluye del hash cada configuración de compilación `COMPILATION_CACHE_*` y cada bandera `-cas-plugin-option` con su valor. Activar o desactivar `enableCaching`, o cambiar la política de subida, mantiene los hashes de tus objetivos, por lo que los binarios de la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> que ya preparaste siguen siendo válidos. Puedes comparar compilaciones con y sin la caché de Xcode frente a la misma caché de módulos.

> [!NOTE]
> **Las configuraciones de asignación de prefijos tienen hash**
>
> En Xcode 27 y posteriores, `enableCaching: true` también establece `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` y las configuraciones `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`. Estas configuraciones forman parte de los hashes de la caché de módulos, por lo que en Xcode 27 y posteriores, activar o desactivar `enableCaching` cambia los hashes de tus objetivos.

### Reutilización de partes de salidas grandes {#reusing-parts-of-large-outputs}

La caché de Xcode puede reducir las transferencias mediante fragmentación definida por contenido. En lugar de tratar cada salida grande como no relacionada con versiones anteriores, divide la salida comprimida en límites determinados por su contenido. Después de una edición, los fragmentos coincidentes pueden reutilizarse incluso cuando sus desplazamientos hayan cambiado.

Las subidas envían solo los fragmentos que faltan en el servidor. Las descargas primero obtienen la acción exacta en caché y la receta de fragmentos de la salida, luego reutilizan los fragmentos verificados almacenados en la máquina local y recuperan las piezas faltantes. La salida reconstruida completa se verifica antes de restaurarla en la caché del compilador.

La caché de fragmentos de transferencia es independiente de `DerivedData`, por lo que sus fragmentos pueden sobrevivir a la limpieza de la caché de compilación o al reinicio del servicio de caché local. Es desechable y está limitada a como máximo un gibibyte de carga útil de fragmentos, con un archivo de preparación temporal adicional de como máximo dos mebibytes. Los fragmentos expulsados o dañados se vuelven a descargar cuando es necesario. Mantener la propia caché de compilación sigue siendo más rápido que reconstruir su contenido.

El cliente utiliza transferencias fragmentadas solo cuando el servidor anuncia compatibilidad. Los clientes antiguos aún pueden leer salidas completas, y los clientes conectados a servidores antiguos o no compatibles mantienen las transferencias ordinarias. Las salidas pequeñas siguen utilizando la ruta existente de salida completa.

Esto reduce los bytes transferidos, no la invalidación del compilador. Cambiar un archivo fuente puede seguir requiriendo compilación; la fragmentación ayuda a publicar o restaurar la salida resultante. Los ahorros dependen de la salida y de la edición, y una máquina fría sin fragmentos coincidentes debe descargar toda la salida.

### Integración continua {#continuous-integration}

Para habilitar la caché en tu entorno de CI, debes ejecutar el mismo comando que en los entornos locales: `tuist setup cache`.

Para la autenticación, puedes usar <.localized_link href="/guides/server/authentication#oidc-tokens">autenticación OIDC</.localized_link> (recomendada para proveedores de CI compatibles) o un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> mediante la variable de entorno `TUIST_TOKEN`.

Un ejemplo de flujo de trabajo para GitHub Actions usando autenticación OIDC:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

Consulta la <.localized_link href="/guides/integrations/continuous-integration">guía de Integración Continua</.localized_link> para ver más ejemplos, incluida la autenticación basada en tokens y otras plataformas de CI como Xcode Cloud, CircleCI, Bitrise y Codemagic.

### Almacén de caché de compilación en CI {#compilation-cache-store-on-ci}

El almacén de caché de compilación es el directorio local donde Xcode guarda las salidas de compilación. La configuración de compilación `COMPILATION_CACHE_CAS_PATH` establece su ubicación, que por defecto es `CompilationCache.noindex` dentro de `DerivedData`.

#### Almacén con estado {#stateful-store}

Para mantener un almacén entre compilaciones, apunta `COMPILATION_CACHE_CAS_PATH` (y `TUIST_COMPILATION_CACHE_CAS_PATH` para `tuist cache`) a una ruta duradera y limita su tamaño con un [límite de tamaño del almacén](#store-size-limit).

## Solución de problemas {#troubleshooting}

### Las compilaciones advierten que el proxy de caché de Xcode falló {#cas-proxy-failed}

Si una compilación muestra una advertencia como la siguiente, que Xcode precede con `CAS error:` o `CAS operation failed:` dependiendo de qué compilación encuentre el fallo primero:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

entonces la caché de compilación no pudo alcanzar el proxy de caché local que instala `tuist setup cache`. La compilación sigue teniendo éxito, pero las compilaciones afectadas no obtienen aciertos de caché remota, por lo que se ejecuta como una compilación con una caché vacía. Sus subidas se mantienen en disco y se envían una vez que el proxy vuelve a manejar solicitudes: más tarde en la misma compilación si regresa a tiempo, o de lo contrario durante la siguiente compilación en la misma máquina. Una máquina de CI que se descarta después del trabajo las pierde. La advertencia aparece una vez por compilación, en el navegador de problemas de Xcode y en la salida de `xcodebuild`.

Para comprobar si el proxy está en ejecución, busca un proceso escuchando en el socket nombrado en la advertencia:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

Si el comando no imprime nada, ejecuta `tuist setup cache` para iniciar el proxy de nuevo. En CI, ejecuta `tuist setup cache` antes de cualquier invocación de `xcodebuild` en cada trabajo.

### Las compilaciones son extremadamente lentas y emiten advertencias de `CAS error: deadlineExceeded` {#cas-deadline-exceeded}

Si tus compilaciones tardan mucho más de lo esperado y el registro de compilación de Xcode está lleno de advertencias como:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

o:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

entonces `COMPILATION_CACHE_REMOTE_SERVICE_PATH` apunta a un socket en el que nadie está escuchando, usualmente el socket por proyecto (`~/.local/state/tuist/<org>_<project>.sock`) que configuraban versiones anteriores de Tuist. Tuist ya no sirve ese socket. Xcode reintenta la conexión en cada solicitud de caché de compilación en lugar de fallar rápidamente, lo que puede hacer que una compilación tarde una hora o más, y Tuist no puede cambiar ese comportamiento.

Para solucionarlo:

- **Proyectos generados**: ejecuta `tuist generate` de nuevo.
- **Otros proyectos**: reemplaza las configuraciones de compilación `COMPILATION_CACHE_*` con las que imprime `tuist setup cache`, como se describe en [Configurar ajustes de compilación de Xcode](#configure-xcode-build-settings).

Si no estás usando la caché de Xcode, elimina las configuraciones de compilación `COMPILATION_CACHE_*` y ejecuta `tuist teardown cache`.

### `uploaded CAS output` aparece localmente aunque las subidas estén deshabilitadas {#uploaded-cas-output-with-upload-disabled}

Cuando se establece `xcodeCache: .xcodeCache(upload: false)` (o `upload: Environment.isCI` en una máquina que no es de CI), aún puedes ver `note: uploaded CAS output ...` en el registro de compilación. `xcodebuild` no tiene forma de omitir esas llamadas, por lo que Tuist las recibe, pero no publica nada en el servidor de Tuist. Las métricas del panel tienen esto en cuenta, por lo que no se informa tráfico de subida espurio.
