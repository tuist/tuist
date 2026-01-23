---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Proyecto Xcode {#xcode-project}

Para añadir paquetes utilizando el registro en tu proyecto Xcode, utiliza la
interfaz de usuario predeterminada de Xcode. Puedes buscar paquetes en el
registro haciendo clic en el botón « ` » + «` » en la pestaña « `» «Package
Dependencies» «` » de Xcode. Si el paquete está disponible en el registro, verás
el registro « `» «tuist.dev» «` » en la parte superior derecha:

![Añadir dependencias del
paquete](/images/guides/features/build/registry/registry-add-package.png)

::: info
<!-- -->
Actualmente, Xcode no admite la sustitución automática de paquetes de control de
código fuente por sus equivalentes en el registro. Deberá eliminar manualmente
el paquete de control de código fuente y añadir el paquete del registro para
acelerar la resolución.
<!-- -->
:::
