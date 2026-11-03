---
{
  "title": "Edición",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Edita los manifiestos de proyectos de Tuist con autocompletado de Xcode y validación de compilación."
}
---
# Edición {#editing}

A diferencia de los proyectos tradicionales de Xcode o de los paquetes Swift, donde los cambios se realizan a través de la interfaz de Xcode, los proyectos gestionados por Tuist se definen en código Swift contenido en **archivos de manifiesto**. Si estás familiarizado con los paquetes Swift y el archivo `Package.swift`, el enfoque es muy similar.

Puedes editar estos archivos con cualquier editor de texto, pero te recomendamos usar el flujo de trabajo que proporciona Tuist para ello, `tuist edit`. Este flujo crea un proyecto de Xcode que contiene todos los archivos de manifiesto y te permite editarlos y compilarlos. Al usar Xcode, obtienes todas las ventajas de **autocompletado, resaltado de sintaxis y verificación de errores**.

## Editar el proyecto {#edit-the-project}

Para editar tu proyecto, puedes ejecutar el siguiente comando en el directorio de un proyecto de Tuist o en un subdirectorio:

```bash
tuist edit
```

El comando crea un proyecto de Xcode en un directorio global y lo abre en Xcode. El proyecto incluye un directorio `Manifests` que puedes compilar para asegurarte de que todos tus manifiestos son válidos.

> [!NOTE]
> **Manifiestos resueltos mediante patrones glob**
>
> `tuist edit` resuelve los manifiestos que se deben incluir utilizando el patrón glob `**/{Manifest}.swift` desde el directorio raíz del proyecto (el que contiene el archivo `Tuist.swift`). Asegúrate de que haya un `Tuist.swift` válido en la raíz del proyecto.


### Ignorar archivos de manifiesto {#ignoring-manifest-files}

Si tu proyecto contiene archivos Swift con el mismo nombre que los archivos de manifiesto (por ejemplo, `Project.swift`) en subdirectorios que no son realmente manifiestos de Tuist, puedes crear un archivo `.tuistignore` en la raíz de tu proyecto para excluirlos del proyecto de edición.

El archivo `.tuistignore` utiliza patrones glob para especificar qué archivos se deben ignorar:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Esto es especialmente útil cuando tienes fixtures de pruebas o código de ejemplo que casualmente usan la misma convención de nombres que los archivos de manifiesto de Tuist.

## Flujo de trabajo de edición y generación {#edit-and-generate-workflow}

Como habrás notado, la edición no se puede hacer desde el proyecto de Xcode generado. Esto es así por diseño para evitar que el proyecto generado tenga una dependencia de Tuist, lo que garantiza que puedas migrar desde Tuist en el futuro con poco esfuerzo.

Cuando iteres sobre un proyecto, te recomendamos ejecutar `tuist edit` desde una sesión de terminal para obtener un proyecto de Xcode con el que editar el proyecto, y usar otra sesión de terminal para ejecutar `tuist generate`.
