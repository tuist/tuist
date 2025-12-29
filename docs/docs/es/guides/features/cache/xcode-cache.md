---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Caché de Xcode {#xcode-cache}

Tuist es compatible con la caché de compilación de Xcode, lo que permite a los
equipos compartir artefactos de compilación aprovechando las capacidades de
almacenamiento en caché del sistema de compilación.

## Configurar {#setup}

::: advertencia REQUISITOS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y
  proyecto</LocalizedLink>
- Xcode 26.0 o posterior
<!-- -->
:::

Si aún no tienes una cuenta y un proyecto Tuist, puedes crearlos ejecutando:

```bash
tuist init
```

Una vez que tenga un archivo `Tuist.swift` que haga referencia a su
`fullHandle`, puede configurar el almacenamiento en caché para su proyecto
ejecutando:

```bash
tuist setup cache
```

Este comando crea un
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
para ejecutar un servicio de caché local al inicio que el [sistema de
compilación](https://github.com/swiftlang/swift-build) Swift utiliza para
compartir artefactos de compilación. Este comando necesita ser ejecutado una vez
en ambos entornos, local y CI.

Para configurar la caché en el CI, asegúrese de estar
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>.

### Configurar los ajustes de compilación de Xcode {#configure-xcode-build-settings}

Añade los siguientes ajustes de compilación a tu proyecto Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Tenga en cuenta que `COMPILATION_CACHE_REMOTE_SERVICE_PATH` y
`COMPILATION_CACHE_ENABLE_PLUGIN` deben añadirse como **ajustes de compilación
definidos por el usuario**, ya que no están expuestos directamente en la
interfaz de usuario de ajustes de compilación de Xcode:

::: info SOCKET PATH
<!-- -->
La ruta del socket se mostrará cuando ejecute `tuist setup cache`. Se basa en el
nombre completo de tu proyecto con barras reemplazadas por guiones bajos.
<!-- -->
:::

También puede especificar esta configuración al ejecutar `xcodebuild` añadiendo
las siguientes banderas, como:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
No es necesario configurar los ajustes manualmente si tu proyecto está generado
por Tuist.

En ese caso, todo lo que necesitas es añadir `enableCaching: true` a tu archivo
`Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### Integración continua (CI) {#continuous-integration-ci}

Para habilitar el almacenamiento en caché en su entorno CI, debe ejecutar el
mismo comando que en los entornos locales: `tuist setup cache`.

Para la autenticación, puede utilizar
<LocalizedLink href="/guides/server/authentication#oidc-tokens">la autenticación
OIDC</LocalizedLink> (recomendada para los proveedores de CI compatibles) o un
<LocalizedLink href="/guides/server/authentication#account-tokens">token de
cuenta</LocalizedLink> a través de la variable de entorno `TUIST_TOKEN`.

Un ejemplo de flujo de trabajo para Acciones de GitHub utilizando autenticación
OIDC:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

Consulte la guía
<LocalizedLink href="/guides/integrations/continuous-integration">Integración
continua</LocalizedLink> para ver más ejemplos, incluida la autenticación basada
en token y otras plataformas CI como Xcode Cloud, CircleCI, Bitrise y Codemagic.
