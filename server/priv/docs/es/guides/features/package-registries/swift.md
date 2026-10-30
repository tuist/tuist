---
{
  "title": "Swift",
  "titleTemplate": ":title · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Acelera la resolución de Swift Package Manager de minutos a segundos con el registro de paquetes Swift de Tuist, respaldado por la red global de caché de Tuist."
}
---
# Registro de paquetes Swift {#swift-package-registry}

A medida que aumenta el número de dependencias, también lo hace el tiempo necesario para resolverlas. Mientras que otros gestores de paquetes como [CocoaPods](https://cocoapods.org/) o [npm](https://www.npmjs.com/) están centralizados, Swift Package Manager no lo está. Por ello, SwiftPM necesita resolver las dependencias realizando un clon profundo de cada repositorio, lo cual puede llevar mucho tiempo y consumir más memoria que un enfoque centralizado. Para solucionar esto, Tuist ofrece una implementación del [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), de modo que puedas descargar únicamente los commits que _realmente necesitas_. Los paquetes del registro se basan en el [Swift Package Index](https://swiftpackageindex.com/): si encuentras un paquete allí, también estará disponible en el Registro de Tuist. Además, los paquetes se distribuyen por todo el mundo mediante almacenamiento perimetral para minimizar la latencia al resolverlos.

## Uso {#usage}

Hay dos formas de configurar el registro:

### Opción 1: Configuración automática durante la generación (recomendada) {#automatic-setup}

Si utilizas Tuist para generar tu proyecto, puedes habilitar el registro estableciendo la opción `registryEnabled` en tu configuración de `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

Con esta opción, `tuist generate` creará automáticamente el archivo de configuración del registro en tu espacio de trabajo. Esto elimina la necesidad de ejecutar `tuist registry setup` por separado.

> [!TIP]
> `registryEnabled` también configura el registro para proyectos que integran dependencias a través de la integración predeterminada de Swift Package Manager de Xcode, en lugar de la integración basada en XcodeProj de Tuist. No configura Xcode para resolver paquetes declarados con una URL de control de versiones desde el registro. Para hacerlo, ejecuta `tuist registry setup` una vez en cada máquina, como se describe en <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Resolución de paquetes de control de versiones</.localized_link>.


### Opción 2: Configuración manual {#manual-setup}

Para configurar el registro manualmente, ejecuta el siguiente comando en el directorio de tu proyecto:

```bash
tuist registry setup
```

Este comando genera un archivo de configuración del registro que habilita el registro para tu proyecto. Asegúrate de confirmar este archivo para que tu equipo también pueda beneficiarse del registro.

### Autenticación (opcional) {#authentication}

La autenticación es **opcional**. Sin autenticación, puedes usar el registro con un límite de tasa de **1.000 solicitudes por minuto** por dirección IP. Para obtener un límite de tasa más alto de **20.000 solicitudes por minuto**, puedes autenticarte ejecutando:

```bash
tuist registry login
```

> [!NOTE]
> La autenticación requiere una <.localized_link href="/guides/server/accounts-and-projects">cuenta y proyecto de Tuist</.localized_link>.


### Resolución de dependencias {#resolving-dependencies}

Para resolver dependencias desde el registro en lugar de desde el control de versiones, continúa leyendo según la configuración de tu proyecto:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

Para configurar el registro en la CI, sigue esta guía: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">Integración continua</.localized_link>.

### Identificadores del registro de paquetes {#package-registry-identifiers}

Cuando uses identificadores del registro de paquetes en un archivo `Package.swift` o `Project.swift`, debes convertir la URL del paquete a la convención del registro. El identificador del registro siempre tiene el formato `{organization}.{repository}`. Por ejemplo, para usar el registro para el paquete `https://github.com/pointfreeco/swift-composable-architecture`, el identificador del registro de paquetes sería `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> El identificador no puede contener más de un punto. Si el nombre del repositorio contiene un punto, se reemplaza por un guion bajo. Por ejemplo, el paquete `https://github.com/groue/GRDB.swift` tendría el identificador de registro `groue.GRDB_swift`.
