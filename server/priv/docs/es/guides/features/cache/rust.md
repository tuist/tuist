---
{
  "title": "Caché de Rust",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Reutiliza los resultados de compilación de Rust compatibles de forma local y a través de la caché remota de Tuist con Cargo."
}
---
# Caché de Rust {#rust-cache}

Tuist almacena en caché las salidas de compilación de Rust compatibles para que Cargo pueda reutilizarlas después de que se hayan eliminado sus resultados de compilación. La caché está integrada en la CLI de Tuist. No hay ningún ejecutable de caché separado ni plugin de Cargo que instalar.

<!-- @snippet: ./_rust-experimental -->

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

La caché es automática para las compilaciones elegibles. No hay configuración adicional de caché ni bandera de habilitación. Tuist descubre el endpoint de caché de tu cuenta y obtiene las credenciales de caché usando la configuración existente de tu proyecto y servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos ordinarios de `cargo`.

## Cómo funciona {#how-it-works}

Antes de que Cargo inicie, Tuist restaura las salidas de tus dependencias de registro y git que una compilación anterior produjo con la misma toolchain, perfil y configuración, para que Cargo las encuentre actualizadas. Cargo sigue siendo responsable de decidir qué recompilar. Luego, para cada compilación elegible que Cargo aún ejecuta, Tuist:

1. Comprueba su caché local en busca de salidas coincidentes.
2. En caso de fallo de caché local, consulta a Kura a través de la Remote Execution API (REAPI), descarga cualquier contenido faltante y verifica las salidas antes de restaurarlas.
3. En caso de fallo de caché, ejecuta el compilador normalmente. Después de una compilación exitosa, almacena las salidas localmente y las sube a Kura a través de REAPI cuando está autorizado. La entrada de caché remota se publica solo después de que todo su contenido referenciado esté disponible.

Las compilaciones en la misma máquina comparten la caché local, incluidas las compilaciones en otros worktrees o directorios de destino. Cuando otra compilación ya está compilando el mismo crate o ejecutando el mismo script de compilación, Tuist espera por ella y restaura sus salidas en lugar de hacer el mismo trabajo dos veces. Si esa compilación tarda más de 10 minutos, Tuist deja de esperar y compila el crate él mismo.

Las compilaciones locales y de CI usan el mismo protocolo de caché remota. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida de caché</.localized_link> de tu cuenta. Una cuenta puede permitir a los desarrolladores descargar mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: las salidas del compilador en caché son código ejecutable, así que otorga acceso de escritura solo a máquinas y tokens en los que confíes.

Si la configuración remota falla, la caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas recurren a la compilación. Un fallo de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché admite:

- Crates de biblioteca, incluidos crates de workspace y de ruta, crates con dependencias y crates con fuentes generadas. Tuist los indexa por las fuentes que leyó el compilador.
- En Macs con Apple silicon y en Linux x86_64 y arm64 con glibc, compilaciones que la inspección de fuentes no puede indexar por adelantado, como crates que usan macros procedurales, ensamblador en línea o bibliotecas nativas, las propias macros procedurales y ejecutables enlazados. Tuist registra los archivos, variables de entorno y comandos de solo lectura que lee cada uno, como `git describe`, y los indexa por ellos. En Linux, el enlazador del sistema, la biblioteca C y los archivos de inicio que lee un enlace forman parte de su clave.
- En las mismas plataformas, ejecuciones de scripts de compilación, incluidas las compilaciones de C que realizan (con el compilador predeterminado de Apple en macOS, con cualquier compilador enlazado dinámicamente en Linux). Una ejecución se restaura solo cuando los archivos, el entorno y los comandos que leyó no han cambiado.
- Advertencias y otros diagnósticos, que un crate en caché muestra de nuevo.

Lo siguiente sigue compilándose normalmente:

