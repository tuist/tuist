---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Uso de Tuist con un paquete Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist admite el uso de `Package.swift` como DSL para tus proyectos y convierte
los objetivos de tu paquete en un proyecto y objetivos Xcode nativos.

::: advertencia
<!-- -->
El objetivo de esta función es proporcionar a los desarrolladores una forma
sencilla de evaluar el impacto de adoptar Tuist en sus paquetes Swift. Por lo
tanto, no tenemos previsto admitir todas las funciones de Swift Package Manager
ni incorporar todas las funciones exclusivas de Tuist, como
<LocalizedLink href="/guides/features/projects/code-sharing">los ayudantes de
descripción de proyectos</LocalizedLink>, al mundo de los paquetes.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Los comandos de Tuist esperan una determinada
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">estructura
de directorios</LocalizedLink> cuya raíz se identifica mediante un directorio
`Tuist` o un directorio `.git`.
<!-- -->
:::

## Uso de Tuist con un paquete Swift {#using-tuist-with-a-swift-package}

Vamos a utilizar Tuist con el repositorio [TootSDK
Package](https://github.com/TootSDK/TootSDK), que contiene un paquete Swift. Lo
primero que debemos hacer es clonar el repositorio:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Una vez en el directorio del repositorio, debemos instalar las dependencias del
Swift Package Manager:

```bash
tuist install
```

Detrás de escena `tuist install` utiliza Swift Package Manager para resolver y
extraer las dependencias del paquete. Una vez completada la resolución, puede
generar el proyecto:

```bash
tuist generate
```

¡Voilà! Ya tienes un proyecto Xcode nativo que puedes abrir y empezar a
trabajar.
