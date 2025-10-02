---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Edición {#editing}

A diferencia de los proyectos tradicionales de Xcode o Swift Packages, en los
que los cambios se realizan a través de la interfaz de usuario de Xcode, los
proyectos gestionados por Tuist se definen en código Swift contenido en archivos
de manifiesto **** . Si estás familiarizado con los paquetes Swift y el archivo
`Package.swift`, el enfoque es muy similar.

Puedes editar estos archivos con cualquier editor de texto, pero te recomendamos
que utilices el flujo de trabajo proporcionado por Tuist, `tuist edit`. El flujo
de trabajo crea un proyecto Xcode que contiene todos los archivos de manifiesto
y te permite editarlos y compilarlos. Gracias al uso de Xcode, obtienes todas
las ventajas de **completado de código, resaltado de sintaxis y comprobación de
errores**.

## Editar el proyecto {#edit-the-project}

Para editar tu proyecto, puedes ejecutar el siguiente comando en un directorio o
subdirectorio del proyecto Tuist:

```bash
tuist edit
```

El comando crea un proyecto Xcode en un directorio global y lo abre en Xcode. El
proyecto incluye un directorio `Manifests` que puedes construir para asegurarte
de que todos tus manifiestos son válidos.

> [!INFO] MANIFESTS RESUELTOS CON GLOB `tuist edit` resuelve los manifiestos a
> incluir usando el glob `**/{Manifest}.swift` desde el directorio raíz del
> proyecto (el que contiene el fichero `Tuist.swift` ). Asegúrate de que hay un
> `Tuist.swift` válido en la raíz del proyecto.

## Editar y generar flujo de trabajo {#edit-and-generate-workflow}

Como habrás notado, la edición no se puede hacer desde el proyecto Xcode
generado. Eso es por diseño para evitar que el proyecto generado de tener una
dependencia de Tuist, asegurando que se puede mover de Tuist en el futuro con
poco esfuerzo.

Al iterar sobre un proyecto, recomendamos ejecutar `tuist edit` desde una sesión
de terminal para obtener un proyecto Xcode para editar el proyecto, y utilizar
otra sesión de terminal para ejecutar `tuist generate`.
