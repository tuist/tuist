---
{
  "title": "Inicio de sesión único",
  "titleTemplate": ":title | Autenticación | Integraciones | Guías | Tuist",
  "description": "Aprende a configurar el inicio de sesión único, verificar el dominio de un correo electrónico de acceso y elegir cómo los usuarios se unen a tu organización."
}
---
# Inicio de sesión único {#single-sign-on}

Tuist ofrece el inicio de sesión único como una opción de acceso para proporcionar mayor seguridad a la cuenta de tu organización.

El inicio de sesión único se configura desde la pestaña **Autenticación** en la configuración de tu organización. Se admiten Google Workspace, Okta, Microsoft Entra ID y proveedores personalizados de [OAuth 2.0](https://oauth.net/2/).

Microsoft Entra ID es un proveedor de OpenID Connect que Tuist configura por ti a partir del identificador de tu directorio. Todo lo que esta guía describe para proveedores personalizados, incluida la verificación del dominio de correo electrónico de inicio de sesión y la inscripción, también se aplica a él.

> [!NOTE]
> El inicio de sesión único controla cómo se autentican los miembros y si los usuarios autenticados pueden unirse automáticamente. El aprovisionamiento mediante <.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management</.localized_link> controla si un proveedor de identidad puede crear, actualizar y desaprovisionar miembros de la organización. Para Okta, la mayoría de las organizaciones configuran ambas opciones.

## Cómo funciona el acceso {#how-access-works}

La identidad del proveedor, el descubrimiento de inicio de sesión y la inscripción en la organización son aspectos independientes:

- **Emisor del proveedor:** La organización proveedora o el servidor de autorización que autenticó al usuario. Tuist combina el proveedor, el emisor y el identificador estable del usuario del proveedor al buscar una identidad vinculada. Para Okta, el emisor está representado por el dominio de Okta. Para Microsoft Entra ID, se deriva del identificador del directorio (tenant). Para un proveedor personalizado, está representado por la URL del proveedor.
- **Dominio de correo electrónico de inicio de sesión:** El dominio de correo electrónico que Tuist utiliza para descubrir un proveedor de Okta o personalizado desde la página general de inicio de sesión. Una vez verificado, también establece qué direcciones de correo electrónico pueden considerarse de confianza para vincular nuevas cuentas y para la inscripción automática.
- **Política de inscripción:** Determina si un usuario del dominio de confianza necesita una invitación o puede unirse automáticamente.
- **Aprovisionamiento:** Crea y gestiona la pertenencia a la organización de forma independiente al flujo de inicio de sesión.

El emisor del proveedor y el dominio de correo electrónico de inicio de sesión suelen ser diferentes. Por ejemplo, una empresa puede usar `example.com` para el correo electrónico de los empleados, mientras que su emisor de proveedor es `https://login.vendor.example.net`. Las nuevas configuraciones de Okta y de proveedores personalizados almacenan estos valores por separado.

### Verificar un dominio de correo electrónico de inicio de sesión {#verify-a-login-email-domain}

Las configuraciones de Okta y de proveedores personalizados requieren un dominio de correo electrónico de inicio de sesión verificado antes de poder crear una nueva cuenta de Tuist o vincular una cuenta existente mediante su dirección de correo electrónico. Los miembros aún pueden <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">vincular su cuenta existente</.localized_link> mientras el dominio no esté verificado.

1. Introduce el dominio de correo electrónico de los empleados, como `example.com`, en **Dominio de correo electrónico de inicio de sesión**.
2. Guarda la configuración del inicio de sesión único.
3. Añade el registro TXT que muestra Tuist a la configuración del [Sistema de Nombres de Dominio](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) del dominio.
4. Vuelve a la configuración de Autenticación y haz clic en **Verificar dominio**.

Un dominio de correo electrónico de inicio de sesión verificado solo puede pertenecer a una organización de Tuist. Cambiar el dominio elimina su verificación y requiere publicar el nuevo registro TXT. La inscripción automática permanece pausada hasta que el dominio esté verificado.

Tuist vuelve a comprobar el registro TXT diariamente. Si un registro deja de resolverse, la verificación no se elimina de inmediato: el dominio la mantiene durante 14 días y la configuración de Autenticación muestra **Verificación próxima a caducar** junto con el registro que debe publicarse de nuevo. Publicar el registro y verificarlo elimina la advertencia. Un dominio cuyo registro siga faltando después de 14 días vuelve al estado no verificado, y el descubrimiento del proveedor, la vinculación de identidades y la inscripción automática se detienen hasta que se verifique de nuevo. Una búsqueda que falle por cualquier otro motivo no reinicia el temporizador ni elimina la verificación por sí sola. Los dominios verificados antes de que se introdujeran las comprobaciones diarias no se vuelven a comprobar.

Google Workspace no requiere este paso de verificación separado en Tuist porque Google proporciona el dominio de Workspace verificado como parte de la identidad autenticada.

### Elegir una política de inscripción {#choose-an-enrollment-policy}

Tuist admite dos políticas de inscripción:

- **Solo con invitación:** El usuario necesita una invitación de la organización. Para Okta y los proveedores personalizados, el dominio de correo electrónico de inicio de sesión debe estar verificado antes de que el proveedor pueda crear una cuenta nueva de Tuist. Un usuario invitado con una cuenta de Tuist existente acepta primero la invitación y luego vincula la identidad del proveedor como se describe en <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Vincular una cuenta de Tuist existente</.localized_link>.
- **Automática:** Un usuario cuyo correo electrónico autenticado coincide con el dominio de confianza puede crear o vincular una cuenta y unirse a la organización sin necesidad de invitación. Las configuraciones de Google utilizan el dominio de Workspace. Okta y los proveedores personalizados requieren un dominio de correo electrónico de inicio de sesión verificado.

Las configuraciones de Google tienen la inscripción automática activada de forma predeterminada. Las nuevas configuraciones de Okta y de proveedores personalizados tienen la inscripción solo con invitación activada de forma predeterminada.

La opción **Forzar inicio de sesión único** es independiente de la inscripción. La aplicación de esta medida impide que los miembros existentes de la organización utilicen correo electrónico y contraseña; no otorga la pertenencia a la organización.

### Elegir el rol que obtienen los miembros inscritos {#choose-the-enrollment-role}

Los miembros que se unen automáticamente reciben el <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> establecido en **Rol para miembros inscritos**, que es `user` a menos que un administrador lo cambie. Establecerlo como `viewer` permite el inicio de sesión a todos los usuarios del directorio sin darles la capacidad de modificar elementos.

Esta opción no puede establecerse como `admin`, se aplica tanto a los miembros aprovisionados mediante <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link> sin un rol como a aquellos que inician sesión, y nunca sobrescribe un rol establecido manualmente por un administrador.

### Vincular una cuenta de Tuist existente {#link-an-existing-account}

Una identidad de proveedor vinculada inicia sesión en toda la cuenta de Tuist, incluidas todas las demás organizaciones a las que pertenezca la cuenta. Para Okta y los proveedores personalizados, Tuist vincula automáticamente una cuenta existente solo cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado o cuando el aprovisionamiento SCIM de la organización creó la cuenta.

Los miembros cuya cuenta no cumple los requisitos vinculan la identidad ellos mismos:

1. Inicia sesión en Tuist con el método de inicio de sesión habitual de la cuenta.
2. Abre Tuist desde el proveedor de identidad, como su icono de aplicación, o abre uno de los proyectos de la organización si esta fuerza el inicio de sesión único.
3. Confirma la organización y la cuenta del proveedor de identidad que muestra Tuist, luego haz clic en **Vincular cuenta**.

Si un miembro inicia el proceso con inicio de sesión único mientras está desconectado, se le pedirá que inicie sesión primero y Tuist volverá a la confirmación después. La vinculación no depende de la verificación del dominio, por lo que los miembros pueden usar el inicio de sesión único antes de que el dominio esté verificado.

### Organizaciones existentes {#existing-organizations}

Todas las organizaciones de Okta y de proveedores personalizados utilizan el modelo de dominio verificado. El modo de compatibilidad temporal ha sido eliminado.

Si tu dominio de correo electrónico de inicio de sesión no está verificado:

- Los miembros vinculados existentes pueden continuar iniciando sesión y la aplicación existente de SSO sigue aplicándose a los miembros de la organización.
- La página de inicio de sesión detecta tu proveedor únicamente a través de la pertenencia existente a la organización.
- La inscripción automática está pausada y el proveedor no puede crear nuevas cuentas de Tuist, incluso con una invitación.
- Los miembros no vinculados inician sesión en su cuenta de Tuist existente y confirman el vínculo como se describe arriba. Las cuentas creadas por el aprovisionamiento SCIM de la organización aún pueden vincularse en el primer inicio de sesión mediante SSO.
- No se requiere que los nuevos registros utilicen tu proveedor solo porque su dirección de correo electrónico use tu dominio.

Las configuraciones de inscripción y aplicación habilitadas existentes permanecen guardadas y pueden desactivarse. Los administradores pueden editar la configuración mientras el dominio no esté verificado; habilitar cualquiera de estas opciones requiere verificación. La verificación reanuda la inscripción automática para las direcciones de correo electrónico coincidentes cuando esa opción está habilitada. El comportamiento de Google Workspace no cambia.

Tu **Dominio de correo electrónico de inicio de sesión** podría ya estar completado a partir de los miembros de tu organización. Confirma el valor, publica el registro de texto y haz clic en **Verificar dominio**. Mantén el registro publicado para las comprobaciones diarias.

## Google Workspace {#google}

El inicio de sesión único de Google Workspace autentica a los usuarios frente a un dominio de Workspace. Los administradores pueden permitir que los usuarios coincidentes se unan automáticamente o requerir una invitación.

> [!NOTE]
> **Requisitos previos**
>
> Necesitas una organización de Google Workspace con un dominio verificado. También debes estar autenticado con Google utilizando un correo electrónico asociado al dominio que estás configurando.

### Configuración {#google-setup}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Google** como proveedor.
4. Introduce tu dominio de Google Workspace, como `example.com`.
5. Elige **Inscripción automática** o inscripción solo con invitación. La inscripción automática está habilitada de forma predeterminada para Google.
6. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.
7. Haz clic en **Guardar cambios**.

## Okta {#okta}

Okta utiliza [OpenID Connect](https://openid.net/developers/how-connect-works/) para autenticar a los miembros. El dominio de Okta identifica al emisor del proveedor; el dominio de correo electrónico de inicio de sesión, verificado por separado, controla el descubrimiento, la vinculación de nuevas cuentas y la inscripción.

Si también deseas que Okta cree, actualice o desaprovisione miembros automáticamente, configura <.localized_link href="/guides/integrations/authentication/scim#okta">el aprovisionamiento del Sistema de Gestión de Identidades entre Dominios de Okta</.localized_link> después de que el inicio de sesión único esté funcionando.

### Paso 1: Crear una aplicación de Okta {#okta-step-1}

1. En tu panel de administración de Okta, ve a **Aplicaciones > Aplicaciones > Crear integración de aplicación**.
2. Selecciona **OpenID Connect** y **Aplicación web**.
3. Establece el nombre de la aplicación, como `Tuist`. Opcionalmente, sube el [logo de Tuist](https://tuist.dev/images/tuist_dashboard.png).
4. Establece el **URI de redirección de inicio de sesión** con el valor que se muestra en la página de configuración de Autenticación, como `https://tuist.dev/users/auth/okta/callback`.
5. En **Asignaciones**, elige el control de acceso deseado y guarda.
6. Copia el **ID de cliente** y el **Secreto de cliente** desde la configuración general de la aplicación. Anota tu **dominio de Okta**, como `your-company.okta.com`.
7. Opcionalmente, para permitir el inicio de sesión desde el panel de Okta, haz clic en **Editar** en Configuración general, cambia **Inicio de sesión iniciado por** a **Okta o la aplicación**, selecciona **Mostrar icono de la aplicación a los usuarios** y establece el **URI de inicio de sesión** con el valor que se muestra en la página de configuración de Autenticación.

### Paso 2: Configurar Tuist {#okta-step-2}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Okta** como proveedor.
4. Introduce el **dominio de Okta**, el **ID de cliente** y el **Secreto de cliente**.
5. Introduce el dominio de correo electrónico de los empleados en **Dominio de correo electrónico de inicio de sesión**. Por ejemplo, un dominio de Okta de `your-company.okta.com` puede tener un dominio de correo electrónico de inicio de sesión de `example.com`.
6. Haz clic en **Guardar cambios**.
7. Añade el registro TXT que muestra Tuist al dominio de correo electrónico de inicio de sesión y, a continuación, haz clic en **Verificar dominio**.
8. Elige si los usuarios necesitan una invitación o pueden inscribirse automáticamente y, a continuación, guarda la configuración de nuevo.
9. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.

### Paso 3: Asignar usuarios a la aplicación de Okta {#okta-step-3}

Asigna los usuarios o grupos que deben poder autenticarse a través de la aplicación de Okta.

La asignación concede acceso al flujo de inicio de sesión, pero la pertenencia a la organización sigue siguiendo la política de inscripción. Si los mismos usuarios se aprovisionan a través del Sistema de Gestión de Identidades entre Dominios, Tuist vincula la identidad de Okta a la cuenta que SCIM creó la primera vez que el usuario inició sesión. Un miembro cuya cuenta existía antes de que SCIM la añadiera se vincula cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado, o después de confirmar el vínculo desde su cuenta con sesión iniciada.

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID autentica a los miembros mediante [OpenID Connect](https://openid.net/developers/how-connect-works/). Tuist deriva los puntos finales de autorización, token e información de usuario a partir del identificador de tu directorio (inquilino), por lo que solo debes introducir ese valor junto con las credenciales de la aplicación.

Si también deseas que Entra ID cree, actualice o desaprovisione miembros automáticamente, configura <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">el aprovisionamiento del Sistema de Gestión de Identidades entre Dominios de Microsoft Entra ID</.localized_link> después de que el inicio de sesión único esté funcionando.

### Paso 1: Registrar una aplicación de Entra {#entra-step-1}

1. En el [Centro de administración de Microsoft Entra](https://entra.microsoft.com), ve a **Identidad > Aplicaciones > Registros de aplicaciones > Nuevo registro**.
2. Establece el nombre de la aplicación, como `Tuist`.
3. En **URI de redirección**, selecciona la plataforma **Web** e introduce el valor que se muestra en la página de configuración de Autenticación, como `https://tuist.dev/users/auth/oauth2/callback`.
4. Registra la aplicación y, a continuación, copia el **ID de directorio (inquilino)** y el **ID de aplicación (cliente)** desde su página de resumen.
5. Ve a **Certificados y secretos > Nuevo secreto de cliente**, crea un secreto y copia su **Valor**. Microsoft muestra el valor solo una vez y cada secreto de cliente tiene una fecha de caducidad, por lo que debes registrar cuándo es necesario rotarlo.
6. Ve a **Permisos de API** y confirma que los permisos delegados de Microsoft Graph `openid`, `profile` y `email` están concedidos.
7. Opcionalmente, para permitir que los miembros inicien el flujo de inicio de sesión desde el portal Mis aplicaciones, establece la **URL de la página principal** en **Marca y propiedades** con el valor que se muestra en la página de configuración de Autenticación.

### Paso 2: Configurar Tuist {#entra-step-2}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Microsoft Entra ID** como proveedor.
4. Introduce el **ID de directorio (inquilino)**, el **ID de cliente** y el **Secreto de cliente**.
5. Introduce el dominio de correo electrónico de los empleados en **Dominio de correo electrónico de inicio de sesión**. Por ejemplo, un directorio cuyos usuarios inician sesión como `first.last@example.com` tiene un dominio de correo electrónico de inicio de sesión de `example.com`.
6. Haz clic en **Guardar cambios**.
7. Añade el registro TXT que muestra Tuist al dominio de correo electrónico de inicio de sesión y, a continuación, haz clic en **Verificar dominio**.
8. Elige si los usuarios necesitan una invitación o pueden inscribirse automáticamente y, a continuación, guarda la configuración de nuevo.
9. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.

### Paso 3: Asignar usuarios a la aplicación de Entra {#entra-step-3}

Asigna los usuarios o grupos que deben poder autenticarse. Si la aplicación está configurada para requerir asignación, solo los usuarios asignados pueden iniciar sesión.

La asignación concede acceso al flujo de inicio de sesión, pero la pertenencia a la organización sigue siguiendo la política de inscripción. Si los mismos usuarios se aprovisionan a través del Sistema de Gestión de Identidades entre Dominios, Tuist vincula la identidad de Entra a la cuenta que SCIM creó la primera vez que el usuario inició sesión. Un miembro cuya cuenta existía antes de que SCIM la añadiera se vincula cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado, o después de confirmar el vínculo desde su cuenta con sesión iniciada.

### Requisitos para la reclamación de correo electrónico {#entra-email-claim}

Tuist lee el perfil del usuario autenticado desde el punto final de información de usuario de Microsoft Graph, que devuelve una dirección de correo electrónico solo cuando el usuario tiene una disponible. Un usuario del directorio cuyo atributo `mail` esté vacío no puede iniciar sesión, porque Tuist no tiene ninguna dirección con la que comparar el dominio de correo electrónico de inicio de sesión.

Confirma que los miembros que asignas tienen una dirección de correo electrónico rellenada en el directorio antes de implementar el inicio de sesión único. Los usuarios sincronizados desde Active Directory local sin una bandeja de entrada son el caso más común en el que falta este atributo.

### Acceso condicional y autenticación multifactor {#entra-conditional-access}

Las políticas de Acceso condicional, la autenticación multifactor y las políticas de riesgo de inicio de sesión se aplican a la aplicación de Tuist de la misma manera que a cualquier otra aplicación de Entra, porque se evalúan durante la solicitud de autorización. No se requiere ninguna configuración adicional de Tuist.

## Proveedor OAuth 2.0 personalizado {#custom-oauth-2-provider}

Un proveedor OAuth 2.0 personalizado permite a una organización utilizar un servicio de identidad distinto de Google Workspace u Okta. El punto final de información de usuario del proveedor debe devolver un identificador de usuario estable y una dirección de correo electrónico.

1. En el proveedor, crea una aplicación web OAuth 2.0.
2. Establece el **URI de redirección de inicio de sesión** y el opcional **URI de inicio de login** con los valores que se muestran en la configuración de autenticación de Tuist.
3. En Tuist, habilita el inicio de sesión único y selecciona **OAuth2**.
4. Introduce la URL del proveedor, el punto final de autorización, el punto final de token, el punto final de información de usuario, el identificador de cliente y el secreto de cliente.
5. Introduce y guarda el **Dominio de correo electrónico de inicio de sesión**. Este es el dominio de correo electrónico de los empleados, no la URL del proveedor.
6. Añade el registro de texto que muestra Tuist al dominio de correo electrónico de inicio de sesión y, a continuación, haz clic en **Verificar dominio**.
7. Elige solo por invitación o inscripción automática y guarda la configuración.
8. Prueba el inicio de sesión antes de habilitar opcionalmente **Forzar inicio de sesión único**.

La URL del proveedor limita las identidades al proveedor emisor. El dominio de correo electrónico de inicio de sesión verificado determina qué direcciones de correo electrónico puede confiar Tuist al vincular o inscribir usuarios.

## Configuración desde la línea de comandos {#command-line-configuration}

La interfaz de línea de comandos puede configurar Google Workspace u Okta y seleccionar una política de inscripción. Por ejemplo:

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

Microsoft Entra ID y los proveedores personalizados se configuran desde la configuración de autenticación de la organización, no desde la línea de comandos.

El valor `--organization-id` identifica la organización del proveedor. No es el dominio de correo electrónico de inicio de sesión. Añade y verifica el dominio de correo electrónico de inicio de sesión desde la configuración de autenticación de la organización antes de inscribir nuevos usuarios de Okta.

## Solución de problemas {#troubleshooting}

### Los miembros existentes pueden iniciar sesión, pero los nuevos usuarios no {#existing-members-can-sign-in-but-new-users-cannot}

Para configuraciones de Okta y de proveedores personalizados, confirma que el dominio de correo electrónico de inicio de sesión esté verificado. Luego, invita al usuario o habilita la inscripción automática.

### El inicio de sesión único te pide que inicies sesión primero {#single-sign-on-asks-you-to-log-in-first}

La dirección de correo electrónico de tu cuenta de Tuist no está en el dominio de correo electrónico de inicio de sesión verificado de la organización, o el dominio aún no está verificado, por lo que Tuist no vincula automáticamente la identidad del proveedor. Inicia sesión con tu método habitual y confirma el vínculo, como se describe en <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Vincular una cuenta existente de Tuist</.localized_link>.
### Tuist no puede encontrar una organización para una dirección de correo electrónico {#tuist-cannot-find-an-organization-for-an-email-address}

Confirma que el usuario introdujo la dirección de correo electrónico esperada y que su dominio coincide exactamente con el dominio de correo electrónico de inicio de sesión verificado. Los miembros existentes también pueden descubrirse a través de su membresía actual en la organización.

### La verificación del dominio sigue pendiente {#domain-verification-remains-pending}

Confirma que el nombre y el valor del registro de texto coinciden exactamente con los valores mostrados en Tuist. Los cambios en el Sistema de Nombres de Dominio pueden tardar en propagarse, así que vuelve a intentar la verificación después de que el registro esté disponible públicamente.

### El inicio de sesión se detuvo después de cambiar el proveedor {#sign-in-stopped-after-changing-the-provider}

Confirma la nueva configuración del proveedor, verifica el dominio de correo electrónico de inicio de sesión y prueba el flujo de inicio de sesión antes de habilitar la aplicación forzosa.
