---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Proyecto Xcode {#xcode-project}

Para añadir paquetes utilizando el registro en su proyecto Xcode, utilice la
interfaz de usuario predeterminada de Xcode. Puede buscar paquetes en el
registro haciendo clic en el botón `+` en la pestaña `Package Dependencies` en
Xcode. Si el paquete está disponible en el registro, verá el registro
`tuist.dev` en la parte superior derecha:

[Añadiendo dependencias de
paquetes](/images/guides/features/build/registry/registry-add-package.png)

> [NOTA: Xcode no soporta actualmente la sustitución automática de los paquetes
> de control de código fuente por sus equivalentes en el registro. Deberá
> eliminar manualmente el paquete de control de origen y añadir el paquete de
> registro para acelerar la resolución.
