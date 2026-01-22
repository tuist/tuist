---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Caché de Xcode {#xcode-cache}

Tuist ofrece compatibilidad con la caché de compilación de Xcode, lo que permite
a los equipos compartir artefactos de compilación aprovechando las capacidades
de almacenamiento en caché del sistema de compilación.

## Configuración {#setup}

::: advertencia REQUISITOS
<!-- -->
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
- Xcode 26.0 o posterior.
<!-- -->
:::

Si aún no tienes una cuenta y un proyecto en Tuist, puedes crear uno ejecutando:

```bash
tuist init
```

Una vez que tengas un archivo `Tuist.swift` que haga referencia a tu
`fullHandle`, puedes configurar el almacenamiento en caché para tu proyecto
ejecutando:

```bash
tuist setup cache
```

Este comando crea un
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
para ejecutar un servicio de caché local al inicio que el [sistema de
compilación](https://github.com/swiftlang/swift-build) de Swift utiliza para
compartir artefactos de compilación. Este comando debe ejecutarse una vez tanto
en tu entorno local como en el de CI.

Para configurar la caché en el CI, asegúrate de estar
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>.

### Configurar los ajustes de compilación de Xcode {#configure-xcode-build-settings}

Añade los siguientes ajustes de compilación a tu proyecto Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Ten en cuenta que `COMPILATION_CACHE_REMOTE_SERVICE_PATH` y
`COMPILATION_CACHE_ENABLE_PLUGIN` deben añadirse como **ajustes de compilación
definidos por el usuario**, ya que no aparecen directamente en la interfaz de
usuario de los ajustes de compilación de Xcode:

::: info SOCKET PATH
<!-- -->
La ruta del socket se mostrará cuando ejecute `tuist setup cache`. Se basa en el
identificador completo de su proyecto, sustituyendo las barras inclinadas por
guiones bajos.
<!-- -->
:::

También puede especificar estos ajustes al ejecutar `xcodebuild` añadiendo los
siguientes indicadores, como por ejemplo:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
No es necesario configurar los ajustes manualmente si tu proyecto ha sido
generado por Tuist.

En ese caso, solo tienes que añadir `enableCaching: true` a tu archivo
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
mismo comando que en entornos locales: `tuist setup cache`.

Para la autenticación, puede utilizar
<LocalizedLink href="/guides/server/authentication#oidc-tokens">la autenticación
OIDC</LocalizedLink> (recomendada para proveedores de CI compatibles) o un
<LocalizedLink href="/guides/server/authentication#account-tokens">token de
cuenta</LocalizedLink> a través de la variable de entorno `TUIST_TOKEN`.

Un ejemplo de flujo de trabajo para GitHub Actions utilizando la autenticación
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

Consulte la
<LocalizedLink href="/guides/integrations/continuous-integration">guía de
integración continua</LocalizedLink> para ver más ejemplos, incluida la
autenticación basada en tokens y otras plataformas de CI como Xcode Cloud,
CircleCI, Bitrise y Codemagic.
