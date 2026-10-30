---
title: Configuración avanzada de la caché de Elixir
titleTemplate: ":title · Caché · Guías · Tuist"
description: Configura entradas de compilación adicionales, selección de dependencias y reutilización portátil.
---

# Configuración avanzada de la caché de Elixir

Comienza con <.localized_link href="/guides/features/cache/elixir">la guía de configuración de la caché de Elixir</.localized_link>. Las opciones siguientes solo son necesarias cuando tu proyecto tiene entradas de compilación adicionales, excepciones de dependencias o rutas de checkout diferentes.

## Seleccionar dependencias

`cache: true` almacena en caché las dependencias compatibles automáticamente. Una lista de palabras clave tiene la misma selección automática, con anulaciones opcionales:

```elixir
cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
```

Para limitar la caché a dependencias específicas:

```elixir
cache: [dependencies: [:nimble_options, :nimble_parsec]]
```

`dependencies: :all` selecciona explícitamente todas las dependencias compatibles; `dependencies: []` no selecciona ninguna. `exclude:` tiene prioridad sobre cualquiera de las selecciones. Omitir `cache`, o establecerlo como `false` o `nil`, desactiva la caché.

Las dependencias compatibles se obtienen a través de Hex o Git y utilizan el pipeline estándar del compilador Mix con fuentes de Elixir/Erlang, o la compilación pura-BEAM ordinaria de rebar3. Las dependencias de Mix también pueden reutilizar artefactos cuando sus dependencias upstream usan rebar3. La configuración de Rebar, los archivos de fuente/cabecera y la huella digital del ejecutable de rebar3 participan en las claves. Los metadatos empaquetados de `ebin/*.app` y los Makefiles pasivos también son compatibles. Los scripts de configuración de Rebar ya han sido evaluados por Mix antes de la búsqueda; su fuente y configuración efectiva entran en las claves. Los scripts de fuente de la aplicación (`*.app.src.script`) son evaluados más tarde por rebar3 y requieren un contrato de builder auditado, al igual que los plugins de build y los hooks de compilación. Si falta el launcher de rebar3, se instala antes de generar la huella digital, utilizando el instalador normal de Mix; los workers fríos aún necesitan acceso a ese instalador.

Los trazadores personalizados, los symlinks de origen, las raíces de umbrella y las cadenas que contienen dependencias locales se compilan normalmente. Las propias dependencias de bootstrap de Tuist también se compilan normalmente en workers fríos. La elegibilidad estructural no prueba que el código de compilación arbitrario sea hermético.

## Declarar entradas adicionales

Los árboles de origen, las identidades bloqueadas de las dependencias, las fuentes upstream, los BEAMs y recursos, las banderas de runtime/opcionales/aplicación de las dependencias, los metadatos resueltos de la aplicación, la configuración efectiva explícita de la aplicación, las opciones del compilador (incluidas las opciones del lexer y parser), el entorno y target de Mix, y la identidad de la toolchain se incluyen automáticamente. Las variables `env:` y `system_env:` específicas de cada dependencia entran en la clave y la configuración se evalúa bajo ese entorno. Los valores predeterminados de la aplicación entran a través de las entradas de origen, no del estado de carga de la VM.

Para las dependencias que leen archivos fuera de su árbol de origen o variables de entorno adicionales en tiempo de compilación, declara esas entradas:

```elixir
cache: [
  inputs: ["schemas", "config/compiler-input.json"],
  env: ["YOUR_COMPILER_OPTION"]
]
```

Las macros de Elixir y los cuerpos de los módulos pueden leer archivos arbitrarios, el entorno, las rutas de código ambientales, las respuestas de red y la hora. Tuist no descubre automáticamente estas lecturas. Cambiar entradas no declaradas puede producir salidas obsoletas. Excluye las dependencias con compilación dependiente del tiempo/red o efectos secundarios que deben ejecutarse en cada build; usa `dependencies:` para una lista de permisos de dependencias auditada cuando necesites un control más estricto.

