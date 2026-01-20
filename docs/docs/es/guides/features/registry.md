---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Registro {#registry}

A medida que el número de dependencias crece, también lo hace el tiempo para
resolverlas. Mientras que otros gestores de paquetes como
[CocoaPods](https://cocoapods.org/) o [npm](https://www.npmjs.com/) están
centralizados, Swift Package Manager no lo está. Debido a esto, SwiftPM necesita
resolver las dependencias haciendo un clon profundo de cada repositorio, lo que
puede llevar mucho tiempo y ocupa más memoria que un enfoque centralizado. Para
solucionar esto, Tuist proporciona una implementación del [Registro de
Paquetes](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md),
para que puedas descargar sólo los commits que _realmente necesita_. Los
paquetes del registro se basan en el [Índice de paquetes
Swift](https://swiftpackageindex.com/). - Si encuentra un paquete allí, también
estará disponible en el Registro Tuist. Además, los paquetes se distribuyen por
todo el mundo utilizando un almacenamiento de borde para una latencia mínima al
resolverlos.

## Uso {#usage}

Para configurar el registro, ejecute el siguiente comando en el directorio de su
proyecto:

```bash
tuist registry setup
```

Este comando genera un archivo de configuración del registro que habilita el
registro para su proyecto. Asegúrese de que este archivo está confirmado para
que su equipo también pueda beneficiarse del registro.

### Autenticación (opcional) {#authentication}

La autenticación es **opcional**. Sin autenticación, puede utilizar el registro
con un límite de velocidad de **1.000 peticiones por minuto** por dirección IP.
Para obtener un límite de velocidad superior de **20.000 peticiones por
minuto**, puede autenticarse ejecutando:

```bash
tuist registry login
```

::: info
<!-- -->
La autenticación requiere una cuenta
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist y un proyecto</LocalizedLink>.
<!-- -->
:::

### Resolver dependencias {#resolving-dependencies}

Para resolver las dependencias desde el registro en lugar de desde el control de
código fuente, siga leyendo en función de la configuración de su proyecto:
- <LocalizedLink href="/guides/features/registry/xcode-project">Proyecto de Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Proyecto generado con la integración del paquete Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Proyecto generado con la integración de paquetes basada en XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Paquete de Swift</LocalizedLink>

Para configurar el registro en la IC, siga esta guía:
<LocalizedLink href="/guides/features/registry/continuous-integration">Integración continua</LocalizedLink>.

### Identificadores del registro de paquetes {#package-registry-identifiers}

Cuando utilice identificadores de registro de paquetes en un archivo
`Package.swift` o `Project.swift`, deberá convertir la URL del paquete a la
convención del registro. El identificador del registro siempre tiene la forma
`{organization}.{repository}`. Por ejemplo, para utilizar el registro para el
paquete `https://github.com/pointfreeco/swift-composable-architecture`, el
identificador del registro del paquete sería
`pointfreeco.swift-composable-architecture`.

::: info
<!-- -->
El identificador no puede contener más de un punto. Si el nombre del repositorio
contiene un punto, se sustituye por un guión bajo. Por ejemplo, el paquete
`https://github.com/groue/GRDB.swift` tendría el identificador de registro
`groue.GRDB_swift`.
<!-- -->
:::
