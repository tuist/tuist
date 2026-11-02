---
title: Configuración avanzada de la caché de Elixir
titleTemplate: ":title · Caché · Guías · Tuist"
description: Configura entradas de compilación adicionales, selección de dependencias y reutilización portátil.
---

# Configuración avanzada de la caché de Elixir

Comienza con <.localized_link href="/guides/features/cache/elixir">la guía de configuración de la caché de Elixir</.localized_link>. Las opciones siguientes solo son necesarias cuando tu proyecto tiene entradas de compilación adicionales, excepciones de dependencias o rutas de checkout diferentes.

## Seleccionar dependencias

`cache: true` almacena en caché las dependencias compatibles automáticamente. Una lista de palabras clave ofrece la misma selección automática, con anulaciones opcionales:

```elixir
cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
```

Para limitar la caché a dependencias específicas:

```elixir
cache: [dependencies: [:nimble_options, :nimble_parsec]]
```

`dependencies: :all` selecciona explícitamente todas las dependencias compatibles; `dependencies: []` no selecciona ninguna. `exclude:` tiene prioridad sobre cualquiera de las selecciones. Omitir `cache`, o establecerlo como `false` o `nil`, desactiva la caché.

Las dependencias compatibles se obtienen a través de Hex o Git y usan el pipeline estándar del compilador Mix con fuentes de Elixir/Erlang, o la compilación pura-BEAM habitual de rebar3. Las dependencias de Mix también pueden reutilizar artefactos cuando sus dependencias ascendentes usan rebar3. La configuración de Rebar, los archivos de fuente/cabecera y la huella del ejecutable de rebar3 participan en las claves. También se admiten los metadatos empaquetados de `ebin/*.app` y los Makefiles pasivos. Los scripts de configuración de Rebar ya han sido evaluados por Mix antes de la búsqueda; su código fuente y la configuración efectiva entran en las claves. Los scripts de origen de la aplicación (`*.app.src.script`) son evaluados posteriormente por rebar3 y requieren un contrato de constructor auditado, al igual que los plugins de compilación y los ganchos de compilación. Si falta el lanzador de rebar3, se instala antes de generar la huella, usando el instalador normal de Mix; los workers fríos aún necesitan acceso a ese instalador.

Los trazadores personalizados, los enlaces simbólicos de origen, las raíces de umbrella y las cadenas que contienen dependencias locales se compilan con normalidad. Las propias dependencias de arranque de Tuist también se compilan con normalidad en workers fríos. La elegibilidad estructural no demuestra que el código de compilación arbitrario sea hermético.

## Declarar entradas adicionales

Los árboles de origen, las identidades bloqueadas de las dependencias, las fuentes ascendentes, los BEAMs y recursos, las banderas de ejecución/opcionales/de aplicación de las dependencias, los metadatos resueltos de la aplicación, la configuración efectiva explícita de la aplicación, las opciones del compilador (incluidas las opciones del lexer y del parser), el entorno y el objetivo de Mix, y la identidad de la toolchain se incluyen automáticamente. Las variables específicas de cada dependencia `env:` y `system_env:` entran en la clave y la configuración se evalúa bajo ese entorno. Los valores predeterminados de la aplicación entran a través de las entradas de origen, no del estado de carga de la VM.

Para dependencias que leen archivos fuera de su árbol de origen o variables de entorno adicionales en tiempo de compilación, declara esas entradas:

```elixir
cache: [
  inputs: ["schemas", "config/compiler-input.json"],
  env: ["YOUR_COMPILER_OPTION"]
]
```

Las macros de Elixir y los cuerpos de los módulos pueden leer archivos arbitrarios, el entorno, las rutas de código ambientales, las respuestas de red y la hora. Tuist no descubre automáticamente estas lecturas. Cambiar entradas no declaradas puede producir salidas obsoletas. Excluye dependencias con compilación dependiente del tiempo/red o efectos secundarios que deban ejecutarse en cada compilación; usa `dependencies:` para una lista blanca de dependencias auditada cuando necesites un control más estricto.

