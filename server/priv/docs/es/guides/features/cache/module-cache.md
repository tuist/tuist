---
{
  "title": "Caché de módulos",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Almacena en caché los binarios compilados y compártelos con tu equipo mediante la caché de módulos de Tuist."
}
---

# Caché de módulos {#module-cache}

> [!WARNING]
> **Requisitos**
>
> - Un <.localized_link href="/guides/features/projects">proyecto generado</.localized_link>. La caché de módulos lee el grafo del proyecto que Tuist mantiene tras `Project.swift` para calcular hashes de los targets y sustituir sus binarios.

Tuist Module Cache ofrece una forma potente de optimizar los tiempos de compilación al almacenar en caché tus módulos como binarios (`.xcframework`s) y compartirlos entre distintos entornos. Esta capacidad te permite aprovechar binarios generados previamente, reduciendo la necesidad de recompilar y acelerando el proceso de desarrollo.

> [!TIP]
> **Combínalo con la caché de Xcode**
>
> La caché de módulos y la <.localized_link href="/guides/features/cache/xcode-cache">caché de Xcode</.localized_link> son complementarias porque operan a distintos niveles de granularidad. La caché de módulos reemplaza módulos completos por `.xcframework`s precompilados antes de ejecutar la compilación, mientras que la caché de Xcode reutiliza los resultados de compilación durante la compilación.
>
> Los ajustes de la caché de compilación no forman parte de los hashes de la caché de módulos, por lo que activar o desactivar la caché de Xcode conserva los binarios que ya has calentado. En Xcode 27 y versiones posteriores, se incluyen en el hash los ajustes de mapeo de prefijos asociados. Consulta <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">hashes de la caché de módulos</.localized_link>.

## Calentamiento {#warming}

Tuist <.localized_link href="/guides/features/projects/hashing">utiliza hashes</.localized_link> de forma eficiente para cada target del grafo de dependencias a fin de detectar cambios. Con estos datos, compila y asigna identificadores únicos a los binarios derivados de esos targets. Durante la generación del grafo, Tuist sustituye sin interrupciones los targets originales por sus versiones binarias correspondientes.

Esta operación, conocida como *"calentamiento"*, genera binarios para uso local o para compartir con compañeros de equipo y entornos de CI a través de Tuist. El proceso de calentar la caché es sencillo y puede iniciarse con un comando simple:

```bash
tuist cache
```

El comando reutiliza binarios para acelerar el proceso.

Si un binario no se puede subir, el comando sube el resto, termina con un estado distinto de cero y enumera los targets que no se subieron. Los binarios en la caché local de una máquina cuentan como almacenados en caché; para volver a subirlos desde la misma máquina, ejecuta `tuist clean binaries` antes de calentar. Usa `--no-upload` para guardar los binarios solo en la caché local.

### Selección de destino {#destination-selection}

Usa `--destination simulator` o `--destination device` para almacenar en caché y generar para un único destino:

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

El valor predeterminado es `all`, que conserva todos los destinos admitidos por tus targets, incluido Mac Catalyst. Una ejecución posterior de `tuist cache` reutiliza las particiones almacenadas en caché y compila solo los SDK faltantes. La generación normal conserva las fuentes de un módulo si falta alguna partición requerida.

La generación restringida limita los targets de origen al destino seleccionado y conserva los targets nativos de macOS, incluidas las macros. Ninguno de los modos restringidos incluye Mac Catalyst. Vuelve a generar con `--destination all` para restaurar todos los destinos.

El almacenamiento en caché por particiones admite iOS y macOS con arquitecturas estándar. Otras plataformas, arquitecturas personalizadas y productos no compatibles mantienen el almacenamiento en caché de artefactos completos. La caché de módulos heredada requiere `--destination all`.

### Admisión de subida remota {#remote-upload-admission}

