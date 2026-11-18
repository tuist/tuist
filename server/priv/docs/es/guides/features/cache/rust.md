---
{
  "title": "Caché de Rust",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Reutiliza los resultados de compilación compatibles de Rust localmente y a través de la caché remota de Tuist con Cargo."
}
---
# Caché de Rust {#rust-cache}

Tuist almacena en caché las salidas de compilación de Rust admitidas para que Cargo pueda reutilizarlas después de eliminar sus resultados de compilación. La caché está integrada en la CLI de Tuist. No hay ningún ejecutable de caché separado ni plugin de Cargo que instalar.

<!-- @snippet: ./_rust-experimental -->

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

La caché es automática para las compilaciones elegibles. No hay configuración adicional de caché ni bandera de habilitación. Tuist descubre el extremo de caché de tu cuenta y obtiene las credenciales de caché usando la configuración existente de tu proyecto y servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos normales de `cargo`.

## Cómo funciona {#how-it-works}

Antes de que Cargo inicie, Tuist restaura las salidas de tus dependencias de registro y git que una compilación anterior produjo con la misma cadena de herramientas, perfil y configuración, para que Cargo las encuentre actualizadas. Cargo sigue siendo responsable de decidir qué recompilar. Luego, para cada compilación elegible que Cargo aún ejecute, Tuist:

1. Comprueba su caché local para buscar salidas coincidentes.
2. En caso de fallo de caché local, consulta Kura a través de la API de Ejecución Remota (REAPI), descarga cualquier contenido faltante y verifica las salidas antes de restaurarlas.
3. En caso de fallo de caché, ejecuta el compilador normalmente. Después de una compilación exitosa, almacena las salidas localmente y las sube a Kura a través de REAPI cuando esté autorizado. La entrada de caché remota se publica solo después de que todo su contenido referenciado esté disponible.

Las compilaciones locales y de CI usan el mismo protocolo de caché remota. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida de caché</.localized_link> de tu cuenta. Una cuenta puede permitir que los desarrolladores descarguen mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: las salidas del compilador almacenadas en caché son código ejecutable, así que otorga acceso de escritura solo a máquinas y tokens en los que confíes.

Si la configuración remota falla, la caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas vuelven a la compilación. Un fallo de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché admite:

- Crates de biblioteca, incluidos crates de espacio de trabajo y de ruta, crates con dependencias y crates con fuentes generadas. Tuist los indexa por las fuentes que leyó el compilador.
- En Macs con Apple Silicon, compilaciones que la inspección de fuentes no puede indexar por adelantado, como crates que usan macros procedimentales, ensamblador en línea o bibliotecas nativas, las propias macros procedimentales y ejecutables enlazados. Tuist registra los archivos, variables de entorno y comandos de solo lectura que lee cada uno, como `git describe`, y los indexa por ellos.
- En Macs con Apple Silicon, ejecuciones de scripts de compilación, incluidas las compilaciones de C que realizan con el compilador predeterminado de Apple. Una ejecución se restaura solo cuando los archivos, el entorno y los comandos que leyó no han cambiado.
- Advertencias y otros diagnósticos, que un crate almacenado en caché muestra de nuevo.

Lo siguiente sigue compilándose normalmente:

- Scripts de compilación y compilaciones registradas en Linux.
- Scripts de compilación que se conectan a la red, inician programas que Tuist no puede observar o escriben fuera de su directorio de salida.
- Compilaciones incrementales, objetivos personalizados y argumentos de compilador o entradas de fuente no admitidos.
- Invocaciones de `cargo check` solo de metadatos.
- Compilaciones que emiten salida inesperada del compilador.

Un wrapper de compilador global preexistente deshabilita la caché de compilación de Tuist y el observador del compilador. Los wrappers de espacio de trabajo personalizados también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad de herramientas de compilador</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la cadena de herramientas, los argumentos y el entorno de compilación. Las ubicaciones del checkout, directorio objetivo, home de Cargo y cadena de herramientas se reemplazan con marcadores de posición, por lo que un checkout en otra ruta reutiliza las mismas entradas. Un crate cuya salida incorpora su propia ruta, por ejemplo a través de `env!("CARGO_MANIFEST_DIR")`, se reutiliza solo en esa ruta. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Los crates que leen esas variables excluidas durante la compilación no se almacenan en caché.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar salidas actualizadas. Para ejercitar la caché de Tuist en lugar de las salidas existentes de Cargo, compila una vez, elimina las salidas de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las bibliotecas elegibles pueden restaurarse en la segunda compilación; los crates no admitidos siguen compilándose. Eliminar las salidas de Cargo no elimina la caché local separada de Tuist. Esto verifica la reutilización, no necesariamente las descargas remotas: un acierto de caché local no necesita una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, por lo que evitar la compilación no garantiza compilaciones más rápidas para crates pequeños.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el panel de tu proyecto para inspeccionar tasas de aciertos, transferencias registradas, latencia, rendimiento y compilaciones recientes. Abre la pestaña **Caché** de una compilación para ver decisiones de tareas individuales y salidas CAS.

Las mediciones faltantes no se cuentan como cero, y un acierto de caché no significa necesariamente una descarga remota. Consulta <.localized_link href="/guides/features/build-insights/rust#cache-measurements">mediciones de caché de Rust</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de depuración para inspeccionar fallos de transferencia y reporte de caché:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

La salida de depuración también explica por qué no se almacenó una compilación o una ejecución de script de compilación. Si no ves aciertos, verifica que otro wrapper de compilador no tenga prioridad y que el compilador, las banderas y el entorno coincidan con la compilación que pobló la caché. Para subidas remotas, verifica también la autenticación y la política de subida de caché de la cuenta.
