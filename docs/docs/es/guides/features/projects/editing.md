---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Edición {#editing}

A diferencia de los proyectos tradicionales de Xcode o los paquetes Swift, en
los que los cambios se realizan a través de la interfaz de usuario de Xcode, los
proyectos gestionados por Tuist se definen en código Swift contenido en archivos
de manifiesto **** . Si estás familiarizado con los paquetes Swift y el archivo
`Package.swift`, el enfoque es muy similar.

Puede editar estos archivos con cualquier editor de texto, pero le recomendamos
que utilice el flujo de trabajo proporcionado por Tuist para ello, `tuist edit`.
El flujo de trabajo crea un proyecto Xcode que contiene todos los archivos de
manifiesto y le permite editarlos y compilarlos. Gracias al uso de Xcode,
obtendrá todas las ventajas de **la finalización de código, el resaltado de
sintaxis y la comprobación de errores**.

## Edita el proyecto. {#edit-the-project}

Para editar tu proyecto, puedes ejecutar el siguiente comando en un directorio
de proyecto Tuist o en un subdirectorio:

```bash
tuist edit
```

El comando crea un proyecto Xcode en un directorio global y lo abre en Xcode. El
proyecto incluye un directorio `Manifests` que puede compilar para asegurarse de
que todos sus manifiestos son válidos.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` resuelve los manifiestos que se incluirán utilizando el glob
`**/{Manifest}.swift` desde el directorio raíz del proyecto (el que contiene el
archivo `Tuist.swift` ). Asegúrate de que hay un `Tuist.swift` válido en la raíz
del proyecto.
<!-- -->
:::

### Ignorar archivos de manifiesto {#ignoring-manifest-files}

Si tu proyecto contiene archivos Swift con el mismo nombre que los archivos de
manifiesto (por ejemplo, `Project.swift`) en subdirectorios que no son
manifiestos Tuist reales, puedes crear un archivo `.tuistignore` en la raíz de
tu proyecto para excluirlos del proyecto de edición.

El archivo `.tuistignore` utiliza patrones glob para especificar qué archivos
deben ignorarse:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Esto resulta especialmente útil cuando tienes elementos de prueba o código de
ejemplo que utilizan la misma convención de nomenclatura que los archivos de
manifiesto de Tuist.

## Editar y generar flujo de trabajo {#edit-and-generate-workflow}

Como habrás notado, la edición no se puede realizar desde el proyecto Xcode
generado. Esto es así por diseño, para evitar que el proyecto generado tenga una
dependencia de Tuist, lo que garantiza que puedas dejar de usar Tuist en el
futuro sin mucho esfuerzo.

Al iterar en un proyecto, recomendamos ejecutar `tuist edit` desde una sesión de
terminal para obtener un proyecto Xcode con el que editar el proyecto, y
utilizar otra sesión de terminal para ejecutar `tuist generate`.
