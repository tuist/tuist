---
{
  "title": "Hashing",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Cómo el hashing de Tuist impulsa la caché binaria y los tests selectivos."
}
---
# Hashing {#hashing}

Funcionalidades como <.localized_link href="/guides/features/cache">caché</.localized_link> o la ejecución de tests selectivos requieren una forma de determinar si un objetivo ha cambiado. Tuist calcula un hash para cada objetivo en el grafo de dependencias para determinar si un objetivo ha cambiado. El hash se calcula en función de los siguientes atributos:

- Los atributos del objetivo (por ejemplo, nombre, plataforma, producto, etc.)
- Los archivos del objetivo
- El hash de las dependencias del objetivo

### Atributos de caché {#cache-attributes}

Además, al calcular el hash para <.localized_link href="/guides/features/cache">caché</.localized_link>, también incluimos en el hash los siguientes atributos.

#### Versión de Swift {#swift-version}

Incluimos en el hash la versión de Swift obtenida al ejecutar el comando `/usr/bin/xcrun swift --version` para evitar errores de compilación debidos a discrepancias entre la versión de Swift de los objetivos y la de los binarios.

> [!NOTE]
> **Estabilidad de módulos**
>
> Las versiones anteriores de la caché de binarios dependían de la configuración de compilación `BUILD_LIBRARY_FOR_DISTRIBUTION` para habilitar la [estabilidad de módulos](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support) y permitir el uso de binarios con cualquier versión del compilador. Sin embargo, esto provocaba problemas de compilación en proyectos con objetivos que no admiten la estabilidad de módulos. Los binarios generados están vinculados a la versión de Swift utilizada para compilarlos, y la versión de Swift debe coincidir con la utilizada para compilar el proyecto.


#### Configuración {#configuration}

Al calcular los hashes de caché, Tuist limita la configuración de cada proyecto y objetivo a la configuración de compilación resuelta. Es decir, la que se indica con `--configuration`, de lo contrario la `defaultConfiguration` del proyecto, o bien la primera configuración de depuración. Tuist incluye en el hash el nombre, la variante, las opciones de compilación y el contenido del archivo de configuración de esa configuración, junto con las configuraciones base compartidas que le corresponden. Agregar, eliminar o modificar otra configuración no afecta a los hashes de caché de la configuración resuelta. Dado que solo importa la configuración resuelta, una caché poblada con un `--configuration` explícito es legible por un comando que resuelve a la misma configuración sin pasar la bandera.

## Depuración {#debugging}

Si observas comportamientos no deterministas al usar la caché entre entornos o invocaciones, podría deberse a diferencias entre los entornos o a un error en la lógica de hashing. Te recomendamos seguir estos pasos para depurar el problema:

1. Ejecuta `tuist hash cache` o `tuist hash selective-testing` (hashes para <.localized_link href="/guides/features/cache">caché de binarios</.localized_link> o <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link>), copia los hashes, cambia el nombre del directorio del proyecto y vuelve a ejecutar el comando. Los hashes deberían coincidir.
2. Si los hashes no coinciden, es probable que el proyecto generado dependa del entorno. Ejecuta `tuist graph --format json` en ambos casos y compara los grafos. Como alternativa, genera los proyectos y compara sus archivos `project.pbxproj` con una herramienta de diff como [Diffchecker](https://www.diffchecker.com).
3. Si los hashes son iguales pero difieren entre entornos (por ejemplo, CI y local), asegúrate de que se usa la misma [configuración](#configuration) y la misma [versión de Swift](#swift-version) en todas partes. La versión de Swift está vinculada a la versión de Xcode, así que confirma que las versiones de Xcode coincidan.

Si los hashes siguen siendo no deterministas, avísanos y podemos ayudarte con la depuración.


> [!NOTE]
> **Mejora de la experiencia de depuración planificada**
>
> Mejorar nuestra experiencia de depuración está en nuestra hoja de ruta. El comando print-hashes, que carece del contexto necesario para entender las diferencias, será reemplazado por un comando más fácil de usar que utiliza una estructura en forma de árbol para mostrar las diferencias entre los hashes.
