---
{
  "title": "Cuentas y proyectos",
  "titleTemplate": ":title | Server | Guías | Tuist",
  "description": "Aprende a crear y gestionar cuentas y proyectos en Tuist."
}
---
# Cuentas y proyectos {#accounts-and-projects}

Algunas funcionalidades de Tuist requieren un servidor que añade persistencia de datos y puede interactuar con otros servicios. Para interactuar con el servidor, necesitas una cuenta y un proyecto que conectes a tu proyecto local.

## Cuentas {#accounts}

Para usar el servidor, necesitarás una cuenta. Hay dos tipos de cuentas:

- **Cuenta personal:** Estas cuentas se crean automáticamente cuando te registras y se identifican mediante un identificador (handle) que se obtiene del proveedor de identidad (por ejemplo, GitHub) o de la primera parte de la dirección de correo electrónico.
- **Cuenta de organización:** Estas cuentas se crean manualmente y se identifican mediante un identificador (handle) definido por el desarrollador. Las organizaciones permiten invitar a otros miembros para colaborar en proyectos.

Si estás familiarizado con [GitHub](https://github.com), el concepto es similar al suyo, donde puedes tener cuentas personales y de organización, y se identifican mediante un *identificador (handle)* que se usa al construir las URL.

Puedes gestionar la organización a través de los subcomandos bajo <.localized_link href="/cli/organization">`tuist organization`</.localized_link>. Para crear una nueva cuenta de organización, ejecuta:
```bash
tuist organization create {account-handle}
```

### Membresía de la organización {#organization-membership}

Los usuarios pueden convertirse en miembros de la organización mediante una invitación, la inscripción automática por single sign-on o el <.localized_link href="/guides/integrations/authentication/scim">aprovisionamiento mediante System for Cross-domain Identity Management</.localized_link>.

Autenticarse con el proveedor de identidad de una organización no concede la membresía por sí mismo. La <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">política de inscripción por single sign-on</.localized_link> de la organización determina si un usuario de su dominio de confianza necesita una invitación o puede unirse automáticamente.

Los administradores pueden invitar a un miembro desde el panel de control o con <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link>. Pasa `--role admin` o `--role viewer` para asignar al invitado un rol distinto de `user` cuando acepte.

### Roles {#roles}

Cada miembro de la organización tiene uno de tres roles:

| Rol | Qué otorga |
| --- | --- |
| **Admin** | Todo lo que puede hacer un usuario, más la gestión de la organización: miembros e invitaciones, proyectos, facturación, tokens, webhooks y configuración. |
| **User** | Lee y actúa sobre el trabajo de la organización: ejecutar compilaciones y tests, escribir en la caché, crear y eliminar previsualizaciones, y cambiar el estado de un caso de test. |
| **Viewer** | Lee el trabajo de la organización sin modificarlo. Los paneles de control, las compilaciones, las ejecuciones de tests, los tests inestables y en cuarentena, las previsualizaciones, los bundles y la actividad de los runners son legibles. Adjuntar una shell interactiva o una sesión VNC a un runner no lo es, porque ejecuta comandos en la máquina. |

Elige un rol cuando invites a alguien y cámbialo después desde **Miembros** en el panel de control. Un rol establecido de esta manera nunca se sobrescribe por un inicio de sesión posterior.

## Proyectos {#projects}

Tus proyectos deben integrarse con tu cuenta a través de un proyecto remoto. Siguiendo con la comparación con GitHub, es como tener un repositorio local y otro remoto al que envías tus cambios. Puedes usar <.localized_link href="/cli/project">`tuist project`</.localized_link> para crear y gestionar proyectos.

Los proyectos se identifican mediante un identificador completo (full handle), que resulta de concatenar el identificador de la organización y el del proyecto. Por ejemplo, si tienes una organización con el identificador `tuist` y un proyecto con el identificador `tuist`, el identificador completo sería `tuist/tuist`.

La vinculación entre el proyecto local y el remoto se realiza mediante el archivo de configuración. Si no tienes ninguno, créalo en `Tuist.swift` y añade el siguiente contenido:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Funcionalidades exclusivas de proyectos de Tuist**
>
> Ten en cuenta que algunas funcionalidades, como la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link>, requieren un proyecto gestionado por Tuist. Si no usas Tuist para gestionar tu proyecto, no podrás usar esas funcionalidades.


La URL de tu proyecto se construye usando el identificador completo. Por ejemplo, el panel de control de Tuist, que es público, es accesible en [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), donde `tuist/tuist` es el identificador completo del proyecto.
