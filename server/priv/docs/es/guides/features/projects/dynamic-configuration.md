---
{
  "title": "Configuración dinámica",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar variables de entorno para configurar tu proyecto de forma dinámica."
}
---
# Configuración dinámica {#dynamic-configuration}

Hay ciertos escenarios en los que podrías necesitar configurar tu proyecto dinámicamente durante la generación. Por ejemplo, es posible que quieras cambiar el nombre de la app, el identificador del bundle o el destino de despliegue en función del entorno donde se está generando el proyecto. Tuist lo admite mediante variables de entorno, a las que se puede acceder desde los archivos de manifiesto.

## Configuración mediante variables de entorno {#configuration-through-environment-variables}

Tuist permite pasar configuración a través de variables de entorno a las que se puede acceder desde los archivos de manifiesto. Por ejemplo:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Si quieres pasar varias variables de entorno, sepáralas con un espacio. Por ejemplo:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Lectura de las variables de entorno desde los manifiestos {#reading-the-environment-variables-from-manifests}

Se puede acceder a las variables usando el tipo [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment). Cualquier variable que siga la convención `TUIST_XXX` definida en el entorno o pasada a Tuist al ejecutar comandos será accesible mediante el tipo `Environment`. El siguiente ejemplo muestra cómo accedemos a la variable `TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Acceder a las variables devuelve una instancia del tipo `Environment.Value?` que puede tomar cualquiera de los siguientes valores:

| Caso | Descripción |
| --- | --- |
| `.string(String)` | Se usa cuando la variable representa una cadena. |

También puedes recuperar la variable `Environment` de tipo string o boolean usando cualquiera de los métodos auxiliares definidos a continuación; estos métodos requieren que se pase un valor predeterminado para garantizar que el usuario obtenga resultados consistentes cada vez. Esto evita la necesidad de definir la función appName() mostrada arriba.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::

## Reenvío de variables de entorno adicionales a los manifiestos {#forwarding-additional-environment-variables-to-manifests}

De forma predeterminada, solo las variables con el prefijo `TUIST_`, además de `CI` y `DEVELOPER_DIR`, se reenvían al subproceso que evalúa `Project.swift`, `Workspace.swift`, `Package.swift` y los ayudantes de descripción del proyecto. Esto mantiene la generación determinista y evita que variables no relacionadas del shell o de CI invaliden la caché del manifiesto.

Cuando un manifiesto necesita leer variables que no están bajo tu control (por ejemplo, un `Package.swift` de terceros que ya lee `OPENSWIFTUI_LIBRARY_TYPE`), decláralas en `Tuist.swift` mediante `manifestEnvironment` en las opciones de generación. Cada entrada es bien un nombre literal o un nombre que termina en `*` para coincidencia por prefijo:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

Las variables listadas participan en el hash de la caché del manifiesto, por lo que los cambios en sus valores invalidan la caché como se espera. Las variables no listadas permanecen ocultas para la evaluación del manifiesto.
