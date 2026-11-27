---
{
  "title": "Caché de compilación de Cargo para Rust",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Reduce a la mitad el tiempo de compilación de Rust en CI y en clones nuevos con la caché de compilación de Cargo de Tuist, que reutiliza los resultados de compilación localmente y a través de una caché remota."
}
---
# Caché de compilación de Cargo para Rust {#rust-cache}

Tuist almacena en caché los resultados de compilación de Rust compatibles para que Cargo pueda reutilizarlos después de que se eliminen sus resultados de compilación, como tras ejecutar `cargo clean`, cambiar de rama o en otro checkout. También puedes ver esto denominado como caché de compilación de Cargo o caché de compilación de Rust: reduce los tiempos de compilación de Rust al reutilizar lo que una compilación anterior generó, incluidas las crates de tu espacio de trabajo compiladas de forma incremental. La caché está integrada en la CLI de Tuist. No hay un ejecutable de caché separado ni un plugin de Cargo que instalar.

<!-- @snippet: ./_rust-experimental -->

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

La caché es automática para las compilaciones elegibles. No hay configuración adicional de caché ni bandera de habilitación. Tuist descubre el extremo de caché de tu cuenta y obtiene las credenciales de caché usando la configuración existente de tu proyecto y servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos ordinarios de `cargo`.

## Cómo funciona {#how-it-works}

Antes de que Cargo inicie, Tuist restaura los resultados de tus dependencias de registro y git que una compilación anterior produjo con la misma toolchain, perfil y configuración, de modo que Cargo los encuentra actualizados. Cargo sigue siendo responsable de decidir qué recompilar. Luego, para cada compilación elegible que Cargo aún ejecuta, Tuist:

1. Comprueba su caché local para buscar resultados coincidentes.
2. En caso de fallo de caché local, consulta Kura a través de la Remote Execution API (REAPI), descarga cualquier contenido faltante y verifica los resultados antes de restaurarlos.
3. En caso de fallo de caché, ejecuta el compilador. Tras una compilación exitosa, almacena los resultados localmente y los sube a Kura a través de REAPI cuando está autorizado. La entrada de caché remota se publica solo después de que todo su contenido referenciado esté disponible.

En CI, la primera compilación de una crate en un directorio de destino se ejecuta sin compilación incremental, como ya hace Cargo 1.99 y versiones posteriores por defecto: no hay una sesión anterior para reutilizar, CI no edita lo que compiló y crear una sesión hace que esa compilación sea más lenta y su entrada de caché más grande. Tuist recuerda la crate en el directorio de destino, de modo que un job que mantenga su directorio de destino la compila de forma incremental la próxima vez. Las compilaciones locales se compilan de forma incremental según lo solicite Cargo, por lo que la primera edición tras una compilación limpia sigue siendo rápida. Las entradas de caché se comparten en ambos casos.

Las compilaciones en la misma máquina comparten la caché local, incluidas las compilaciones en otros worktrees o directorios de destino. Cuando otra compilación ya está compilando la misma crate o ejecutando el mismo script de compilación, Tuist espera a que termine y restaura sus resultados en lugar de hacer el mismo trabajo dos veces. Si esa compilación tarda más de 10 minutos, Tuist deja de esperar y compila la crate por sí mismo.

Las compilaciones locales y de CI usan el mismo protocolo de caché remota. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida de caché</.localized_link> de tu cuenta. Una cuenta puede permitir a los desarrolladores descargar mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: los resultados del compilador almacenados en caché son código ejecutable, así que otorga acceso de escritura solo a máquinas y tokens en los que confíes.

Si la configuración remota falla, la caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas recurren a la compilación. Un fallo de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché admite:

- Crates de biblioteca, incluidas las crates de espacio de trabajo y de ruta, crates con dependencias y crates con fuentes generadas. Tuist las identifica mediante las fuentes que leyó el compilador.
- `cargo check` y `cargo clippy`, que compilan bibliotecas solo a metadatos. Sus entradas son independientes de las de las compilaciones, por lo que un check nunca proporciona una biblioteca a `cargo build`. Las dependencias que `cargo clippy` compila con el compilador estándar, como las crates de ruta fuera del espacio de trabajo, reutilizan las entradas de `cargo check`.
- En Macs con Apple silicon y en Linux x86_64 y arm64 con glibc, compilaciones que la inspección de fuentes no puede identificar por adelantado, como crates que usan macros procedimentales, ensamblador en línea o bibliotecas nativas, las propias macros procedimentales y ejecutables enlazados. Tuist registra los archivos, variables de entorno y comandos de solo lectura que lee cada uno, como `git describe`, y los identifica mediante ellos. En Linux, el enlazador del sistema, la biblioteca C y los archivos de inicio que lee un enlace forman parte de su clave.
- En las mismas plataformas, ejecuciones de scripts de compilación, incluidas las compilaciones de C que realizan (con el compilador predeterminado de Apple en macOS, con cualquier compilador enlazado dinámicamente en Linux). Una ejecución se restaura solo cuando los archivos, el entorno y los comandos que leyó no han cambiado.
- Advertencias y otros diagnósticos, que una crate en caché vuelve a mostrar, incluidos los lints de Clippy.

