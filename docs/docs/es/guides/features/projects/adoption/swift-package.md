---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Uso de Tuist con un paquete Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist soporta el uso de `Package.swift` como DSL para tus proyectos y convierte
tus objetivos de paquete en un proyecto y objetivos nativos de Xcode.

::: advertencia
<!-- -->
El objetivo de esta característica es proporcionar una manera fácil para los
desarrolladores para evaluar el impacto de la adopción de Tuist en sus paquetes
Swift. Por lo tanto, no planeamos soportar toda la gama de características del
Gestor de Paquetes Swift ni traer todas las características únicas de Tuist como
<LocalizedLink href="/guides/features/projects/code-sharing">ayudantes de descripción de proyectos</LocalizedLink> al mundo de los paquetes.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Los comandos Tuist esperan una cierta estructura
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">de directorios</LocalizedLink> cuya raíz esté identificada por un directorio
`Tuist` o un directorio `.git`.
<!-- -->
:::

## Uso de Tuist con un paquete Swift {#using-tuist-with-a-swift-package}

Vamos a utilizar Tuist con el repositorio [TootSDK
Package](https://github.com/TootSDK/TootSDK), que contiene un paquete Swift. Lo
primero que tenemos que hacer es clonar el repositorio:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Una vez en el directorio del repositorio, necesitamos instalar las dependencias
del gestor de paquetes Swift:

```bash
tuist install
```

Bajo el capó `tuist install` utiliza el gestor de paquetes Swift para resolver y
extraer las dependencias del paquete. Después de la resolución completa, puede
generar el proyecto:

```bash
tuist generate
```

¡Voilà! Tienes un proyecto nativo de Xcode que puedes abrir y empezar a trabajar
en él.
