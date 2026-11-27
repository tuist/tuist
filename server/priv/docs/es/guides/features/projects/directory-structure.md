---
{
  "title": "Estructura de directorios",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende sobre la estructura de los proyectos de Tuist y cómo organizarlos."
}
---
# Estructura de directorios {#directory-structure}

Aunque los proyectos de Tuist se utilizan habitualmente para sustituir a los proyectos de Xcode, no se limitan a este caso de uso. Los proyectos de Tuist también se emplean para generar otros tipos de proyectos, como paquetes SPM, plantillas, plugins y tareas. Este documento describe la estructura de los proyectos de Tuist y cómo organizarlos. En secciones posteriores, explicaremos cómo definir plantillas, plugins y tareas.

## Proyectos estándar de Tuist {#standard-tuist-projects}

Los proyectos de Tuist son **el tipo de proyecto generado por Tuist más habitual.** Se utilizan para compilar aplicaciones, frameworks y bibliotecas, entre otros. A diferencia de los proyectos de Xcode, los proyectos de Tuist se definen en Swift, lo que los hace más flexibles y fáciles de mantener. Los proyectos de Tuist también son más declarativos, lo que facilita su comprensión y análisis. La siguiente estructura muestra un proyecto típico de Tuist que genera un proyecto de Xcode:

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
  - **ProjectDescriptionHelpers:** Este directorio contiene código Swift compartido entre todos los archivos de manifiesto. Los archivos de manifiesto pueden `import ProjectDescriptionHelpers` para utilizar el código definido en este directorio. Compartir código resulta útil para evitar duplicaciones y garantizar la coherencia entre los proyectos.
  - **Package.swift:** Este archivo contiene las dependencias de Swift Package para que Tuist las integre mediante proyectos y targets de Xcode (como [CocoaPods](https://cocoapods.org)) que son configurables y optimizables. Obtén más información <.localized_link href="/guides/features/projects/dependencies">aquí</.localized_link>.

- **Directorio raíz**: El directorio raíz de tu proyecto, que también contiene el directorio `Tuist`.
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift:</strong></.localized_link> Este archivo contiene la configuración de Tuist compartida entre todos los proyectos, workspaces y entornos. Por ejemplo, puede utilizarse para desactivar la generación automática de esquemas o para definir el destino de despliegue de los proyectos.
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift:</strong></.localized_link> Este manifiesto representa un workspace de Xcode. Se utiliza para agrupar otros proyectos y también puede añadir archivos y esquemas adicionales.
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift:</strong></.localized_link> Este manifiesto representa un proyecto de Xcode. Se utiliza para definir los targets que forman parte del proyecto y sus dependencias.

Al interactuar con el proyecto anterior, los comandos esperan encontrar un archivo `Workspace.swift` o `Project.swift` en el directorio de trabajo o en el directorio indicado mediante la opción `--path`. El manifiesto debe estar en un directorio o subdirectorio de un directorio que contenga un directorio `Tuist`, que representa la raíz del proyecto.

> [!TIP]
> Los workspaces de Xcode permitían dividir los proyectos en varios proyectos de Xcode para reducir la probabilidad de conflictos al fusionar cambios. Si ese era el motivo por el que utilizabas workspaces, no los necesitas en Tuist. Tuist genera automáticamente un workspace que contiene un proyecto y los proyectos de sus dependencias.


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist también admite proyectos de paquetes SPM. Si estás trabajando en un paquete SPM, no deberías necesitar actualizar nada. Tuist detecta automáticamente tu `Package.swift` raíz y todas las funcionalidades de Tuist funcionan como si fuera un manifiesto `Project.swift`.

Para empezar, ejecuta `tuist install` y `tuist generate` en tu paquete SPM. Tu proyecto debería tener ahora los mismos esquemas y archivos que verías en la integración vanilla de Xcode con SPM. Sin embargo, ahora también puedes ejecutar <.localized_link href="/guides/features/cache">`tuist cache`</.localized_link> y tener la mayoría de tus dependencias y módulos SPM precompilados, lo que hace que las compilaciones posteriores sean extremadamente rápidas.