- Scripts de compilación y compilaciones registradas en distribuciones de Linux sin glibc, como Alpine.
- Scripts de compilación que se conectan a la red, inician programas que Tuist no puede observar (en Linux, programas enlazados estáticamente) o escriben fuera de su directorio de salida.
- Compilaciones incrementales, targets personalizados y argumentos del compilador o entradas de fuente no compatibles.
- Invocaciones de `cargo check` solo de metadatos.
- Compilaciones que emiten salida inesperada del compilador.
- Compilaciones que se ejecutan con configuraciones del cargador dinámico, como `LD_PRELOAD`, o con directorios de `LD_LIBRARY_PATH` fuera de la toolchain de Rust y del directorio de destino, por ejemplo, los heredados de tu shell o un `build.build-dir` fuera del directorio de destino.

Un wrapper global del compilador preexistente deshabilita la caché de compilación de Tuist y el observador del compilador. Los wrappers personalizados de workspace también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad de herramientas del compilador</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la toolchain, los argumentos y el entorno de compilación. La ubicación del checkout, el directorio de destino, el home de Cargo y la toolchain se reemplazan con marcadores de posición, por lo que un checkout en otra ruta reutiliza las mismas entradas. Un crate cuya salida incorpora su propia ruta, por ejemplo a través de `env!("CARGO_MANIFEST_DIR")`, se reutiliza solo en esa ruta. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Los crates que leen esas variables excluidas durante la compilación no se almacenan en caché.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar salidas actualizadas. Para probar la caché de Tuist en lugar de las salidas existentes de Cargo, compila una vez, elimina las salidas de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las bibliotecas elegibles pueden restaurarse en la segunda compilación; los crates no compatibles siguen compilándose. Eliminar las salidas de Cargo no elimina la caché local separada de Tuist. Esto verifica la reutilización, no necesariamente las descargas remotas: un acierto local no necesita una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, por lo que evitar la compilación no garantiza compilaciones más rápidas para crates pequeños.

Para comprobar que los aciertos son correctos, por ejemplo como canary en CI, establece cualquiera de las variables en `sampled` (un crate de cada 64, los mismos crates en cada compilación) o en `always`:

- `TUIST_CARGO_VERIFY` comprueba que las entradas por las que se indexó un acierto sigan siendo las que lee el compilador o el script de compilación.
- `TUIST_CARGO_VERIFY_RECOMPILE` compila los aciertos de nuevo y compara sus salidas con las almacenadas en caché.

Un crate verificado se compila en lugar de restaurarse, como si no estuviera en caché, por lo que sus salidas siempre son frescas y la verificación no cambia los resultados de la compilación. La verificación nunca almacena ni reemplaza la entrada de caché del crate verificado. Si sus salidas frescas difieren de las almacenadas en caché, los crates que dependen de él sufren fallos de caché y se almacenan en caché como en una compilación sin caché. Las compilaciones incrementales no son reproducibles, por lo que para ellas `TUIST_CARGO_VERIFY_RECOMPILE` compara solo metadatos e información de dependencias. Con `TUIST_DEBUG=1`, cada verificación imprime una línea `Tuist Cargo cache: verified`, y las verificaciones que encuentran una diferencia se cuentan como divergencias en las mediciones de caché de la compilación.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el panel de tu proyecto para inspeccionar las tasas de aciertos, las transferencias registradas, la latencia, el rendimiento y las compilaciones recientes. Abre la pestaña **Cache** de una compilación para ver las decisiones individuales de las tareas y las salidas CAS.

Las mediciones faltantes no se cuentan como cero y un acierto de caché no necesariamente implica una descarga remota. Consulta <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Mediciones de la caché de Rust</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de depuración para inspeccionar fallos en la transferencia de la caché y en los informes:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

La salida de depuración también explica por qué no se almacenó una compilación o una ejecución de script de compilación. Si no ves aciertos, comprueba que otro wrapper del compilador no tenga prioridad y que el compilador, las banderas y el entorno coincidan con la compilación que pobló la caché. Para las cargas remotas, verifica también la autenticación y la política de carga de caché de la cuenta.
