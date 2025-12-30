---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Integración continua (CI) {#continuous-integration-ci}

Para utilizar el registro en su CI, debe asegurarse de que ha iniciado sesión en
el registro ejecutando `tuist registry login` como parte de su flujo de trabajo.

::: info ONLY XCODE INTEGRATION
<!-- -->
La creación de un nuevo llavero predesbloqueado sólo es necesaria si se utiliza
la integración de paquetes en Xcode.
<!-- -->
:::

Dado que las credenciales de registro se almacenan en un llavero, es necesario
asegurarse de que el llavero se puede acceder en el entorno de CI. Tenga en
cuenta que algunos proveedores de CI o herramientas de automatización como
[Fastlane](https://fastlane.tools/) ya crean un llavero temporal o proporcionan
una forma integrada de crearlo. Sin embargo, también puede crear uno creando un
paso personalizado con el siguiente código:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` almacenará las credenciales en el llavero por defecto.
Asegúrese de que su llavero predeterminado está creado y desbloqueado _antes de
ejecutar_ `tuist registry login`.

Además, debe asegurarse de que la variable de entorno `TUIST_TOKEN` está
configurada. Puede crear una siguiendo la documentación
<LocalizedLink href="/guides/server/authentication#as-a-project">aquí</LocalizedLink>.

Un ejemplo de flujo de trabajo para GitHub Actions podría ser el siguiente:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### Resolución incremental en todos los entornos {#incremental-resolution-across-environments}

Las resoluciones limpias/frías son ligeramente más rápidas con nuestro registro,
y puede experimentar mejoras aún mayores si persiste las dependencias resueltas
a través de las compilaciones CI. Ten en cuenta que gracias al registro, el
tamaño del directorio que necesitas almacenar y restaurar es mucho menor que sin
el registro, tardando significativamente menos tiempo. Para almacenar en caché
las dependencias cuando se utiliza la integración de paquetes por defecto de
Xcode, lo mejor es especificar una `clonedSourcePackagesDirPath` personalizada
cuando se resuelven las dependencias a través de `xcodebuild`. Esto puede
hacerse añadiendo lo siguiente a su archivo `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Además, necesitará encontrar una ruta del `Package.resolved`. Puede obtener la
ruta ejecutando `ls **/Package.resolved`. La ruta debería ser algo parecido a
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Para los paquetes Swift y la integración basada en XcodeProj, podemos utilizar
el directorio por defecto `.build` ubicado en la raíz del proyecto o en el
directorio `Tuist`. Asegúrate de que la ruta es correcta cuando configures tu
pipeline.

A continuación se muestra un flujo de trabajo de ejemplo para las Acciones de
GitHub para resolver y almacenar en caché las dependencias cuando se utiliza la
integración predeterminada de paquetes de Xcode:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
