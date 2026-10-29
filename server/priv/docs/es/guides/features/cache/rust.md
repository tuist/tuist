---
{
  "title": "Rust cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Reuse supported Rust compilation outputs locally and through Tuist's remote cache with Cargo."
}
---
# Caché de Rust {#rust-cache}

Tuist almacena en caché los resultados de compilación de Rust compatibles para que Cargo pueda reutilizarlos después de que se hayan eliminado sus resultados de compilación. La caché está integrada en la CLI de Tuist. No hay un ejecutable de caché separado ni un plugin de Cargo que instalar.

> [!WARNING] Experimental compilation cache
> La versión actual solo almacena en caché las bibliotecas hoja del registro: crates de biblioteca descargados desde un registro de Cargo que no dependen de otros crates. Otras compilaciones se ejecutan normalmente. Las claves de caché conservan rutas absolutas y entradas del entorno, por lo que aún no se admite la reutilización entre diferentes ubicaciones de checkout.

## Habilitar la caché {#enable-caching}

Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte. Luego, ejecuta tu compilación a través de Tuist:

```sh
tuist cargo build --release
```

La caché es automática para las compilaciones elegibles. No hay configuración adicional de caché ni bandera de habilitación. Tuist descubre el endpoint de caché de tu cuenta y obtiene las credenciales de caché utilizando la configuración existente de tu proyecto y servidor.

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir escribiendo comandos `cargo` ordinarios.

## Cómo funciona {#how-it-works}

Para cada compilación elegible, Tuist:

1. Comprueba su caché local para buscar resultados coincidentes.
2. En caso de fallo local, consulta a Kura a través de la API de Ejecución Remota (REAPI), descarga cualquier contenido faltante y verifica los resultados antes de restaurarlos.
3. En caso de fallo de caché, ejecuta el compilador normalmente. Después de una compilación exitosa, almacena los resultados localmente y los sube a Kura a través de REAPI cuando está autorizado. La entrada de caché remota se publica solo después de que todo su contenido referenciado esté disponible.

Las compilaciones locales y de CI utilizan el mismo protocolo de caché remota. El acceso de lectura y escritura proviene de las credenciales de caché emitidas por el servidor de Tuist y de la <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida de caché</.localized_link> de tu cuenta. Una cuenta puede permitir que los desarrolladores descarguen mientras restringe las subidas a CI y tokens de cuenta. Los escritores de caché son productores de código de confianza: los resultados del compilador almacenados en caché son código ejecutable, por lo que solo concede acceso de escritura a máquinas y tokens en los que confíes.

Si la configuración remota falla, la caché local sigue estando disponible. Las entradas de caché no disponibles, faltantes o corruptas vuelven a la compilación. Un fallo de subida no hace fallar la compilación ni descarta su entrada de caché local.

## Qué se puede almacenar en caché {#what-can-be-cached}

La caché actual admite bibliotecas hoja del registro elegibles que producen artefactos de biblioteca de Rust y sus metadatos adjuntos, información de dependencias y resultados de depuración dividida compatibles.

Lo siguiente sigue compilándose normalmente:

- Crates de workspace y bibliotecas con dependencias de otros crates.
- Scripts de compilación, macros procedurales y crates que dependen de sus resultados.
- Ejecutables, binarios de tests, enlace nativo y compilaciones de C/C++.
- Compilaciones incrementales, objetivos personalizados y argumentos del compilador o entradas de origen no compatibles.
- Invocaciones de `cargo check` solo de metadatos.
- Compilaciones que emiten diagnósticos renderizados o salida inesperada del compilador.

Un wrapper de compilador global preexistente deshabilita la caché de compilación de Tuist y el observador del compilador. Los wrappers de workspace personalizados también omiten la caché. Consulta la <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compatibilidad de herramientas del compilador</.localized_link>.

Las claves de caché incluyen el contenido del paquete, el compilador y la toolchain, los argumentos, el directorio de trabajo y el entorno de compilación. Las credenciales, la configuración de informes de Tuist y los metadatos reconocidos de ejecución de CI no invalidan las entradas. Los crates que leen esas variables excluidas durante la compilación no se almacenan en caché. Mantén las otras entradas y sus rutas absolutas consistentes al probar la reutilización. El soporte de transporte remoto no hace que los resultados sean reubicables entre diferentes rutas de checkout.

## Verificar la reutilización {#verify-reuse}

Cargo ya evita recompilar resultados actualizados. Para ejercitar la caché de Tuist en lugar de los resultados existentes de Cargo, compila una vez, elimina los resultados de Cargo y luego repite la misma compilación:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Las bibliotecas elegibles pueden restaurarse en la segunda compilación; los crates no compatibles siguen compilándose. Eliminar los resultados de Cargo no elimina la caché local separada de Tuist. Esto verifica la reutilización, no necesariamente las descargas remotas: un acierto local no necesita una transferencia desde Kura. La validación de entradas y las operaciones de caché añaden sobrecarga, por lo que evitar la compilación no garantiza compilaciones más rápidas para crates pequeños.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Cargo Cache** en el dashboard de tu proyecto para inspeccionar las tasas de aciertos, las transferencias registradas, la latencia, el rendimiento y las compilaciones recientes. Abre la pestaña **Cache** de una compilación para ver las decisiones de tareas individuales y los resultados CAS.

Las mediciones faltantes no se cuentan como cero, y un acierto de caché no significa necesariamente una descarga remota. Consulta las <.localized_link href="/guides/features/build-insights/rust#cache-measurements">mediciones de la caché de Rust</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

Habilita la salida de debug para inspeccionar fallos de transferencia y reporting de la caché:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Si no ves aciertos, verifica que tu compilación contenga bibliotecas hoja del registro elegibles, que otro wrapper del compilador no esté teniendo prioridad y que el compilador, las banderas, el entorno y las rutas coincidan con la compilación que pobló la caché. Para las subidas remotas, verifica también la autenticación y la política de subida de caché de la cuenta.