La caché de módulos moderna usa REAPI. Cuando una caché saturada rechaza temporalmente una subida con `RESOURCE_EXHAUSTED`, Tuist aplica retroceso con jitter, respeta los retrasos mínimos estándar de `google.rpc.RetryInfo` y reintenta dentro de un presupuesto de espera acotado. La admisión de subida permite como máximo seis reintentos por llamada. Cada operación de subida de blobs comparte un único presupuesto acumulado de retroceso de 60 segundos entre sus comprobaciones de presencia, subidas por lotes y escrituras en streaming; las esperas concurrentes consumen el presupuesto, por lo que los rechazos repetidos no conceden a cada blob en cola otro minuto de reintentos. Las transferencias exitosas no consumen este presupuesto y no se cancelan cuando se agota. La publicación de resultados de acciones tiene su propio presupuesto acotado. El retraso exponencial comienza en un segundo y crece hasta 30 segundos antes del jitter proporcional. Si el retraso requerido por el servidor supera el presupuesto restante, Tuist falla en lugar de reintentar antes de lo indicado. La cancelación interrumpe el retroceso y las lecturas de caché conservan reintentos breves para que la sobrecarga no detenga la generación.

Estos valores predeterminados también ayudan a versiones antiguas de Kura sin indicaciones de reintento. Los reintentos más largos absorben contención temporal, no sobrecarga sostenida: reduce el [límite de concurrencia de caché](#cache-concurrency-limit) en trabajos de calentamiento o aumenta la capacidad del servidor si los rechazos persisten. Consulta [dimensionamiento de subidas de Kura](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing) para estimaciones de memoria de pods y métricas de admisión.

### Selección de configuración {#configuration-selection}

Al calentar la caché sin pasar `--configuration`, Tuist selecciona la configuración de compilación a usar en el siguiente orden:

1. El [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration) establecido en `Project.Options.generationOptions` de tu manifiesto, si existe.
2. De lo contrario, la primera configuración de compilación de variante `debug`, ordenada alfabéticamente por nombre.

Para calentar la caché para una configuración específica, pásala explícitamente:

```bash
tuist cache --configuration Release
```

## Uso {#usage}

De forma predeterminada, cuando los comandos de Tuist requieren generar el proyecto, sustituyen automáticamente las dependencias por sus equivalentes binarios de la caché, si están disponibles. Además, si especificas una lista de targets en los que centrarte, Tuist también reemplazará cualquier target dependiente por sus binarios almacenados en caché, siempre que estén disponibles. Para quienes prefieren otro enfoque, existe una opción para desactivar por completo este comportamiento mediante una flag específica:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> La caché de binarios es una funcionalidad diseñada para flujos de trabajo de desarrollo, como ejecutar la app en un simulador o dispositivo, o ejecutar tests. No está pensada para compilaciones de release. Al archivar la app, genera un proyecto con las fuentes usando `--cache-profile none`.

## Perfiles de caché {#cache-profiles}

Tuist admite perfiles de caché para controlar con qué agresividad se reemplazan los targets por binarios almacenados en caché al generar proyectos.

- Integrados:
  - `only-external`: reemplaza solo dependencias externas (predeterminado del sistema)
  - `all-possible`: reemplaza tantos targets como sea posible (incluidos targets internos)
  - `none`: nunca reemplaza por binarios almacenados en caché

Selecciona un perfil con `--cache-profile` en `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **Flag obsoleta**
>
> La flag `--no-binary-cache` está obsoleta. Usa `--cache-profile none` en su lugar. La flag obsoleta sigue funcionando por compatibilidad hacia atrás.

Precedencia al resolver el comportamiento efectivo (de mayor a menor):

1. `--cache-profile none`
2. Enfoque en targets (pasar targets a `generate`) → perfil `all-possible`
3. `--cache-profile <value>`
4. Predeterminado de la configuración (si está establecido)
5. Predeterminado del sistema (`only-external`)

## Productos compatibles {#supported-products}

Solo los siguientes productos de target pueden almacenarse en caché con Tuist:

- Frameworks (estáticos y dinámicos), incluidos frameworks de soporte para tests que dependen de [XCTest](https://developer.apple.com/documentation/xctest) o Swift Testing
- Librerías (estáticas y dinámicas), incluidas librerías de soporte para tests que dependen de XCTest o Swift Testing
- Bundles
- Macros de Swift

Los bundles de test siguen excluidos de la caché de módulos. Esto significa que los targets `unitTests` y `uiTests` no se almacenan en caché como binarios, pero los targets regulares de framework y librería de los que dependen los tests sí pueden almacenarse en caché aunque enlacen con XCTest o Swift Testing.

Las `.xcframework` de librería almacenadas en caché conservan los metadatos necesarios para que los proyectos generados las importen, incluidos los módulos de Swift y las cabeceras públicas de C/Objective-C cuando el target fuente declara cabeceras públicas.

> [!NOTE]
> **Dependencias upstream**
>
> Cuando un target no es cacheable, hace que los targets upstream tampoco lo sean. Por ejemplo, si tienes el grafo de dependencias `A > B`, donde A depende de B, si B no es cacheable, A tampoco lo será.

## Analíticas {#analytics}

Abre **Caché de módulos → Módulos** en el panel de tu proyecto para encontrar módulos con fallos frecuentes. Selecciona el entorno que quieres mejorar, como **CI**, y un intervalo de fechas. La vista general muestra aciertos y fallos de caché, y módulos con fallos; al abrir un módulo se muestra su historial y la razón asignada a cada observación.

El desplegable **Fallos** selecciona un recuento y una explicación para una razón. El gráfico muestra la distribución de las cuatro razones. En la página de un módulo, usa el filtro **Razón** del historial para inspeccionar ocurrencias individuales. Pasa el cursor sobre una etiqueta de razón, o enfócala con el teclado, para ver su definición.

### Razones de fallo {#miss-reasons}

| Razón | Qué significa |
| --- | --- |
| **Cambiado** | Las entradas comparadas propias del módulo han cambiado. Estas incluyen hashes de archivos, ajustes de compilación, la configuración resuelta y el identificador del compilador. Una edición del código fuente es solo una posible causa. |
| **Upstream** | Las entradas comparadas propias del módulo se mantienen igual, pero el hash de su dependencia o paquete externo ha cambiado. Los archivos fuente del módulo pueden permanecer intactos. |
| **Frío** | No hay una observación anterior del módulo con la que comparar, o las entradas reportadas no explican el fallo y no hay evidencia suficiente de disponibilidad remota previa. Frío no prueba que el módulo nunca se haya almacenado en caché. |
| **Evictado** | La clave de caché exacta tuvo previamente un acierto remoto en el mismo proyecto en el mismo endpoint de caché registrado, pero ahora falla. |

Para los fallos etiquetados como **Evictado**, el artefacto se descargó previamente de la caché remota pero no pudo reutilizarse esta vez. La evicción es la causa más probable, aunque los fallos de acceso o descarga también pueden explicar el fallo. Tuist solo asigna esta etiqueta cuando encuentra un acierto remoto anterior; los fallos previos y los aciertos locales no son suficientes.

Por ejemplo:

| Escenario | Clasificación |
| --- | --- |
| Un módulo falla sin observación previa ni acierto remoto válido | Frío |
| A cambia; B depende de A y C depende de B; las tres claves cambian | A es Cambiado; B y C son Upstream |
| La versión del compilador cambia después del calentamiento, con fuentes y ajustes sin cambios | Los fallos afectados son Cambiados cuando ambas observaciones reportan las entradas del compilador |
| Una clave exacta se descargó remotamente y luego falla después de que su artefacto sea evictado | Evictado, cuando el acierto anterior califica como evidencia |
| Una clave falla repetidamente y nunca se calentó con éxito | Puede permanecer Frío |

Las razones describen observaciones; no son etiquetas permanentes asociadas a una clave. Por ejemplo, el primer fallo tras una actualización del compilador puede ser Cambiado, mientras que un fallo posterior para esa nueva clave puede ser Frío si nunca se observó como disponible remotamente.

### Mejorar la tasa de aciertos de caché {#improving-cache-hit-rate}

1. **Elige una línea base consistente.** Comienza con CI y un rango de fechas representativo. Ordena los módulos por fallos, luego considera sus tasas de acierto, dependientes y coste de compilación. Arreglar una dependencia costosa que falla con frecuencia puede ahorrar más tiempo que mejorar la tasa de acierto de un módulo diminuto. Compara el mismo entorno y cargas de trabajo similares después de realizar un cambio.
2. **Investiga los fallos Cambiados.** Abre las ejecuciones relevantes y compara sus claves completas y entradas reportadas. Alinea los trabajos de calentamiento y consumo en la versión de Xcode/compilador, configuración y destinos de destino previstos. Vuelve a calentar después de cambios intencionados. Si archivos generados volátiles o ajustes dependientes del entorno invalidan módulos otherwise estables, investiga esas entradas. Mantén en el hash las entradas que afectan a la compatibilidad binaria.
3. **Sigue los fallos Upstream hasta la dependencia cambiada.** Inspecciona su historial para encontrar el cambio directo. Calentar las claves resultantes puede restaurar la reutilización. Si una implementación que cambia con frecuencia invalida muchos dependientes costosos, considera módulos más pequeños o interfaces estables como se describe en [Eficiencia](#efficiency).
4. **Comprueba la cobertura de calentamiento para fallos Fríos.** Verifica que el calentamiento selecciona los módulos requeridos, usa la configuración y el entorno del trabajo de consumo, y sube los artefactos con éxito. Comprueba las claves completas usadas por los trabajos de CI reales. Si el calentamiento y el consumo solicitan claves diferentes, inspecciona las entradas de hashing antes de asumir que la caché fue evictada. Los fallos repetidos sin una subida exitosa anterior son posibles incluso cuando las fuentes del módulo no han cambiado.
5. **Usa la evidencia para los fallos Evictados.** Confirma la clave y el endpoint de la ejecución de consumo, luego inspecciona las advertencias de caché de esa ejecución y el resultado de la subida del trabajo de calentamiento. Comprueba la retención o evicción cuando corresponda. Vuelve a calentar los artefactos necesarios y verifica un acierto posterior. Si siguen fallando, comparte los enlaces y registros de las ejecuciones relevantes con soporte.

Para una comparación de hashes, ejecuta esto en cada entorno relevante, usando la configuración que pretendes calentar y consumir:

```bash
tuist hash cache --configuration Debug --verbose
```

Compara el hash completo del módulo y el bloque de componentes. Repetir el comando en la misma máquina sin cambios debería producir normalmente el mismo resultado; compara los entornos reales de calentamiento y consumo para investigar una discrepancia. Ninguno de los comandos necesita acertar en la caché. Consulta <.localized_link href="/guides/features/projects/hashing#debugging">diagnóstico de hashing</.localized_link> para más comprobaciones.

## Eficiencia {#efficiency}

El nivel de eficiencia que se puede lograr con la caché binaria depende en gran medida de la estructura del grafo. Para obtener los mejores resultados, recomendamos lo siguiente:

1. Evita grafos de dependencias muy anidados. Cuanto más superficial sea el grafo, mejor.
2. Define dependencias con objetivos de protocolo/interfaz en lugar de implementación, e inyecta las implementaciones como dependencias desde los objetivos de nivel superior.
3. Divide los objetivos modificados con frecuencia en otros más pequeños cuya probabilidad de cambio sea menor.

Las sugerencias anteriores forman parte de <.localized_link href="/guides/features/projects/tma-architecture">La Arquitectura Modular</.localized_link>, que proponemos como una forma de estructurar tus proyectos para maximizar los beneficios no solo de la caché binaria, sino también de las capacidades de Xcode.

## Configuración recomendada {#recommended-setup}

Recomendamos tener un trabajo de CI que **se ejecute en cada commit en la rama principal** para calentar la caché. Esto asegurará que la caché contenga siempre binarios para los cambios en `main`, de modo que las compilaciones locales y de ramas de CI se basen incrementalmente en ellos.

> [!TIP]
> **Mantén el calentamiento de caché aislado**
>
> Ejecuta `tuist cache` en un paso de CI dedicado sin pasos posteriores que dependan del espacio de trabajo generado. Dado que `tuist cache` modifica el espacio de trabajo con fines de construcción de caché, cualquier paso de CI que necesite el espacio de trabajo debe ejecutar `tuist generate` primero para obtener un espacio de trabajo nuevo y utilizable.

> [!TIP]
> **El calentamiento de caché usa binarios**
>
> El comando `tuist cache` también hace uso de la caché binaria para acelerar el calentamiento.

A continuación se muestran algunos ejemplos de flujos de trabajo comunes:

### Un desarrollador comienza a trabajar en una nueva funcionalidad {#a-developer-starts-to-work-on-a-new-feature}

1. Crea una nueva rama desde `main`.
2. Ejecuta `tuist generate`.
3. Tuist obtiene los binarios más recientes de `main` y genera el proyecto con ellos.

### Un desarrollador envía cambios upstream {#a-developer-pushes-changes-upstream}

1. La pipeline de CI ejecutará `xcodebuild build` o `tuist test` para compilar o probar el proyecto.
2. El flujo de trabajo obtendrá los binarios más recientes de `main` y generará el proyecto con ellos.
3. Luego compilará o probará el proyecto incrementalmente.

## Configuración {#configuration}

### Límite de concurrencia de caché {#cache-concurrency-limit}

Establece `TUIST_CACHE_CONCURRENCY_LIMIT` en un entero positivo para limitar tanto las descargas como las subidas. Por ejemplo, reduce la carga en una caché autoalojada pequeña en trabajos de calentamiento:

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

Cuando no está establecido, las subidas REAPI usan ocho tareas de transferencia. Las descargas usan ocho cuando cualquier blob requiere ByteStream y 32 para planes solo por lotes. La ruta de caché HTTP heredada tiene por defecto 100; ese valor por defecto no se aplica a REAPI. Los valores inválidos, incluido el documentado anteriormente `none`, mantienen los valores por defecto en lugar de eliminar los límites. Usa `unset TUIST_CACHE_CONCURRENCY_LIMIT` para restaurar los valores por defecto.

Los límites se aplican por operación de transferencia, no globalmente entre operaciones o trabajos de CI. Tres calentamientos simultáneos con un límite de dos pueden tener seis subidas activas contra la misma caché. Los trabajos de consumo pueden dejar la variable sin establecer para mantener el paralelismo de descarga por defecto.

### Directorio scratch de calentamiento de caché {#cache-warm-scratch-directory}

Por defecto, `tuist cache` crea un directorio scratch temporal para intermedios de compilación y artefactos de caché ensamblados, y luego lo elimina cuando finaliza el calentamiento de la caché. Para mantener esos archivos bajo un directorio que tú gestionas, establece `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`.

La ruta puede ser absoluta o relativa al directorio de trabajo actual. Tuist crea el directorio cuando no existe. Si ya existe, debe ser un directorio vacío.

Cuando esta variable de entorno está establecida, Tuist deja el directorio y su contenido en su lugar después de que finaliza el comando. El llamador es responsable de limpiarlo antes del próximo calentamiento de caché. Cuando la variable no está establecida, Tuist continúa usando y eliminando un directorio temporal.

Tuist rechaza un directorio scratch propiedad del llamador cuando es necesario calentar un objetivo de compilación externo. Los scripts de compilación externos controlan sus propias ubicaciones de salida, por lo que Tuist no puede garantizar que esas salidas permanezcan dentro del directorio scratch.

### Cobertura de código {#code-coverage}

> [!NOTE] EARLY ACCESS
> La cobertura de código con la caché de módulos está en acceso anticipado. Los comandos solo leen y calientan los binarios instrumentados descritos a continuación cuando `TUIST_FEATURE_FLAG_COVERAGE=1` está establecido.

Un objetivo de la caché de módulos es un binario precompilado, y una ejecución de tests mide su código solo cuando ese binario se compiló con contadores de cobertura. Activa la cobertura para tu proyecto en `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

Con `enabled`, cada comando y cada entorno lee una variante instrumentada de la caché para los objetivos propios de tu proyecto, por lo que un único calentamiento en CI sirve tanto para entornos de CI como para máquinas locales:

| Comando | Objetivos de tu proyecto | Paquetes externos |
| --- | --- | --- |
| `tuist cache` (configuración Debug) | Calienta binarios instrumentados | Calienta binarios normales |
| `tuist cache` (configuración Release) | Calienta binarios normales | Calienta binarios normales |
| `tuist hash cache` | Imprime las claves instrumentadas | Imprime las claves normales |
| `tuist generate` | Lee binarios instrumentados | Lee binarios normales |
| `tuist test` | Lee binarios instrumentados | Lee binarios normales |

La opción se aplica a cada configuración que Xcode trata como Debug. Las compilaciones Release nunca están instrumentadas. Tuist también enlaza el runtime de perfilado en esas configuraciones (`CLANG_COVERAGE_MAPPING_LINKER_ARGS`), por lo que las compilaciones que no recopilan cobertura siguen enlazando los binarios instrumentados, y activa la cobertura en la acción de test de los esquemas que genera automáticamente y de los esquemas que defines dejando `coverage` sin establecer.

Un esquema que definas sigue la opción a menos que establezca la cobertura por sí mismo: `.options(coverage: false)` la mantiene desactivada y `.options(coverage: true)` la mantiene activada independientemente de lo que diga la opción. Los planes de test deciden la cobertura por sí mismos, y `-enableCodeCoverage` sigue anulando una ejecución, como en Xcode. Una ejecución que lee binarios instrumentados sin recopilar cobertura compila y prueba normalmente. Cuando una ejecución recopila cobertura pero los objetivos de tu proyecto provienen de la caché como binarios normales, Tuist advierte que su cobertura no se mide.

La variable de entorno `TUIST_COVERAGE_ENABLED` (`1` o `0`) tiene prioridad sobre `coverage: .coverage(enabled:)`. Establécela para todo un entorno, como un flujo de trabajo de CI, en lugar de para un solo comando, para que los comandos que calientan la caché y los que la lean estén de acuerdo.

`prefixMapping` (consulta la <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">caché de Xcode</.localized_link>) tiene su propia anulación: la variable de entorno `TUIST_COVERAGE_PREFIX_MAPPING` (`1` o `0`) tiene prioridad sobre `coverage: .coverage(prefixMapping:)`.

Anular a desactivado lee la variante normal, que una caché calentada con cobertura activada no llena, por lo que esos objetivos se compilan desde el código fuente. Un calentamiento Release siempre calienta binarios normales.

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` y `prefixMapping` cambian la configuración de compilación y las claves de caché de los objetivos de tu proyecto, así como los hashes de testing selectivo de sus objetivos de test. Establece el mismo valor en cada máquina que comparta la caché y no los derives del entorno (por ejemplo, de `Environment.isCI`): un valor diferente entre CI y máquinas locales les da claves distintas. Lo mismo ocurre con las variables de entorno: una ejecución con `TUIST_COVERAGE_ENABLED=0` no reutiliza los binarios ni los resultados de testing selectivo de ejecuciones con cobertura activada.

Ten en cuenta:

- Los binarios instrumentados son más grandes: alrededor de un 20–30 % para archivos estáticos y bibliotecas dinámicas. Las compilaciones Debug se ejecutan a la misma velocidad.
- El informe de cobertura de Xcode nunca muestra código que provino de la caché, con o sin esta opción. La subida de cobertura de Tuist sí la mide. Para ver la cobertura de un objetivo en Xcode, céntrate en él con `tuist generate <target>` para que se compile desde el código fuente.

## Solución de problemas {#troubleshooting}

### No usa binarios para mis objetivos {#it-doesnt-use-binaries-for-my-targets}

Asegúrate de que los <.localized_link href="/guides/features/projects/hashing#debugging">hashes sean deterministas</.localized_link> entre entornos y ejecuciones. Esto puede ocurrir si el proyecto tiene referencias al entorno, por ejemplo, a través de rutas absolutas. Puedes usar el comando `diff` para comparar los proyectos generados por dos invocaciones consecutivas de `tuist generate` o entre entornos o ejecuciones.

Asegúrate también de que el objetivo no dependa, ni directa ni indirectamente, de un <.localized_link href="/guides/features/cache/module-cache#supported-products">objetivo no cacheable</.localized_link>.

### Símbolos faltantes {#missing-symbols}

Al usar fuentes, el sistema de compilación de Xcode, a través de Derived Data, puede resolver dependencias que no están declaradas explícitamente. Sin embargo, cuando confías en la caché binaria, las dependencias deben declararse explícitamente; de lo contrario, es probable que veas errores de compilación cuando no se encuentren símbolos. Para depurar esto, recomendamos usar el comando <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> y configurarlo en CI para prevenir regresiones en el enlazado implícito.
