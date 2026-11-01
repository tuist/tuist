---
{
  "title": "Estructura de directorios",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende sobre la estructura de los proyectos de Tuist y cómo organizarlos."
}
---
# Estructura de directorios {#directory-structure}

Aunque los proyectos de Tuist se usan habitualmente para sustituir a los proyectos de Xcode, no se limitan a este caso de uso. Los proyectos de Tuist también se utilizan para generar otros tipos de proyectos, como paquetes SPM, plantillas, complementos y tareas. Este documento describe la estructura de los proyectos de Tuist y cómo organizarlos. En secciones posteriores, veremos cómo definir plantillas, complementos y tareas.

## Proyectos estándar de Tuist {#standard-tuist-projects}

Los proyectos de Tuist son **el tipo de proyecto más común generado por Tuist.** Se utilizan para compilar apps, frameworks y bibliotecas, entre otros. A diferencia de los proyectos de Xcode, los proyectos de Tuist se definen en Swift, lo que los hace más flexibles y fáciles de mantener. Los proyectos de Tuist también son más declarativos, lo que facilita su comprensión y análisis. La siguiente estructura muestra un proyecto típico de Tuist que genera un proyecto de Xcode:

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

- **Directorio Tuist:** Este directorio tiene dos propósitos. En primer lugar, indica **dónde está la raíz del proyecto**. Esto permite construir rutas relativas a la raíz del proyecto y también ejecutar comandos de Tuist desde cualquier directorio dentro del proyecto. En segundo lugar, es el contenedor de los siguientes archivos:
  - **ProjectDescriptionHelpers:** Este directorio contiene código Swift que se comparte en todos los archivos de manifiesto. Los archivos de manifiesto pueden `import ProjectDescriptionHelpers` para usar el código definido en este directorio. Compartir código es útil para evitar duplicaciones y garantizar la coherencia entre los proyectos.
  - **Package.swift:** Este archivo contiene las dependencias de Swift Package para que Tuist las integre mediante proyectos y destinos de Xcode (como [CocoaPods](https://cococapods)) que son configurables y optimizables. Más información <.localized_link href="/guides/features/projects/dependencies">aquí</.localized_link>.

- **Directorio raíz**: El directorio raíz de tu proyecto que también contiene el directorio `Tuist`.
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></.localized_link> Este archivo contiene la configuración de Tuist que se comparte en todos los proyectos, espacios de trabajo y entornos. Por ejemplo, puede usarse para desactivar la generación automática de esquemas o para definir el destino de implementación de los proyectos.
  - <.localized_link href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></.localized_link> Este manifiesto representa un espacio de trabajo de Xcode. Se utiliza para agrupar otros proyectos y también puede añadir archivos y esquemas adicionales.
  - <.localized_link href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></.localized_link> Este manifiesto representa un proyecto de Xcode. Se utiliza para definir los destinos que forman parte del proyecto y sus dependencias.

Al interactuar con el proyecto anterior, los comandos esperan encontrar un archivo `Workspace.swift` o `Project.swift` en el directorio de trabajo o en el directorio indicado mediante la opción `--path`. El manifiesto debe estar en un directorio o subdirectorio de un directorio que contenga un directorio `Tuist`, que representa la raíz del proyecto.

> [!TIP]
> Los espacios de trabajo de Xcode permitían dividir los proyectos en varios proyectos de Xcode para reducir la probabilidad de conflictos al fusionar cambios. Si ese era el motivo por el que utilizabas espacios de trabajo, no los necesitas en Tuist. Tuist genera automáticamente un espacio de trabajo que contiene un proyecto y los proyectos de sus dependencias.


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist también admite proyectos de paquetes SPM. Si estás trabajando en un paquete SPM, no deberías necesitar actualizar nada. Tuist detecta automáticamente tu `Package.swift` raíz y todas las funcionalidades de Tuist funcionan como si fuera un manifiesto `Project.swift`.

Para empezar, ejecuta `tuist install` y `tuist generate` en tu paquete SPM. Tu proyecto debería tener ahora los mismos esquemas y archivos que verías en la integración vanilla de SPM de Xcode. Sin embargo, ahora también puedes ejecutar <.localized_link href="/guides/features/cache">`tuist cache`</.localized_link> y tener la mayoría de tus dependencias y módulos SPM precompilados, lo que hace que las compilaciones posteriores sean extremadamente rápidas.
