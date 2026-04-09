---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Configuración dinámica {#dynamic-configuration}

Hay ciertos escenarios en los que podrías necesitar configurar dinámicamente tu
proyecto en el momento de la generación. Por ejemplo, es posible que desee
cambiar el nombre de la aplicación, el identificador de paquete, o el objetivo
de despliegue basado en el entorno en el que se está generando el proyecto.
Tuist soporta esto a través de variables de entorno, a las que se puede acceder
desde los archivos de manifiesto.

## Configuración mediante variables de entorno {#configuration-through-environment-variables}

Tuist permite pasar la configuración a través de variables de entorno a las que
se puede acceder desde los ficheros de manifiesto. Por ejemplo:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Si desea pasar varias variables de entorno, sepárelas con un espacio. Por
ejemplo:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Lectura de las variables de entorno de los manifiestos {#reading-the-environment-variables-from-manifests}

Se puede acceder a las variables utilizando el tipo
<LocalizedLink href="/references/project-description/enums/environment">`Entorno`</LocalizedLink>.
Cualquier variable que siga la convención `TUIST_XXX` definida en el entorno o
pasada a Tuist al ejecutar comandos será accesible utilizando el tipo `Entorno`.
El siguiente ejemplo muestra cómo accedemos a la variable `TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

El acceso a las variables devuelve una instancia de tipo `Environment.Value?`
que puede tomar cualquiera de los siguientes valores:

| Caso              | Descripción                                          |
| ----------------- | ---------------------------------------------------- |
| `.string(Cadena)` | Se utiliza cuando la variable representa una cadena. |

También puede recuperar la cadena o booleano `Entorno` variable utilizando
cualquiera de los métodos de ayuda definidos a continuación, estos métodos
requieren un valor por defecto que se pasa a asegurar que el usuario obtiene
resultados consistentes cada vez. Esto evita la necesidad de definir la función
appName() definida anteriormente.

::: grupo de códigos

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
