---
{
  "title": "Proyecto de Xcode",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar el registro de Tuist en un proyecto de Xcode."
}
---
# Proyecto de Xcode {#xcode-project}

Para añadir paquetes mediante el registro en tu proyecto de Xcode, utiliza la interfaz predeterminada de Xcode. Puedes buscar paquetes en el registro haciendo clic en el botón `+` de la pestaña `Package Dependencies` en Xcode. Si el paquete está disponible en el registro, verás el registro `tuist.dev` en la parte superior derecha:

![Añadir dependencias de paquetes](/images/guides/features/build/registry/registry-add-package.png)

## Resolución de paquetes de control de código fuente {#resolving-source-control-packages}

Los paquetes declarados con una URL de control de código fuente, como las dependencias transitivas de los paquetes que añades, se resuelven desde el control de código fuente de forma predeterminada. `tuist registry setup` configura Xcode para resolverlos desde el registro escribiendo la siguiente preferencia de usuario:

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

A continuación, Xcode resuelve un paquete de control de código fuente desde el registro siempre que exista un equivalente en el registro y recurre al control de código fuente cuando no lo haya.

> [!NOTE]
> Esta es una preferencia de Xcode por máquina y no una configuración del proyecto, por lo que confirmar el archivo de configuración del registro no lo comparte con el resto de tu equipo. Cada desarrollador debe ejecutar `tuist registry setup` una vez en su máquina. La preferencia se aplica entonces a todos los proyectos de Xcode en esa máquina.