Las variables estándar del compilador/tiempo de ejecución (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`, `ERL_AFLAGS`, `ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH` y `MIX_ARCHIVES`) se capturan automáticamente. La identidad de la toolchain incluye la build de Elixir, la versión completa de OTP cuando esté disponible, ERTS, el bytecode del compilador, el sistema operativo/versión, la arquitectura, el tamaño de palabra y el orden de bytes. El contexto efectivo se captura antes de cada búsqueda. Los modelos de entrada por dependencia pueden compartirse para la planificación de búsquedas dentro de una misma preparación; la compilación borra el plan y la restauración invalida los registros de la aplicación instalada. La instalación y publicación por etapas siempre verifican entradas nuevas sin reutilizar el plan de búsqueda. Un fallo de búsqueda también captura una clave nueva antes de la compilación. Las entradas cambiadas rechazan un acierto por etapas en lugar de instalar código construido para las entradas anteriores.

Las claves usan codificación determinista de términos y recorrido ordenado del sistema de archivos. Las declaraciones de constructores no ordenadas y los conjuntos de entradas declarados se ordenan y deduplican; las opciones del compilador ordenadas conservan su orden. Importan los contenidos de los archivos, los nombres, los bits de ejecución y las rutas faltantes, no las marcas de tiempo del sistema de archivos. Las declaraciones de archivos no modelan la propiedad, las marcas de tiempo ni otros metadatos del sistema de archivos; excluye constructores que deriven salidas a partir de esos valores. Los manifiestos del compilador ascendente se excluyen como contabilidad incremental; el código que lee deliberadamente su contenido debe declararlos como entradas adicionales. La configuración de expresiones regulares usa su origen y opciones, nunca referencias compiladas locales a la VM. Otros valores opacos de tiempo de ejecución omiten la caché. Los modelos de clave actualizados invalidan las entradas antiguas sin migración.

La codificación determinista de claves es independiente de la salida determinista del compilador. Si los metadatos BEAM ascendentes cambian entre builds otherwise idénticas en versiones recientes de Elixir, considera establecer `ERL_COMPILER_OPTIONS='[deterministic]'` antes del arranque del SDK, la siembra y el consumo de la caché. Combínalo con cualquier opción de compilador existente y reconstruye las salidas de las dependencias una vez al cambiar la configuración. El SDK no lo establece automáticamente; su valor exacto sigue formando parte de la clave. Los bytes completos ascendentes siguen siendo hasheados, no normalizados ni eliminados. Esto no es una garantía de reproducibilidad entre checkouts o para constructores arbitrarios. La opción del compilador también omite el origen/opciones de `module_info(:compile)`, así que valida las herramientas de cobertura, depuración y descubrimiento de origen antes de adoptarla. Las banderas del compilador no arreglan generadores en tiempo de compilación no ordenados. El SDK requiere Mint 1.10.2 o posterior, incluidos sus backports de seguridad. Esta versión ordena los mapas usados para generar sus funciones de tramas HTTP/2; actualiza las entradas de bloqueo de Mint antiguas al actualizar el SDK. Otras dependencias y pasadas del compilador aún pueden producir BEAMs de arranque variables, incluso con `deterministic` habilitado.

Las salidas del lexer y del parser se tratan como archivos derivados solo cuando están ausentes del árbol de Git bloqueado o del manifiesto de archivos del paquete Hex. Los archivos `.erl` distribuidos y los contenidos opacos de directorios/submódulos siguen siendo entradas ordinarias; los archivos distribuidos regenerados deben pasar la misma reconciliación de entradas posterior al staging. Las plantillas de generadores de `parsetools` de OTP también entran en la identidad de la toolchain. Mantén los checkouts de origen de las dependencias aislados entre builds concurrentes: los generadores y constructores nativos pueden escribir en `deps/`. Las disposiciones anidadas/personalizadas de generadores de rebar aún pueden necesitar una declaración `generated` auditada.

## Constructores nativos y personalizados

Para un constructor Mix, rebar3 o Make auditado, declara un contrato por dependencia:

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

`platform` identifica el entorno de compilación nativo compatible. Usa una identidad inmutable de imagen/toolchain que cubra compiladores, SDKs, cabeceras del sistema y bibliotecas compartidas, no una etiqueta reutilizable como `linux`. Siguen aplicándose las comprobaciones habituales de plataforma y Elixir/OTP. Esto es una auditoría explícita del constructor, no un descubrimiento automático de entradas nativas o efectos secundarios requeridos. Los contratos de constructor explícitos no válidos generan un error de configuración accionable en lugar de dejar la caché deshabilitada silenciosamente.

`outputs` lista las rutas requeridas relativas al directorio de compilación de la aplicación de la dependencia. Enumera las bibliotecas/ejecutables reales necesarios en tiempo de ejecución. Las salidas faltantes activan la restauración o compilación incluso si Mix considera los BEAMs actuales; las instantáneas incompletas se rechazan. Declara variables de entorno adicionales con `env` del constructor y archivos/directorios externos con su `inputs`, relativos al proyecto consumidor. Las claves nativas incluyen automáticamente variables de entorno de compilación estándar como `PATH`, `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, `SDKROOT` y `RUSTFLAGS`, usando las anulaciones efectivas de `system_env` de la dependencia. La configuración resuelta del proyecto Mix también entra en las claves del constructor nativo; la configuración opaca con valores de función no se puede almacenar en caché.

Los nombres opcionales de `tools` se resuelven en ese `PATH` efectivo; las rutas de herramientas relativas son relativas al directorio de origen de la dependencia. Los bytes ejecutables y las rutas resueltas entran en la clave, y las herramientas declaradas no disponibles omiten la caché. La huella digital de un lanzador o envoltorio del compilador no cubre sus SDKs, subprocesos o bibliotecas del sistema: la `platform` inmutable y las `inputs` adicionales deben cubrirlos. `MAKEFLAGS` se conserva literalmente porque los constructores personalizados pueden leerlo. Los identificadores heredados del jobserver de GNU make pueden causar fallos de caché seguros entre ejecuciones; usa banderas de compilación estables en un trabajo de caché aislado en lugar de asumir que esos valores se eliminan de la clave.

Algunos constructores generan archivos bajo `deps/` en lugar de solo `_build/`. Lista esas rutas relativas al directorio de origen de esa dependencia en `generated`, por ejemplo `generated: ["priv/native"]`. Solo esas rutas generadas se excluyen de las entradas de origen. No excluyas recursos originales ni archivos de origen: deben permanecer como entradas. Las rutas son literales, sin comodines ni traversals. El contrato, la plataforma, las entradas adicionales, los valores de entorno y cualquier comando de compilación personalizado de la dependencia participan en las claves. `compile: false` sigue siendo una opción para excluirse de la compilación.

Las instantáneas auditadas materializan recursos respaldados por origen de `ebin`, `priv`, `include` y `src` en la aplicación restaurada. Por lo tanto, las bibliotecas nativas, ejecutables de puerto, cabeceras y recursos generados sobreviven a un checkout frío, sin modificar sus fuentes de dependencia. Se preservan los modos ejecutables y los enlaces simbólicos de recursos relativos contenidos; se rechazan los enlaces de escape, absolutos y cíclicos. Todos los recursos de la aplicación ascendente entran en las claves descendentes, incluidos los recursos ordinarios de `priv` y los directorios de salida personalizados, no solo las bibliotecas nativas o BEAMs. El código que lee directamente las rutas de origen del productor no se reubica; los constructores con efectos secundarios obligatorios fuera del artefacto de la aplicación aún necesitan esos pasos.

Mantén los constructores personalizados excluidos hasta que sus entradas y salidas sean auditadas. Un contrato no elimina la compilación de arranque del SDK en frío, el límite de artefacto de 64 MiB, ni la necesidad de un entorno de compilación compatible.

## Reutilización entre rutas de checkout

Las rutas de checkout participan en las claves por defecto. Si tus dependencias no dependen de las rutas del productor, opta por la reutilización entre diferentes ubicaciones de checkout:

```elixir
cache: [portable: true]
```

Los valores configurados que incrustan la ruta de checkout, como las rutas construidas desde `__DIR__` en `config/config.exs`, no cambian las claves portátiles.

Los BEAMs en caché conservan las rutas de depuración/origen del productor y los valores en tiempo de compilación de `__DIR__`, `__ENV__.file` y `File.cwd!()`. La reutilización portátil no los reescribe. Los enlaces de recursos apuntan al checkout de origen actual. Los bytes BEAM ascendentes también entran en las claves y pueden incrustar rutas, por lo que la reutilización puede requerir restaurar el cierre ascendente desde la misma caché en lugar de recompilarlo independientemente.

## Almacenamiento y acceso

| Opción | Predeterminado | Propósito |
| --- | --- | --- |
| `remote` | `true` | Usa la caché remota compartida después de un fallo local. |
| `upload` | `true` | Publica nuevos bundles remotamente. `false` aún permite lecturas e instantáneas locales. |
| `path` | Directorio de caché de Tuist, bajo `mix/dependencies/v1` | Elige un almacén local diferente. |
| `endpoint` | Descubierto automáticamente | Anula el endpoint HTTPS REAPI de la cuenta. |

`upload: false` controla el comportamiento del cliente, no la autorización. Los permisos de caché del proyecto son aplicados por el servidor. Las credenciales que solo pueden leer la caché del proyecto omiten las subidas automáticamente. Las opciones de `endpoint:` del proyecto y los endpoints descubiertos requieren HTTPS, excepto para endpoints de desarrollo de loopback (`localhost`, `127.0.0.1`, `::1`).

Un `TUIST_CACHE_ENDPOINT` no vacío anula tanto `endpoint:` como el descubrimiento. Los runners alojados lo usan para alcanzar su caché privada dentro del clúster. Esta anulación de entorno controlada por el operador también permite HTTP en hosts que no son de loopback. HTTP envía el token de caché con ámbito de proyecto y los artefactos sin cifrar, así que úsalo solo en una red de confianza. Una anulación no válida vuelve a las instantáneas locales sin intentar el descubrimiento.

Las instantáneas locales y los bundles remotos están limitados a 64 MiB; los artefactos más grandes se compilan sin ser almacenados en caché. El almacén local no tiene expulsión automática; elimina su contenido cuando sea necesario. Los artefactos remotos usan las reglas existentes de retención, expulsión y limpieza de proyectos de Kura.

> [!IMPORTANT]
> Los manifiestos del compilador y los BEAMs pueden incrustar rutas del productor y valores en tiempo de compilación, incluidos secretos. Los lectores de caché del proyecto pueden acceder a esos artefactos. Los escritores de caché son productores de código de confianza: las comprobaciones de digest detectan corrupción, no BEAMs ejecutables maliciosos. No expongas credenciales de escritura de caché a trabajos de PR no confiables ni compiles dependencias no confiables con esas credenciales disponibles.

## Solución de problemas de hits faltantes

- Ejecuta `mix tuist.setup` después de instalar el paquete y confirma la configuración de Mix generada. La configuración preserva otros alias y opciones de Tuist; rechaza acciones de compilación personalizadas en lugar de eliminarlas silenciosamente.
- Mantén el alias de compilación generado. La descubierta directa de tareas `mix tuist.compile` puede compilar dependencias antes de que la caché pueda inspeccionarlas.
- Las salidas ya actualizadas y válidas para las dependencias seleccionadas y compatibles cuentan como hits locales con motivo `up_to_date`. No se publican retrospectivamente y no llevan clave de artefacto, bytes transferidos, latencia de restauración ni tiempo estimado ahorrado. Para probar una restauración desde instantánea, limpia solo la compilación de una dependencia compatible con `mix deps.clean NAME --build` después de que haya poblado la caché, y luego vuelve a compilar.
- Asegúrate de que coincidan `MIX_ENV`, `MIX_TARGET`, la configuración del compilador y las entradas declaradas. Los cambios en las rutas también cambian las claves, a menos que esté habilitada la reutilización portátil.
- Las dependencias no compatibles aparecen como **No almacenado en caché**, no como fallos. Se excluyen de la tasa de aciertos. Una compilación sin búsquedas ni hits locales actualizados tiene una tasa no disponible, no 0%.
- La falta de credenciales, los endpoints no disponibles y las instantáneas corruptas vuelven a la compilación. Los fallos del compilador siguen haciendo fallar la compilación.
- Los registros CAS pueden llegar después del informe de compilación. Actualiza para ver las transferencias recién ingeridas. Los hits locales y las compilaciones heredadas no tienen salidas CAS remotas.

Los servidores necesitan soporte para el contrato de informe de compilación `0.2` para registrar hits locales `up_to_date`. Si un servidor antiguo rechaza explícitamente los datos de caché o un valor de enumeración del esquema, el paquete reintenta el informe una vez sin estas nuevas observaciones de reutilización. Los detalles de compilación y otros resultados de caché se conservan; la nueva reutilización local permanece no disponible hasta que el servidor se actualice. Desplegar el servidor primero evita esta solicitud adicional. La versión del contrato no negocia el soporte, y los fallos de autenticación, fallos de transporte y otros mensajes de validación no se reintentan. Los errores de enumeración no identifican su campo en servidores antiguos; un campo no válido retenido sigue fallando en el único reintento.

## Integración manual de compilación

Si la configuración no puede editar la configuración de tu proyecto de forma segura, añade este alias y estas funciones al módulo de tu proyecto Mix manualmente, conservando cualquier acción de compilación personalizada:

```elixir
# In aliases/0:
compile: &compile/1

# In the same Mix project module:
defp compile(args) do
  if "--no-compile" not in args do
    compile_tuist_ex()
  end

  Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
  Mix.Task.run("tuist.compile", args)
end

defp compile_tuist_ex do
  deps =
    ["tuist_ex"]
    |> Mix.Dep.filter_by_name(Mix.Dep.load_and_cache(), include_children: true)
    |> Enum.reject(&(Mix.Dep.ok?(&1) and &1.scm.fetchable?()))
    |> Enum.map(&Atom.to_string(&1.app))

  if deps != [], do: Mix.Task.run("deps.compile", deps)
end
```

Estas funciones compilan y cargan Tuist antes que otras dependencias, incluso en compilaciones paralelas en frío, y omiten ese trabajo cuando Tuist y sus dependencias ya están compiladas o el comando se ejecuta con `--no-compile`. Las mismas funciones funcionan con instalaciones Hex, Git y de ruta; no se necesita una ruta de script.

Si tu alias comienza con `deps.compile tuist_ex --include-children`, cada `mix compile` recompila las dependencias de Tuist y puede recompilar todo tu proyecto. Ejecuta `mix tuist.setup` de nuevo para reemplazarlo.

## Cómo funciona

El almacenamiento en caché de Elixir usa la tubería compartida REAPI ActionCache/CAS, la autenticación y las analíticas firmadas por Kura usadas por Bazel, no un servicio de almacenamiento Mix separado. Una clave de entrada modelada hace referencia a un ActionResult que contiene el digest SHA-256 en bytes crudos de un bundle de compilación completo. Tuist verifica sus archivos, metadatos de aplicación, BEAMs declarados y manifiesto SCM antes de la instalación por etapas. Las entradas corruptas se reparan tras una compilación exitosa.

En OTP 28 y posteriores, las sesiones remotas negocian compresión zstd para transferencias ByteStream de al menos 1 KiB. Las subidas incompresibles, los entornos de ejecución OTP más antiguos y los servidores sin compresión usan transporte identity. Los digests, los límites de artefactos y los bytes reportados se refieren al contenido sin comprimir. Los bytes decodificados están acotados y verificados antes de la instalación. Cada dependencia permanece como un único bundle CAS, evitando solicitudes por archivo o por fragmento para artefactos pequeños.

Las credenciales/conexiones remotas se resuelven de forma diferida; las compilaciones inactivas y los hits locales (incluidas las salidas ya actualizadas) no contactan con endpoints remotos. Una sesión se cierra en cada salida, incluido el fallo del compilador. Las RPC del cliente tienen un plazo de 30 segundos. Mix sigue siendo responsable de las comprobaciones de bloqueo, la compilación local de dependencias y el trabajo no compatible.

La latencia/bytes del panel conservan la procedencia local frente a remota y distinguen valores no disponibles de cero medido. El tiempo remoto mide las transferencias CAS del cliente, mientras que el tiempo local incluye verificación e instalación; ninguno incluye compilación. Las Salidas CAS usan transferencias exitosas firmadas por Kura, no copias locales ni claves de entrada de acción. El rendimiento son bytes divididos por el tiempo medido; los tamaños comprimidos no están disponibles. El tiempo de compilación estimado evitado es la duración original de compilación del productor, no el ahorro de compilación de extremo a extremo medido.

Las dependencias independientes y listas se obtienen en ventanas de hasta cuatro solicitudes concurrentes sobre la misma conexión HTTP/2. Esto limita el búfer de bundles decodificados a cuatro artefactos, cada uno sujeto al límite de 64 MiB. La planificación de claves, el estado de Mix y la instalación permanecen serializados. Las claves descendentes esperan a los artefactos ascendentes; los bytes precargados se consumen solo bajo su clave de entrada exacta, con entradas verificadas de nuevo antes de la instalación remota. Las salidas ya actualizadas y las instantáneas locales no provocan solicitudes remotas especulativas. La compilación y las subidas permanecen seriales para fallos de caché seleccionados; la concurrencia no es una promesa de que cada compilación sea más rápida.

## ¿Puede cada dependencia omitir la compilación?

Un hit compatible puede omitir la compilación de una dependencia compatible, pero `cache: true` es fail-open, no una garantía de cero compilación. Las entradas faltantes/expulsadas, los constructores no compatibles y el arranque en frío del SDK aún pueden compilar. Una alta tasa de aciertos por sí sola no establece una aceleración en tiempo real.

Para CI de construir-una-vez/probar-muchas, usa
<.localized_link href="/guides/features/test-sharding/elixir">Elixir test sharding</.localized_link>
para distribuir la compilación preparada exacta en lugar de esperar que cada worker la reconstruya a partir de hits de caché por dependencia. Reutilizar una compilación completa, especialmente una que contiene bibliotecas nativas, sigue requiriendo una plataforma, cadena de herramientas y configuración compatibles. Las compilaciones personalizadas arbitrarias no pueden omitir con seguridad sus pasos de compilación sin modelar sus entradas externas, salidas y efectos secundarios requeridos.
