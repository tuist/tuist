---
{
  "title": "Caché de Rust",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Reutiliza los resultados de compilación compatibles de Rust de forma local y a través de la caché remota de Tuist con Cargo."
}
---
# Caché de Rust {#rust-cache}

Tuist almacena en caché los resultados de compilación de Rust compatibles para que Cargo pueda reutilizarlos después de eliminar sus artefactos de compilación. La caché está integrada en la CLI de Tuist. No hay ningún ejecutable de caché separado ni plugin de Cargo que instalar.

> [!WARNING] Experimental compilation cache
> La versión actual solo almacena en caché las bibliotecas hoja del registro: crates de biblioteca descargados desde un registro de Cargo que no dependen de otros crates. Las demás compilaciones se ejecutan con normalidad. Las claves de caché conservan las rutas absolutas y las variables de entorno, por lo que aún no se admite la reutilización entre distintas ubicaciones de checkout.

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

La caché es automática para las compilaciones elegibles. No hace falta configuración adicional ni ninguna bandera de habilitación. Tuist detecta el extremo de caché de tu cuenta y obtiene las credenciales de caché usando la configuración existente de tu proyecto y del servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos `cargo` habituales.

## Cómo funciona {#how-it-works}

Para cada compilación elegible, Tuist:

1. Comprueba su caché local en busca de resultados coincidentes.
2. En caso de fallo de caché local, consulta Kura a través de la Remote Execution API (REAPI), descarga el contenido faltante y verifica los resultados antes de restaurarlos.
3. En caso de fallo de caché, ejecuta el compilador con normalidad. Tras una compilación exitosa, almacena los resultados localmente y los sube a Kura mediante REAPI cuando está autorizado. La entrada de caché remota se publica solo cuando todo su contenido referenciado está disponible.

Las compilaciones locales y de CI usan el mismo protocolo de caché remoto. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida a la caché</.localized_link> de tu cuenta. Una cuenta puede permitir que los desarrolladores descarguen mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: las salidas del compilador almacenadas en caché son código ejecutable, así que otorga acceso de escritura solo a máquinas y tokens en los que confíes.

Si la configuración remota falla, la caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas recurren a la compilación. Un error de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché actual admite bibliotecas hoja del registro elegibles que producen artefactos de biblioteca de Rust, junto con sus metadatos asociados, información de dependencias y resultados de depuración dividida admitidos.

Lo siguiente sigue compilándose con normalidad:

- Crates de workspace y bibliotecas con dependencias de otros crates.
- Scripts de compilación, macros procedimentales y crates que dependen de sus resultados.
- Ejecutables, binarios de test, enlace nativo y compilaciones de C/C++.
- Compilaciones incrementales, targets personalizados y argumentos del compilador o entradas de origen no admitidos.
- Invocaciones de `cargo check` solo de metadatos.
- Compilaciones que emiten diagnósticos renderizados o salida inesperada del compilador.

Un wrapper global del compilador preexistente deshabilita la caché de compilación de Tuist y el observador del compilador. Los wrappers personalizados del workspace también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad con herramientas del compilador</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la toolchain, los argumentos, el directorio de trabajo y el entorno de compilación. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Los crates que leen esas variables excluidas durante la compilación no se almacenan en caché. Mantén consistentes las demás entradas y sus rutas absolutas al probar la reutilización. El soporte de transporte remoto no hace que los resultados sean reubicables entre distintas rutas de checkout.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar resultados actualizados. Para ejercitar la caché de Tuist en lugar de usar los resultados existentes de Cargo, compila una vez, elimina los resultados de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las bibliotecas elegibles pueden restaurarse en la segunda compilación; los crates no admitidos siguen compilándose. Eliminar los resultados de Cargo no elimina la caché local independiente de Tuist. Esto comprueba la reutilización, no necesariamente las descargas remotas: un acierto de caché local no requiere una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, así que evitar la compilación no garantiza compilaciones más rápidas para crates pequeños.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el panel de tu proyecto para inspeccionar las tasas de aciertos, las transferencias registradas, la latencia, el throughput y las compilaciones recientes. Abre la pestaña **Caché** de una compilación para ver las decisiones individuales de tareas y los resultados CAS.

Las mediciones faltantes no se cuentan como cero, y un acierto de caché no significa necesariamente una descarga remota. Consulta las <.localized_link href="/guides/features/build-insights/rust#cache-measurements">mediciones de la caché de Rust</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de depuración para inspeccionar fallos de transferencia y de informe de la caché:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Si no ves aciertos, comprueba que tu compilación contenga bibliotecas hoja del registro elegibles, que otro wrapper del compilador no tenga prioridad y que el compilador, las banderas, el entorno y las rutas coincidan con la compilación que pobló la caché. Para las subidas remotas, verifica también la autenticación y la política de subida a la caché de la cuenta.