Lo siguiente sigue compilándose con normalidad:

- Scripts de compilación y compilaciones registradas en distribuciones de Linux sin glibc, como Alpine.
- Scripts de compilación que se conectan a la red, inician programas que Tuist no puede observar (en Linux, programas enlazados estáticamente) o escriben fuera de su directorio de salida.
- Targets personalizados y argumentos de compilador o entradas de fuente no compatibles.
- Compilaciones de Clippy de macros procedimentales y scripts de compilación, y ejecuciones de Clippy que habilitan el grupo de lints `cargo`, que lee cada manifiesto del espacio de trabajo y su archivo de bloqueo a través de `cargo metadata`.
- Compilaciones que emiten resultados inesperados del compilador.
- Compilaciones que se ejecutan con configuraciones del cargador dinámico, como `LD_PRELOAD`, o con directorios de `LD_LIBRARY_PATH` fuera de la toolchain de Rust y del directorio de destino, por ejemplo, heredados de tu shell o un `build.build-dir` fuera del directorio de destino.

Un wrapper global del compilador preexistente deshabilita la caché de compilación y el observador del compilador de Tuist. Los wrappers personalizados del espacio de trabajo distintos al de Clippy también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad de herramientas del compilador</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la toolchain, los argumentos y el entorno de compilación. Las entradas de Clippy también dependen de la versión de Clippy, los argumentos de lint en `CLIPPY_ARGS`, `CLIPPY_CONF_DIR`, `CLIPPY_DISABLE_DOCS_LINKS`, el `Cargo.toml` del paquete y el `clippy.toml` o `.clippy.toml` que carga Clippy. Las ubicaciones del checkout, el directorio de destino, el home de Cargo y la toolchain se reemplazan con marcadores de posición, por lo que un checkout en otra ruta reutiliza las mismas entradas. Una crate cuya salida incrusta su propia ruta, por ejemplo a través de `env!("CARGO_MANIFEST_DIR")`, solo se reutiliza en esa ruta. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Las crates que leen esas variables excluidas durante la compilación no se almacenan en caché.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar las salidas actualizadas. Para poner a prueba la caché de Tuist en lugar de usar las salidas existentes de Cargo, compila una vez, elimina las salidas de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las bibliotecas elegibles pueden restaurarse en la segunda compilación; las crates no compatibles siguen compilándose. Eliminar las salidas de Cargo no elimina la caché local independiente de Tuist. Esto verifica la reutilización, no necesariamente las descargas remotas: un acierto local no necesita una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, por lo que evitar la compilación no garantiza compilaciones más rápidas para crates pequeñas.

Para comprobar que los aciertos son correctos, por ejemplo como prueba canaria en CI, establece cualquiera de las variables en `sampled` (una crate de cada 64, las mismas crates en cada compilación) o en `always`:

- `TUIST_CARGO_VERIFY` comprueba que las entradas por las que se indexó un acierto sigan siendo las que lee el compilador o el script de compilación.
- `TUIST_CARGO_VERIFY_RECOMPILE` vuelve a compilar los aciertos y compara sus salidas con las almacenadas en caché.

Una crate verificada se compila en lugar de restaurarse, como si no estuviera en caché, por lo que sus salidas siempre están actualizadas y la verificación no cambia los resultados de la compilación. La verificación nunca almacena ni reemplaza la entrada de caché de la crate verificada. Si sus salidas actualizadas difieren de las almacenadas en caché, las crates que dependen de ella generan fallos de caché y se almacenan como en una compilación sin caché. Las compilaciones incrementales no son reproducibles, por lo que para ellas `TUIST_CARGO_VERIFY_RECOMPILE` compara solo los metadatos y la información de dependencias. Con `TUIST_DEBUG=1`, cada verificación imprime una línea `Tuist Cargo cache: verified`, y las verificaciones que encuentran una diferencia se cuentan como divergencias en las mediciones de caché de la compilación.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el panel de tu proyecto para inspeccionar las tasas de acierto, las transferencias registradas, la latencia, el rendimiento y las compilaciones recientes. Abre la pestaña **Cache** de una compilación para ver las decisiones individuales de las tareas y las salidas de CAS.

Las mediciones faltantes no se cuentan como cero y un acierto de caché no significa necesariamente una descarga remota. Consulta <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Mediciones de caché de Rust</.localized_link> para obtener más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de depuración para inspeccionar los fallos de transferencia de caché y de informes:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

La salida de depuración también explica por qué no se almacenó una compilación o una ejecución de script de compilación. Si no ves aciertos, comprueba que otro wrapper del compilador no tenga prioridad y que el compilador, las banderas y el entorno coincidan con la compilación que pobló la caché. Para las cargas remotas, verifica también la autenticación y la política de carga de caché de la cuenta.
