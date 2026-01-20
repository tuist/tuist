---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Recopila insights {#gather-insights}

Tuist puede integrarse con un servidor para ampliar sus capacidades. Una de esas
capacidades es recopilar información sobre tu proyecto y tus construcciones.
Todo lo que necesitas es tener una cuenta con un proyecto en el servidor.

En primer lugar, tendrás que autenticarte ejecutando:

```bash
tuist auth login
```

## Crear un proyecto {#create-a-project}

A continuación, puede crear un proyecto ejecutando:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Copie `my-handle/MyApp`, que representa el "handle" completo del proyecto.

## Conectar proyectos {#connect-projects}

Después de crear el proyecto en el servidor, tendrás que conectarlo a tu
proyecto local. Ejecuta `tuist edit` y edita el archivo `Tuist.swift` para
incluir el handle completo del proyecto:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

¡Voilà! Ya estás listo para recopilar información sobre tu proyecto y tus
compilaciones. Ejecute `tuist test` para ejecutar las pruebas e informar de los
resultados al servidor.

::: info
<!-- -->
Tuist pone en cola los resultados localmente e intenta enviarlos sin bloquear el
comando. Por lo tanto, es posible que no se envíen inmediatamente después de que
finalice el comando. En CI, los resultados se envían inmediatamente.
<!-- -->
:::


![Una imagen que muestra una lista de ejecuciones en el
servidor](/images/guides/quick-start/runs.png)

Disponer de datos de tus proyectos y construcciones es crucial para tomar
decisiones informadas. Tuist seguirá ampliando sus capacidades, y tú te
beneficiarás de ellas sin tener que cambiar la configuración de tu proyecto.
Mágico, ¿verdad? 🪄