Las variables estándar del compilador/runtime (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`, `ERL_AFLAGS`, `ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH` y `MIX_ARCHIVES`) se capturan automáticamente. La identidad de la toolchain incluye la build de Elixir, la versión completa de OTP cuando está disponible, ERTS, el bytecode del compilador, el SO/versión, la arquitectura, el tamaño de palabra y el orden de bytes. El contexto efectivo se captura antes de cada búsqueda. Los modelos de entrada por dependencia pueden compartirse para la planificación de la búsqueda dentro de una preparación; la compilación borra el plan y la restauración invalida los registros de la aplicación instalada. La instalación y publicación por etapas siempre verifican entradas nuevas sin reutilizar el plan de búsqueda. Un fallo de búsqueda también captura una clave nueva antes de la compilación. Las entradas cambiadas rechazan un acierto por etapas en lugar de instalar código construido para las entradas anteriores.

Las claves utilizan codificación determinista de términos y recorrido ordenado del sistema de archivos. Las declaraciones de builders no ordenadas y los conjuntos de entradas declarados se ordenan y deduplican; las opciones del compilador ordenadas conservan su orden. Importan los contenidos de los archivos, los nombres, los bits de ejecución y las rutas faltantes, no las marcas de tiempo del sistema de archivos. Las declaraciones de archivos no modelan la propiedad, las marcas de tiempo ni otros metadatos del sistema de archivos; excluye los builders que derivan salidas de esos valores. Los manifiestos del compilador upstream se excluyen como contabilidad incremental; el código que lee deliberadamente sus contenidos debe declararlos como entradas adicionales. La configuración de Regex utiliza su fuente y opciones, nunca referencias compiladas locales a la VM. Otros valores opacos de runtime omiten la caché. Los modelos de clave actualizados invalidan las entradas antiguas sin una migración.

La codificación determinista de claves es independiente de la salida determinista del compilador. Si los metadatos BEAM upstream cambian entre builds otherwise idénticas en versiones recientes de Elixir, considera establecer `ERL_COMPILER_OPTIONS='[deterministic]'` antes del bootstrap, seeding y consumo de la caché del SDK. Combínalo con cualquier opción de compilador existente y reconstruye las salidas de las dependencias una vez al cambiar la configuración. El SDK no lo establece automáticamente; su valor exacto sigue formando parte de la clave. Los bytes upstream completos siguen siendo hasheados, no normalizados ni eliminados. Esto no es una garantía de reproducibilidad entre checkouts o con builders arbitrarios. La opción del compilador también omite la fuente/opciones de `module_info(:compile)`, así que valida las herramientas de cobertura, depuración y descubrimiento de fuentes antes de adoptarla. Las banderas del compilador no arreglan los generadores en tiempo de compilación no ordenados. El SDK requiere Mint 1.10.2 o posterior, incluidos sus backports de seguridad. Esta release ordena los mapas utilizados para generar sus funciones de frame HTTP/2; actualiza las entradas de lock de Mint antiguas al actualizar el SDK. Otras dependencias y pasadas del compilador aún pueden producir BEAMs de bootstrap variables, incluso con `deterministic` habilitado.

Las salidas del lexer y parser se tratan como archivos derivados solo cuando están ausentes del árbol Git bloqueado o del manifiesto de archivos del paquete Hex. Los archivos `.erl` distribuidos y los contenidos opacos de directorios/submódulos siguen siendo entradas ordinarias; los archivos distribuidos regenerados deben pasar la misma reconciliación de entradas posterior a la etapa. Las plantillas de generador de `parsetools` de OTP también entran en la identidad de la toolchain. Mantén los checkouts de origen de las dependencias aislados entre builds concurrentes: los generadores y builders nativos pueden escribir en `deps/`. Las disposiciones de generadores rebar anidados/personalizados aún pueden necesitar una declaración `generated` auditada.

## Builders nativos y personalizados

Para un builder de Mix, rebar3 o Make auditado, declara un contrato por dependencia:

```elixir
cache: [
  builders: [
    bcrypt_elixir: [
      platform: "build-image@sha256:YOUR_IMMUTABLE_IMAGE_DIGEST",
      outputs: ["priv/bcrypt_nif.so"],
      tools: ["cc", "make"],
      env: ["YOUR_BUILDER_OPTION"]
    ]
  ]
]
```

`platform` identifica el entorno de build nativo compatible. Usa una identidad de imagen/toolchain inmutable que cubra compiladores, SDKs, cabeceras del sistema y librerías compartidas, no una etiqueta reutilizable como `linux`. Siguen aplicándose las comprobaciones habituales de plataforma y Elixir/OTP. Se trata de una auditoría explícita del builder, no de un descubrimiento automático de entradas nativas o efectos secundarios requeridos. Los contratos de builder explícitos no válidos generan un error de configuración accionable en lugar de dejar la caché deshabilitada silenciosamente.

`outputs` enumera las rutas requeridas relativas al directorio de build de la aplicación de la dependencia. Enumera las librerías/ejecutables reales necesarios en tiempo de ejecución. Las salidas faltantes desencadenan la restauración o compilación incluso si Mix considera que los BEAMs están actualizados; se rechazan las snapshots incompletas. Declara variables de entorno adicionales con el `env` del builder y archivos/directorios externos con sus `inputs`, relativos al proyecto consumidor. Las claves nativas incluyen automáticamente variables de entorno de build estándar como `PATH`, `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, `SDKROOT` y `RUSTFLAGS`, utilizando las anulaciones efectivas de `system_env` de la dependencia. La configuración resuelta del proyecto Mix también entra en las claves del builder nativo; la configuración opaca con valores de función no se puede cachear.

Los nombres opcionales de `tools` se resuelven en ese `PATH` efectivo; las rutas de herramientas relativas son relativas al directorio fuente de la dependencia. Los bytes ejecutables y las rutas resueltas entran en la clave, y las herramientas declaradas no disponibles omiten la caché. La huella digital de un lanzador o wrapper del compilador no cubre sus SDKs, subprocesos o librerías del sistema: la `platform` inmutable y las `inputs` adicionales deben cubrirlos. `MAKEFLAGS` se conserva literalmente porque los builders personalizados pueden leerlo. Por lo tanto, los identificadores heredados del jobserver de GNU make pueden causar fallos de caché seguros entre ejecuciones; usa banderas de build estables en un trabajo de caché aislado en lugar de asumir que esos valores se eliminan de la clave.

Algunos builders generan archivos bajo `deps/` en lugar de solo `_build/`. Enumera esas rutas relativas al directorio fuente de esa dependencia en `generated`, por ejemplo `generated: ["priv/native"]`. Solo esas rutas generadas se excluyen de las entradas de origen. No excluyas recursos originales ni archivos fuente: deben permanecer como entradas. Las rutas son literales, sin comodines ni traversals. El contrato, la plataforma, las entradas adicionales, los valores de entorno y cualquier comando de compilación personalizado de la dependencia participan en las claves. `compile: false` sigue siendo una opción para excluirse de la compilación.

Las snapshots auditadas materializan los recursos respaldados por origen `ebin`, `priv`, `include` y `src` en la aplicación restaurada. Por lo tanto, las librerías nativas, ejecutables de puerto, cabeceras y recursos generados sobreviven a un checkout frío, sin modificar sus fuentes de dependencia. Se preservan los modos ejecutables y los symlinks de recursos relativos contenidos; se rechazan los enlaces de escape, absolutos y cíclicos. Todos los recursos de la aplicación upstream entran en las claves downstream, incluidos los recursos ordinarios de `priv` y los directorios de salida personalizados, no solo las librerías nativas o BEAMs. El código que lee directamente las rutas de origen del productor no se reubica; los builders con efectos secundarios obligatorios fuera del artefacto de la aplicación aún necesitan esos pasos.

Mantén los builders personalizados excluidos hasta que sus entradas y salidas sean auditadas. Un contrato no elimina la compilación de bootstrap del SDK en frío, el límite de artefactos de 64 MiB, ni la necesidad de un entorno de build compatible.

## Reutilización entre rutas de checkout

Las rutas de checkout participan en las claves por defecto. Si tus dependencias no dependen de las rutas del productor, opta por la reutilización entre diferentes ubicaciones de checkout:

```elixir
cache: [portable: true]
```

Los BEAMs en caché conservan las rutas de depuración/fuente del productor y los valores en tiempo de compilación de `__DIR__`, `__ENV__.file` y `File.cwd!()`. La reutilización portátil no los reescribe. Los enlaces de recursos apuntan al checkout de origen actual. Los bytes BEAM upstream también entran en las claves y pueden incrustar rutas, por lo que la reutilización puede requerir restaurar el cierre upstream desde la misma caché en lugar de recompilarlo independientemente.

## Almacenamiento y acceso

| Opción | Por defecto | Propósito |
| --- | --- | --- |
| `remote` | `true` | Usa la caché remota compartida después de un fallo local. |
| `upload` | `true` | Publica nuevos bundles remotamente. `false` aún permite lecturas y snapshots locales. |
| `path` | Directorio de caché de Tuist, bajo `mix/dependencies/v1` | Elige un almacén local diferente. |
| `endpoint` | Descubierto automáticamente | Anula el endpoint HTTPS REAPI de la cuenta. |

`upload: false` controla el comportamiento del cliente, no la autorización. Los permisos de caché del proyecto son aplicados por el servidor. Las opciones de `endpoint:` del proyecto y los endpoints descubiertos requieren HTTPS, excepto para los endpoints de desarrollo de loopback (`localhost`, `127.0.0.1`, `::1`).

Un `TUIST_CACHE_ENDPOINT` no vacío anula tanto `endpoint:` como el descubrimiento. Los runners alojados lo usan para alcanzar su caché privada dentro del clúster. Esta anulación de entorno controlada por el operador también permite HTTP en hosts que no son de loopback. HTTP envía el token de caché con alcance de proyecto y los artefactos sin cifrar, así que úsalo solo en una red de confianza. Una anulación no válida vuelve a las snapshots locales sin intentar el descubrimiento.

Las snapshots locales y los bundles remotos están limitados a 64 MiB; los artefactos más grandes se compilan sin ser cacheados. El almacén local no tiene expulsión automática; elimina su contenido cuando sea necesario. Los artefactos remotos utilizan las reglas existentes de retención, expulsión y limpieza de proyectos de Kura.

> [!IMPORTANT]
> Los manifiestos del compilador y los BEAMs pueden incrustar rutas del productor y valores en tiempo de compilación, incluidos secretos. Los lectores de caché del proyecto pueden acceder a esos artefactos. Los escritores de caché son productores de código de confianza: las comprobaciones de digest detectan corrupción, no BEAMs ejecutables maliciosos. No expongas las credenciales de escritura de caché a trabajos de PR no confiables ni compiles dependencias no confiables con esas credenciales disponibles.

## Solución de problemas de hits faltantes

- Ejecuta `mix tuist.setup` después de instalar el paquete y confirma la configuración de Mix generada. La configuración preserva otros alias y opciones de Tuist; rechaza acciones de compilación personalizadas en lugar de eliminarlas silenciosamente.
- Mantén el alias de compilación generado. El descubrimiento directo de tareas de `mix tuist.compile` puede compilar dependencias antes de que la caché pueda inspeccionarlas.
- Las salidas válidas y ya actualizadas de las dependencias seleccionadas y compatibles se cuentan como hits locales con el motivo `up_to_date`. No se publican retrospectivamente y no llevan clave de artefacto, bytes transferidos, latencia de restauración ni tiempo estimado ahorrado. Para probar la restauración de una snapshot, limpia solo la compilación de una dependencia compatible con `mix deps.clean NAME --build` después de que haya poblado la caché y luego compila de nuevo.
- Asegúrate de que coincidan `MIX_ENV`, `MIX_TARGET`, la configuración del compilador y las entradas declaradas. Los cambios de ruta también cambian las claves, a menos que esté habilitada la reutilización portable.
- Las dependencias no compatibles aparecen como **No cacheadas**, no como fallos de caché. Se excluyen de la tasa de aciertos. Una compilación sin búsquedas ni hits locales actualizados tiene una tasa no disponible, no 0%.
- La falta de credenciales, los endpoints no disponibles y las snapshots corruptas recurren a la compilación. Los fallos del compilador siguen haciendo fallar la compilación.
- Los registros CAS pueden llegar después del informe de compilación. Actualiza para ver las transferencias recién ingeridas. Los hits locales y las compilaciones heredadas no tienen salidas CAS remotas.

Los servidores necesitan soporte para el contrato de informe de compilación `0.2` para registrar hits locales `up_to_date`. Si un servidor antiguo rechaza explícitamente los datos de caché o un valor de enumeración del esquema, el paquete reintenta el informe una vez sin estas nuevas observaciones de reutilización. Los detalles de compilación y otros resultados de caché se conservan; la nueva reutilización local sigue sin estar disponible hasta que se actualice el servidor. Desplegar el servidor primero evita esta solicitud adicional. La versión del contrato no negocia el soporte, y los fallos de autenticación, los fallos de transporte y otros mensajes de validación no se reintentan. Los errores de enumeración no identifican su campo en servidores antiguos; un campo no válido retenido sigue fallando en el único reintento.

## Integración manual de compilación

Si la configuración no puede editar la configuración de tu proyecto de forma segura, integra este alias manualmente, conservando cualquier acción de compilación personalizada:

```elixir
compile: [
  "deps.compile tuist_ex --include-children",
  "deps.loadpaths --no-compile --no-deps-check",
  "tuist.compile"
]
```

Estos pasos compilan y cargan Tuist antes que otras dependencias, incluso en compilaciones paralelas en frío. El wrapper restaura las comprobaciones normales de dependencias después. El mismo alias funciona con instalaciones Hex, Git y de ruta; no se necesita una ruta de script.

Para trabajos que preparan una compilación subida y luego se ejecutan con `--no-compile`, protege también todo el trabajo de arranque. Mix reenvía argumentos solo a la tarea final de un alias de lista, por lo que su `deps.compile` anterior se ejecuta incondicionalmente. Usa una función local en el módulo de tu proyecto Mix en su lugar:

```elixir
# In aliases/0:
compile: &compile/1

# In the same Mix project module:
defp compile(args) do
  if "--no-compile" not in args do
    Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
  end

  Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
  Mix.Task.run("tuist.compile", args)
end
```

Esta es una función local del proyecto, no una captura de una función del SDK que aún no está cargada. Trátala como una integración personalizada: `tuist.setup` rechaza los alias de compilación personalizados en lugar de reemplazarlos.

## Cómo funciona

El almacenamiento en caché de Elixir utiliza la tubería compartida REAPI ActionCache/CAS, la autenticación y las analíticas firmadas por Kura utilizadas por Bazel, no un servicio de almacenamiento Mix separado. Una clave de entrada modelada hace referencia a un ActionResult que contiene el digest SHA-256 en bytes brutos de un bundle de compilación completo. Tuist verifica sus archivos, metadatos de la aplicación, BEAMs declarados y manifiesto SCM antes de la instalación por etapas. Las entradas corruptas se reparan después de una compilación exitosa.

En OTP 28 y posteriores, las sesiones remotas negocian la compresión zstd para transferencias ByteStream de al menos 1 KiB. Las subidas incompresibles, los tiempos de ejecución OTP más antiguos y los servidores sin compresión utilizan transporte identity. Los digests, los límites de artefactos y los bytes reportados se refieren al contenido sin comprimir. Los bytes decodificados se limitan y verifican antes de la instalación. Cada dependencia permanece como un único bundle CAS, evitando solicitudes por archivo o por fragmento para artefactos pequeños.

Las credenciales/conexiones remotas se resuelven de forma perezosa; las compilaciones inactivas y los hits locales (incluidas las salidas ya actualizadas) no contactan con endpoints remotos. Una sesión se cierra en cada salida, incluido el fallo del compilador. Las RPC del cliente tienen un plazo de 30 segundos. Mix sigue siendo responsable de las comprobaciones de bloqueo, la compilación local de dependencias y el trabajo no compatible.

La latencia/bytes del panel conservan la procedencia local frente a la remota y distinguen los valores no disponibles del cero medido. El tiempo remoto mide las transferencias CAS del cliente, mientras que el tiempo local incluye la verificación y la instalación; ninguno incluye la compilación. Las salidas CAS utilizan transferencias exitosas firmadas por Kura, no copias locales ni claves de entrada de acción. El rendimiento son los bytes divididos por el tiempo medido; los tamaños comprimidos no están disponibles. El tiempo de compilación estimado evitado es la duración original de compilación del productor, no el ahorro de compilación de extremo a extremo medido.

Las dependencias independientes y listas se obtienen en ventanas de hasta cuatro solicitudes concurrentes sobre la misma conexión HTTP/2. Esto limita el búfer de bundles decodificados a cuatro artefactos, cada uno sujeto al límite de 64 MiB. La planificación de claves, el estado de Mix y la instalación permanecen serializados. Las claves descendentes esperan a los artefactos ascendentes; los bytes preobtenidos se consumen solo bajo su clave de entrada exacta, con las entradas revalidadas antes de la instalación remota. Las salidas ya actualizadas y las snapshots locales no provocan solicitudes remotas especulativas. La compilación y las subidas permanecen seriales para ciertos fallos de caché; la concurrencia no es una promesa de que cada compilación sea más rápida.

## ¿Puede cada dependencia omitir la compilación?

Un hit compatible puede omitir la compilación de una dependencia compatible, pero `cache: true` es fail-open, no una garantía de cero compilación. Las entradas faltantes/expulsadas, los builders no compatibles y el arranque en frío del SDK todavía pueden compilar. Una alta tasa de aciertos por sí sola no establece una aceleración en tiempo real.

Para CI de construir-una-vez/probar-muchas, usa
<.localized_link href="/guides/features/test-sharding/elixir">Elixir test sharding</.localized_link>
para distribuir la compilación preparada exacta en lugar de esperar que cada worker la reconstruya a partir de hits de caché por dependencia. Reutilizar una compilación completa, especialmente una que contenga bibliotecas nativas, sigue requiriendo una plataforma, toolchain y configuración compatibles. Las compilaciones personalizadas arbitrarias no pueden omitir con seguridad sus pasos de compilación sin modelar sus entradas externas, salidas y efectos secundarios requeridos.
