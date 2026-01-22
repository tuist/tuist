---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Integración continua (CI) {#continuous-integration-ci}

Para utilizar el registro en su CI, debe asegurarse de haber iniciado sesión en
el registro ejecutando `tuist registry login` como parte de su flujo de trabajo.

::: info ONLY XCODE INTEGRATION
<!-- -->
Solo es necesario crear un nuevo llavero predesbloqueado si utiliza la
integración de paquetes de Xcode.
<!-- -->
:::

Dado que las credenciales del registro se almacenan en un llavero, debes
asegurarte de que se pueda acceder al llavero en el entorno de CI. Ten en cuenta
que algunos proveedores de CI o herramientas de automatización como
[Fastlane](https://fastlane.tools/) ya crean un llavero temporal o proporcionan
una forma integrada de crear uno. Sin embargo, también puedes crear uno creando
un paso personalizado con el siguiente código:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` almacenará las credenciales en el llavero predeterminado.
Asegúrate de que tu llavero predeterminado esté creado y desbloqueado _antes de
ejecutar_ `tuist registry login`.

Además, debes asegurarte de que la variable de entorno `TUIST_TOKEN` esté
configurada. Puedes crear una siguiendo la documentación
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

### Resolución incremental en todos los entornos. {#incremental-resolution-across-environments}

Las resoluciones limpias/frías son ligeramente más rápidas con nuestro registro,
y puede experimentar mejoras aún mayores si persiste en las dependencias
resueltas a lo largo de las compilaciones de CI. Tenga en cuenta que, gracias al
registro, el tamaño del directorio que necesita almacenar y restaurar es mucho
menor que sin el registro, lo que reduce considerablemente el tiempo necesario.
Para almacenar en caché las dependencias cuando se utiliza la integración
predeterminada del paquete Xcode, la mejor manera es especificar un
`clonedSourcePackagesDirPath` personalizado al resolver las dependencias a
través de `xcodebuild`. Esto se puede hacer añadiendo lo siguiente a su archivo
`Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Además, tendrás que encontrar la ruta del paquete `Package.resolved`. Puedes
obtener la ruta ejecutando `ls **/Package.resolved`. La ruta debería ser similar
a `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Para los paquetes Swift y la integración basada en XcodeProj, podemos utilizar
el directorio predeterminado `.build`, ubicado en la raíz del proyecto o en el
directorio `Tuist`. Asegúrate de que la ruta sea correcta al configurar tu
canalización.

A continuación se muestra un ejemplo de flujo de trabajo de GitHub Actions para
resolver y almacenar en caché las dependencias cuando se utiliza la integración
predeterminada del paquete Xcode:
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
