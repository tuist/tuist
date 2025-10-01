---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# Hashing {#hashing}

Características como
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> o la
ejecución selectiva de pruebas requieren una forma de determinar si un objetivo
ha cambiado. Tuist calcula un hash para cada objetivo en el grafo de dependencia
para determinar si un objetivo ha cambiado. El hash se calcula basándose en los
siguientes atributos:

- Los atributos del objetivo (por ejemplo, nombre, plataforma, producto, etc.)
- Los archivos del objetivo
- El hash de las dependencias del objetivo

### Atributos de caché {#cache-attributes}

Además, al calcular el hash para
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink>, también
hacemos hash de los siguientes atributos.

#### Versión de Swift {#swift-version}

Hacemos hash de la versión de Swift obtenida al ejecutar el comando
`/usr/bin/xcrun swift --version` para evitar errores de compilación debidos a
desajustes de versión de Swift entre los objetivos y los binarios.

> [NOTA] ESTABILIDAD DE MÓDULOS Las versiones anteriores del almacenamiento en
> caché de binarios se basaban en el ajuste de compilación
> `BUILD_LIBRARY_FOR_DISTRIBUTION` para activar la [estabilidad de
> módulos](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
> y permitir el uso de binarios con cualquier versión del compilador. Sin
> embargo, causaba problemas de compilación en proyectos con objetivos que no
> soportan la estabilidad de módulos. Los binarios generados están vinculados a
> la versión de Swift utilizada para compilarlos, y la versión de Swift debe
> coincidir con la utilizada para compilar el proyecto.

#### Configuración {#configuration}

La idea detrás de la bandera `-configuration` era asegurar que los binarios de
depuración no se utilizaran en las compilaciones de lanzamiento y viceversa. Sin
embargo, todavía nos falta un mecanismo para eliminar las otras configuraciones
de los proyectos para evitar que se utilicen.

## Depuración {#debugging}

Si observas comportamientos no deterministas al utilizar la caché en distintos
entornos o invocaciones, puede estar relacionado con diferencias entre los
entornos o con un error en la lógica de hash. Te recomendamos que sigas estos
pasos para depurar el problema:

1. Asegúrese de que se utiliza la misma [configuración](#configuration) y
   [versión Swift](#swift-version) en todos los entornos.
2. Compruebe si existen diferencias entre los proyectos Xcode generados por dos
   invocaciones consecutivas de `tuist generate` o entre entornos. Puede
   utilizar el comando `diff` para comparar los proyectos. Los proyectos
   generados pueden incluir **rutas absolutas** causando que la lógica hash no
   sea determinista.

> [La mejora de nuestra experiencia de depuración está en nuestra hoja de ruta.
> El comando print-hashes, que carece de contexto para entender las diferencias,
> será sustituido por un comando más fácil de usar que utilice una estructura en
> forma de árbol para mostrar las diferencias entre los hashes.
