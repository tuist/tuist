---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Estructura del directorio {#directory-structure}

Aunque los proyectos Tuist se utilizan habitualmente para sustituir a los
proyectos Xcode, no se limitan a este caso de uso. Los proyectos Tuist también
se utilizan para generar otros tipos de proyectos, como paquetes SPM,
plantillas, plugins y tareas. Este documento describe la estructura de los
proyectos Tuist y cómo organizarlos. En secciones posteriores, veremos cómo
definir plantillas, plugins y tareas.

## Proyectos Tuist estándar {#standard-tuist-projects}

Los proyectos Tuist son **el tipo más común de proyecto generado por Tuist.** Se
utilizan para construir apps, frameworks y librerías entre otros. A diferencia
de los proyectos Xcode, los proyectos Tuist se definen en Swift, lo que los hace
más flexibles y fáciles de mantener. Los proyectos Tuist también son más
declarativos, lo que los hace más fáciles de entender y razonar. La siguiente
estructura muestra un proyecto Tuist típico que genera un proyecto Xcode:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Directorio Tuist:** Este directorio tiene dos finalidades. En primer lugar,
  indica a **dónde está la raíz del proyecto**. Esto permite construir rutas
  relativas a la raíz del proyecto, y también ejecutar comandos Tuist desde
  cualquier directorio dentro del proyecto. En segundo lugar, es el contenedor
  de los siguientes archivos:
  - **ProjectDescriptionHelpers:** Este directorio contiene código Swift que se
    comparte en todos los archivos de manifiesto. Los archivos de manifiesto
    pueden `importar ProjectDescriptionHelpers` para utilizar el código definido
    en este directorio. Compartir código es útil para evitar duplicidades y
    garantizar la coherencia entre los proyectos.
  - **Package.swift:** Este archivo contiene las dependencias de Swift Package
    para que Tuist las integre utilizando proyectos y objetivos de Xcode (como
    [CocoaPods](https://cococapods)) que son configurables y optimizables. Más
    información
    <LocalizedLink href="/guides/features/projects/dependencies">aquí</LocalizedLink>.

- **Directorio raíz**: El directorio raíz de su proyecto que también contiene el
  directorio `Tuist`.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Este archivo contiene la configuración de Tuist que se comparte en todos los
    proyectos, espacios de trabajo y entornos. Por ejemplo, se puede utilizar
    para desactivar la generación automática de esquemas, o para definir el
    destino de despliegue de los proyectos.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Espacio de trabajo.swift:</bold></LocalizedLink> Este manifiesto representa un
    espacio de trabajo de Xcode. Se utiliza para agrupar otros proyectos y
    también puede añadir archivos y esquemas adicionales.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Proyecto.swift:</bold></LocalizedLink>
    Este manifiesto representa un proyecto Xcode. Se utiliza para definir los
    objetivos que forman parte del proyecto y sus dependencias.

Al interactuar con el proyecto anterior, los comandos esperan encontrar un
archivo `Workspace.swift` o `Project.swift` en el directorio de trabajo o en el
directorio indicado mediante la bandera `--path`. El manifiesto debe estar en un
directorio o subdirectorio de un directorio que contenga un directorio `Tuist`,
que representa la raíz del proyecto.

::: consejo
<!-- -->
Los espacios de trabajo de Xcode permitían dividir proyectos en varios proyectos
de Xcode para reducir la probabilidad de conflictos de fusión. Si usabas
espacios de trabajo para eso, no los necesitas en Tuist. Tuist genera
automáticamente un espacio de trabajo que contiene un proyecto y los proyectos
de sus dependencias.
<!-- -->
:::

## Paquete Swift <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist también soporta proyectos de paquetes SPM. Si estás trabajando en un
paquete SPM, no deberías necesitar actualizar nada. Tuist recoge automáticamente
su raíz `Package.swift` y todas las características de Tuist funcionan como si
fuera un `Project.swift` manifiesto.

Para empezar, ejecute `tuist install` y `tuist generate` en su paquete SPM. Tu
proyecto debería tener ahora todos los mismos esquemas y archivos que verías en
la integración SPM vainilla de Xcode. Sin embargo, ahora también puedes ejecutar
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink> y
tener la mayoría de tus dependencias y módulos SPM precompilados, haciendo que
las construcciones posteriores sean extremadamente rápidas.
