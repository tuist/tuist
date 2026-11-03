---
{
  "title": "Integración continua",
  "titleTemplate": ":title · Swift · Package Registries · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar el Registry de Tuist en integración continua."
}
---
# Integración continua (CI) {#continuous-integration-ci}

El registro funciona de forma inmediata en CI sin necesidad de configurar autenticación adicional. Por defecto, las solicitudes no autenticadas tienen un límite de tasa de **1000 solicitudes por minuto** por dirección IP.

Si necesitas un límite de tasa más alto de **20 000 solicitudes por minuto**, puedes autenticarte ejecutando `tuist registry login`. Esto requiere que la variable de entorno `TUIST_TOKEN` esté configurada. Puedes crear un token de proyecto siguiendo la documentación <.localized_link href="/guides/server/authentication#as-a-project">aquí</.localized_link>.

> [!NOTE]
> La configuración del llavero que se muestra a continuación solo es necesaria si usas `tuist registry login` para obtener límites de tasa más altos. En la mayoría de los casos, el límite de tasa predeterminado para solicitudes no autenticadas es suficiente y puedes omitir este paso por completo.
>
> Además, crear un nuevo llavero previamente desbloqueado solo es necesario cuando se usa la integración de paquetes de Xcode.


Dado que `tuist registry login` almacena credenciales en un llavero, debes asegurarte de que el llavero sea accesible en el entorno de CI. Ten en cuenta que algunos proveedores de CI o herramientas de automatización como [Fastlane](https://fastlane.tools/) ya crean un llavero temporal o proporcionan una forma integrada de crear uno. Sin embargo, también puedes crear uno añadiendo un paso personalizado con el siguiente código:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Asegúrate de que tu llavero predeterminado esté creado y desbloqueado _antes_ de ejecutar `tuist registry login`.

### Resolución incremental entre entornos {#incremental-resolution-across-environments}

Las resoluciones limpias o en frío son ligeramente más rápidas con nuestro registro, y puedes experimentar mejoras aún mayores si mantienes las dependencias resueltas entre compilaciones de CI. Ten en cuenta que, gracias al registro, el tamaño del directorio que necesitas almacenar y restaurar es mucho menor que sin el registro, lo que reduce significativamente el tiempo. Para almacenar en caché las dependencias cuando uses la integración predeterminada de paquetes de Xcode, la mejor opción es especificar un `clonedSourcePackagesDirPath` personalizado al resolver dependencias mediante `xcodebuild`. Esto se puede hacer añadiendo lo siguiente a tu archivo `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Además, tendrás que encontrar la ruta del `Package.resolved`. Puedes obtener la ruta ejecutando `ls **/Package.resolved`. La ruta debería tener un aspecto similar a `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Para paquetes Swift y la integración basada en XcodeProj, podemos usar el directorio predeterminado `.build`, ubicado en la raíz del proyecto o en el directorio `Tuist`. Asegúrate de que la ruta sea correcta al configurar tu pipeline.

A continuación se muestra un ejemplo de flujo de trabajo para GitHub Actions para resolver y almacenar en caché dependencias cuando se usa la integración predeterminada de paquetes de Xcode:
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
