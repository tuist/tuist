---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Configuración dinámica {#dynamic-configuration}

Hay ciertos casos en los que es posible que necesites configurar dinámicamente
tu proyecto en el momento de la generación. Por ejemplo, es posible que quieras
cambiar el nombre de la aplicación, el identificador del paquete o el destino de
implementación en función del entorno en el que se genere el proyecto. Tuist lo
permite mediante variables de entorno, a las que se puede acceder desde los
archivos de manifiesto.

## Configuración mediante variables de entorno {#configuration-through-environment-variables}

Tuist permite pasar la configuración a través de variables de entorno a las que
se puede acceder desde los archivos de manifiesto. Por ejemplo:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Si quieres pasar varias variables de entorno, simplemente sepáralas con un
espacio. Por ejemplo:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Lectura de las variables de entorno de los manifiestos {#reading-the-environment-variables-from-manifests}

Se puede acceder a las variables utilizando el tipo
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
Cualquier variable que siga la convención `TUIST_XXX` definida en el entorno o
pasada a Tuist al ejecutar comandos será accesible utilizando el tipo
`Environment`. El siguiente ejemplo muestra cómo accedemos a la variable
`TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Al acceder a las variables se devuelve una instancia de tipo
`Environment.Value?` que puede tomar cualquiera de los siguientes valores:

| Mayúsculas y minúsculas | Descripción                                          |
| ----------------------- | ---------------------------------------------------- |
| `.string(String)`       | Se utiliza cuando la variable representa una cadena. |

También puedes recuperar la cadena o el valor booleano de la variable de entorno
`Environment` utilizando cualquiera de los métodos auxiliares definidos a
continuación; estos métodos requieren que se les pase un valor predeterminado
para garantizar que el usuario obtenga resultados coherentes en cada ocasión.
Esto evita la necesidad de definir la función appName() definida anteriormente.

::: grupo de códigos

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
