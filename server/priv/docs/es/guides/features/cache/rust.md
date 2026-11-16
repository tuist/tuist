---
{
  "title": "Caché de Rust",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Reutiliza los resultados de compilación de Rust compatibles de forma local y a través de la caché remota de Tuist con Cargo."
}
---
# Caché de Rust {#rust-cache}

Tuist almacena en caché los resultados de compilación de Rust admitidos para que Cargo pueda reutilizarlos después de eliminar sus resultados de compilación. La caché está integrada en la CLI de Tuist. No hay ningún ejecutable de caché separado ni plugin de Cargo que instalar.

<!-- @snippet: ./_rust-experimental -->

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

El almacenamiento en caché es automático para las compilaciones elegibles. No hay configuración adicional de caché ni bandera de habilitación. Tuist descubre el endpoint de caché de tu cuenta y obtiene las credenciales de caché utilizando la configuración existente de tu proyecto y servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos ordinarios de `cargo`.

## Cómo funciona {#how-it-works}

Antes de que Cargo inicie, Tuist restaura los resultados de tus dependencias de registro y git que una compilación anterior produjo con la misma toolchain, perfil y configuración, para que Cargo los encuentre actualizados. Cargo sigue siendo responsable de decidir qué recompilar. Luego, para cada compilación elegible que Cargo aún ejecute, Tuist:

1. Comprueba su caché local para buscar resultados coincidentes.
2. En caso de fallo de caché local, consulta Kura a través de la Remote Execution API (REAPI), descarga cualquier contenido faltante y verifica los resultados antes de restaurarlos.
3. En caso de fallo de caché, ejecuta el compilador normalmente. Después de una compilación exitosa, almacena los resultados localmente y los sube a Kura a través de REAPI cuando esté autorizado. La entrada de caché remota se publica solo después de que todo su contenido referenciado esté disponible.

Las compilaciones en la misma máquina comparten la caché local, incluidas las compilaciones en otros worktrees o directorios de destino. Cuando otra compilación ya está compilando el mismo crate o ejecutando el mismo script de compilación, Tuist espera por ella y restaura sus resultados en lugar de hacer el mismo trabajo dos veces. Si esa compilación tarda más de 10 minutos, Tuist deja de esperar y compila el crate él mismo.

Las compilaciones locales y de CI utilizan el mismo protocolo de caché remota. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida de caché</.localized_link> de tu cuenta. Una cuenta puede permitir a los desarrolladores descargar mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: los resultados del compilador almacenados en caché son código ejecutable, así que otorga acceso de escritura solo a máquinas y tokens en los que confíes.

Si la configuración remota falla, el almacenamiento en caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas recurren a la compilación. Un fallo de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché admite:

- Crates de librería, incluidos crates de workspace y de ruta, crates con dependencias y crates con fuentes generadas. Tuist los indexa por las fuentes que leyó el compilador.
- En Macs con Apple silicon, compilaciones que la inspección de fuentes no puede indexar por adelantado, como crates que usan macros procedurales, ensamblador en línea o librerías nativas, las propias macros procedurales y ejecutables enlazados. Tuist registra los archivos, variables de entorno y comandos de solo lectura que lee cada uno, como `git describe`, y los indexa por ellos.
- En Macs con Apple silicon, ejecuciones de scripts de compilación, incluidas las compilaciones de C que realizan con el compilador predeterminado de Apple. Una ejecución se restaura solo cuando los archivos, el entorno y los comandos que leyó no han cambiado.
- Advertencias y otros diagnósticos, que un crate almacenado en caché muestra de nuevo.

Lo siguiente sigue compilándose normalmente:

- Scripts de compilación y compilaciones registradas en Linux.
- Scripts de compilación que se conectan a la red, inician programas que Tuist no puede observar o escriben fuera de su directorio de salida.
- Compilaciones incrementales, targets personalizados y argumentos de compilador o entradas de fuente no admitidos.
- Invocaciones de `cargo check` solo de metadatos.
- Compilaciones que emiten salida inesperada del compilador.
- Compilaciones que se ejecutan con configuraciones de cargador dinámico, como `LD_PRELOAD`, o con directorios de `LD_LIBRARY_PATH` fuera de la toolchain de Rust y del directorio de destino, por ejemplo, heredados de tu shell o un `build.build-dir` fuera del directorio de destino.

Un wrapper global de compilador preexistente deshabilita la caché de compilación de Tuist y el observador del compilador. Los wrappers personalizados de workspace también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad de herramientas de compilación</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la toolchain, los argumentos y el entorno de compilación. El checkout, el directorio de destino, el home de Cargo y las ubicaciones de la toolchain se reemplazan con marcadores de posición, por lo que un checkout en otra ruta reutiliza las mismas entradas. Un crate cuya salida incrusta su propia ruta, por ejemplo a través de `env!("CARGO_MANIFEST_DIR")`, se reutiliza solo en esa ruta. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Los crates que leen esas variables excluidas durante la compilación no se almacenan en caché.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar resultados actualizados. Para probar la caché de Tuist en lugar de los resultados existentes de Cargo, compila una vez, elimina los resultados de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las librerías elegibles pueden restaurarse en la segunda compilación; los crates no admitidos siguen compilándose. Eliminar los resultados de Cargo no elimina la caché local separada de Tuist. Esto verifica la reutilización, no necesariamente las descargas remotas: un acierto local no necesita una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, por lo que evitar la compilación no garantiza compilaciones más rápidas para crates pequeños.

Para comprobar que los aciertos son correctos, por ejemplo como prueba canaria en CI, establece cualquiera de las variables a `sampled` (un crate de cada 64, los mismos crates en cada compilación) o a `always`:

- `TUIST_CARGO_VERIFY` comprueba que las entradas por las que se indexó un acierto siguen siendo las que lee el compilador o el script de compilación.
- `TUIST_CARGO_VERIFY_RECOMPILE` compila de nuevo los aciertos y compara sus resultados con los almacenados en caché.

Un crate verificado se compila en lugar de restaurarse, como si no estuviera en caché, por lo que sus resultados siempre están actualizados y la verificación no cambia los resultados de la compilación. La verificación nunca almacena ni reemplaza la entrada de caché del crate verificado. Si sus resultados actualizados difieren de los almacenados en caché, los crates que dependen de él generan fallos de caché y se almacenan como en una compilación sin caché. Las compilaciones incrementales no son reproducibles, por lo que para esas `TUIST_CARGO_VERIFY_RECOMPILE` solo compara metadatos e información de dependencias. Con `TUIST_DEBUG=1`, cada verificación imprime una línea `Tuist Cargo cache: verified`, y las verificaciones que encuentran una diferencia se cuentan como divergencias en las mediciones de caché de la compilación.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el panel de tu proyecto para inspeccionar las tasas de aciertos, las transferencias registradas, la latencia, el rendimiento y las compilaciones recientes. Abre la pestaña **Cache** de una compilación para ver las decisiones individuales de las tareas y los resultados de CAS.

Las mediciones faltantes no se cuentan como cero, y un acierto de caché no significa necesariamente una descarga remota. Consulta <.localized_link href="/guides/features/build-insights/rust#cache-measurements">mediciones de caché de Rust</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de depuración para inspeccionar fallos de transferencia de caché y de informes:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

La salida de depuración también explica por qué no se almacenó una compilación o una ejecución de script de compilación. Si no ves aciertos, comprueba que otro wrapper de compilador no esté teniendo prioridad y que el compilador, las flags y el entorno coincidan con la compilación que pobló la caché. Para cargas remotas, comprueba también la autenticación y la política de carga de caché de la cuenta.
