---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Cuentas y proyectos {#accounts-and-projects}

Algunas funcionalidades de Tuist requieren un servidor que añade persistencia de datos y puede interactuar con otros servicios. Para interactuar con el servidor, necesitas una cuenta y un proyecto que conectes a tu proyecto local.

## Cuentas {#accounts}

Para usar el servidor, necesitarás una cuenta. Hay dos tipos de cuentas:

- **Cuenta personal:** Estas cuentas se crean automáticamente cuando te registras y se identifican mediante un identificador (handle) que se obtiene del proveedor de identidad (por ejemplo, GitHub) o de la primera parte de la dirección de correo electrónico.
- **Cuenta de organización:** Estas cuentas se crean manualmente y se identifican mediante un identificador (handle) definido por el desarrollador. Las organizaciones permiten invitar a otros miembros para colaborar en proyectos.

Si estás familiarizado con [GitHub](https://github.com), el concepto es similar al suyo, donde puedes tener cuentas personales y de organización, y se identifican mediante un *identificador (handle)* que se usa al construir URLs.

> [!NOTE]
> **Prioridad a la CLI**
>
> La mayoría de las operaciones para gestionar cuentas y proyectos se realizan a través de la CLI. Estamos trabajando en una interfaz web que facilitará la gestión de cuentas y proyectos.


Puedes gestionar la organización a través de los subcomandos bajo <.localized_link href="/cli/organization">`tuist organization`</.localized_link>. Para crear una nueva cuenta de organización, ejecuta:
```bash
tuist organization create {account-handle}
```

### Membresía de la organización {#organization-membership}

Los usuarios pueden convertirse en miembros de la organización mediante una invitación, inscripción automática de inicio de sesión único (SSO) o <.localized_link href="/guides/integrations/authentication/scim">aprovisionamiento del Sistema de Gestión de Identidades entre Dominios (SCIM)</.localized_link>.

Autenticarse con el proveedor de identidad de una organización no concede la membresía por sí mismo. La <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">política de inscripción de inicio de sesión único (SSO)</.localized_link> de la organización determina si un usuario de su dominio de confianza necesita una invitación o puede unirse automáticamente.

Los administradores pueden invitar a un miembro desde el panel de control o con <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link>. Pasa `--role admin` o `--role viewer` para asignar al invitado un rol distinto de `user` cuando acepte.

### Roles {#roles}

Cada miembro de la organización tiene uno de tres roles:

| Rol | Qué otorga |
| --- | --- |
| **Administrador** | Todo lo que puede hacer un usuario, más la gestión de la organización: miembros e invitaciones, proyectos, facturación, tokens, webhooks y configuración. |
| **Usuario** | Lee y actúa sobre el trabajo de la organización: ejecutar compilaciones y tests, escribir en la caché, crear y eliminar previsualizaciones, y cambiar el estado de un caso de test. |
| **Visualizador** | Lee el trabajo de la organización y no cambia nada. Los paneles de control, compilaciones, ejecuciones de tests, tests inestables y en cuarentena, previsualizaciones, paquetes y actividad de los runners son todos legibles. Adjuntar una shell interactiva o una sesión VNC a un runner no está permitido, porque ejecuta comandos en la máquina. |

Elige un rol cuando invites a alguien y cámbialo más tarde desde **Miembros** en el panel de control. Un rol establecido de esta manera nunca se sobrescribe por un inicio de sesión posterior.

## Proyectos {#projects}

Tus proyectos necesitan integrarse con tu cuenta a través de un proyecto remoto. Siguiendo con la comparación con GitHub, es como tener un repositorio local y otro remoto donde envías tus cambios. Puedes usar <.localized_link href="/cli/project">`tuist project`</.localized_link> para crear y gestionar proyectos.

Los proyectos se identifican mediante un identificador completo (full handle), que es el resultado de concatenar el identificador de la organización y el identificador del proyecto. Por ejemplo, si tienes una organización con el identificador `tuist` y un proyecto con el identificador `tuist`, el identificador completo sería `tuist/tuist`.

La vinculación entre el proyecto local y el remoto se realiza a través del archivo de configuración. Si no tienes ninguno, créalo en `Tuist.swift` y añade el siguiente contenido:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Funcionalidades exclusivas de proyectos de Tuist**
>
> Ten en cuenta que algunas funcionalidades como <.localized_link href="/guides/features/cache/module-cache">la caché de módulos</.localized_link> requieren un proyecto gestionado por Tuist. Si no usas Tuist para gestionar tu proyecto, no podrás usar esas funcionalidades.


La URL de tu proyecto se construye utilizando el identificador completo. Por ejemplo, el panel de control de Tuist, que es público, es accesible en [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), donde `tuist/tuist` es el identificador completo del proyecto.
