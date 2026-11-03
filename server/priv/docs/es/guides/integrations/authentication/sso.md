---
{
  "title": "Inicio de sesión único",
  "titleTemplate": ":title | Autenticación | Integraciones | Guías | Tuist",
  "description": "Aprende a configurar el inicio de sesión único, verificar el dominio de correo electrónico de inicio de sesión y elegir cómo los usuarios se unen a tu organización."
}
---
# Inicio de sesión único {#single-sign-on}

Tuist ofrece inicio de sesión único como opción de acceso para proporcionar seguridad adicional a la cuenta de tu organización.

El inicio de sesión único se configura desde la pestaña **Autenticación** en la configuración de tu organización. Se admiten Google Workspace, Okta, Microsoft Entra ID y proveedores personalizados de [OAuth 2.0](https://oauth.net/2/).

Microsoft Entra ID es un proveedor de OpenID Connect que Tuist configura por ti a partir del identificador de tu directorio. Todo lo que esta guía describe para proveedores personalizados, incluida la verificación del dominio de correo electrónico de inicio de sesión y la inscripción, también se aplica a él.

> [!NOTE]
> El inicio de sesión único controla cómo se autentican los miembros y si los usuarios autenticados pueden unirse automáticamente. La aprovisionamiento mediante <.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management</.localized_link> controla si un proveedor de identidad puede crear, actualizar y desaprovisionar miembros de la organización. Para Okta, la mayoría de las organizaciones configuran ambas opciones.

## Cómo funciona el acceso {#how-access-works}

La identidad del proveedor, el descubrimiento de inicio de sesión y la inscripción en la organización son aspectos independientes:

- **Emisor del proveedor:** La organización proveedora o el servidor de autorización que autenticó al usuario. Tuist combina el proveedor, el emisor y el identificador estable del usuario del proveedor al buscar una identidad vinculada. Para Okta, el emisor está representado por el dominio de Okta. Para Microsoft Entra ID, se deriva del identificador del directorio (tenant). Para un proveedor personalizado, está representado por la URL del proveedor.
- **Dominio de correo electrónico de inicio de sesión:** El dominio de correo electrónico que Tuist utiliza para descubrir un proveedor de Okta o personalizado desde la página general de inicio de sesión. Una vez verificado, también establece qué direcciones de correo electrónico pueden considerarse de confianza para vincular nuevas cuentas y para la inscripción automática.
- **Política de inscripción:** Determina si un usuario del dominio de confianza necesita una invitación o puede unirse automáticamente.
- **Aprovisionamiento:** Crea y gestiona la membresía en la organización de forma independiente al flujo de inicio de sesión.

El emisor del proveedor y el dominio de correo electrónico de inicio de sesión suelen ser diferentes. Por ejemplo, una empresa puede usar `example.com` para el correo electrónico de los empleados mientras que su emisor de proveedor es `https://login.vendor.example.net`. Las nuevas configuraciones de Okta y de proveedores personalizados almacenan estos valores por separado.

### Verificar un dominio de correo electrónico de inicio de sesión {#verify-a-login-email-domain}

Las configuraciones de Okta y de proveedores personalizados requieren un dominio de correo electrónico de inicio de sesión verificado antes de poder crear una nueva cuenta de Tuist o vincular una cuenta existente por su dirección de correo electrónico. Los miembros aún pueden <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">vincular su cuenta existente</.localized_link> mientras el dominio no esté verificado.

1. Introduce el dominio de correo electrónico de los empleados, como `example.com`, en **Dominio de correo electrónico de inicio de sesión**.
2. Guarda la configuración de inicio de sesión único.
3. Añade el registro TXT que muestra Tuist a la configuración del [Sistema de Nombres de Dominio](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) del dominio.
4. Vuelve a la configuración de Autenticación y haz clic en **Verificar dominio**.

Un dominio de correo electrónico de inicio de sesión verificado solo puede pertenecer a una organización de Tuist. Cambiar el dominio borra su verificación y requiere publicar el nuevo registro TXT. La inscripción automática permanece pausada hasta que el dominio esté verificado.

Tuist vuelve a comprobar el registro TXT diariamente. Un registro que deja de resolverse no borra la verificación de inmediato: el dominio la mantiene durante 14 días y la configuración de Autenticación muestra **Verificación próxima a caducar** junto con el registro que debes volver a publicar. Publicar el registro y verificarlo elimina la advertencia. Un dominio cuyo registro siga faltando después de 14 días vuelve al estado no verificado, y el descubrimiento del proveedor, la vinculación de identidades y la inscripción automática se detienen hasta que se vuelva a verificar. Una búsqueda que falle por cualquier otro motivo no reinicia el temporizador ni borra la verificación por sí sola. Los dominios verificados antes de que se introdujeran las comprobaciones diarias no se vuelven a comprobar.

Google Workspace no requiere este paso de verificación separado en Tuist porque Google proporciona el dominio de Workspace verificado como parte de la identidad autenticada.

### Elegir una política de inscripción {#choose-an-enrollment-policy}

Tuist admite dos políticas de inscripción:

- **Solo por invitación:** Un usuario necesita una invitación de la organización. Para Okta y proveedores personalizados, el dominio de correo electrónico de inicio de sesión debe estar verificado antes de que el proveedor pueda crear una cuenta nueva de Tuist. Un usuario invitado con una cuenta de Tuist existente acepta primero la invitación y luego vincula la identidad del proveedor como se describe en <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Vincular una cuenta de Tuist existente</.localized_link>.
- **Automática:** Un usuario cuyo correo electrónico autenticado coincide con el dominio de confianza puede crear o vincular una cuenta y unirse a la organización sin invitación. Las configuraciones de Google utilizan el dominio de Workspace. Okta y los proveedores personalizados requieren un dominio de correo electrónico de inicio de sesión verificado.

Las configuraciones de Google tienen como valor predeterminado la inscripción automática. Las nuevas configuraciones de Okta y de proveedores personalizados tienen como valor predeterminado la inscripción solo por invitación.

La configuración **Forzar inicio de sesión único** es independiente de la inscripción. El acceso a las páginas protegidas del navegador de la organización requiere una sesión autenticada a través de su proveedor y emisor actuales (o Google Workspace verificado). Una identidad vinculada histórica o la autenticación a través del proveedor de otra organización no son suficientes. El inicio de sesión normal en Tuist y el acceso a otras cuentas siguen disponibles; la aplicación de esta norma no concede la membresía en la organización. Los paneles públicos anónimos y las concesiones de soporte técnico con límite de tiempo mantienen sus reglas de acceso separadas. Las páginas de vista previa de aplicaciones aplican la restricción solo a los miembros de la organización, por lo que los enlaces de vista previa compartidos fuera de la organización siguen funcionando para las vistas previas que los visitantes ya podían abrir.

La aplicación de la norma afecta dondequiera que la sesión de un miembro llegue a la organización:

- **Panel de control**: las páginas de la organización requieren una sesión iniciada con el proveedor de la organización.
- **CLI de Tuist, la aplicación de Tuist, clientes MCP y la referencia de la API**: al iniciar sesión en ellos se crea una credencial que actúa en nombre del miembro en todas las organizaciones, por lo que requiere una sesión iniciada a través de la organización que fuerza el inicio de sesión único. Tuist redirige primero al proveedor a un miembro que haya iniciado sesión de otra manera y rechaza el inicio de sesión con correo electrónico y contraseña o con Apple. Cada vez que uno de estos clientes renueva su credencial, Tuist vuelve a comprobarlo. Una credencial obtenida mediante el inicio de sesión único de la organización sigue renovándose, al igual que una obtenida de otra manera por un miembro que ya ha iniciado sesión a través del proveedor de la organización. Cualquier otra credencial, como una que un miembro obtuvo con una contraseña antes de que la organización forzara el inicio de sesión único, sigue renovándose durante cuatro semanas desde su primera renovación bajo la aplicación de la norma; después, el cliente pide al miembro que inicie sesión de nuevo. Iniciar sesión a través del proveedor en ese periodo, en el panel de control o con `tuist auth login`, mantiene la renovación.

Un miembro de varias organizaciones que fuerzan el inicio de sesión único no puede iniciar sesión en la CLI, la aplicación o los clientes MCP, porque una sesión inicia sesión a través de una sola organización.

### Elige el rol que obtienen los miembros inscritos {#choose-the-enrollment-role}

Los miembros que se unen automáticamente obtienen el <.localized_link href="/guides/server/accounts-and-projects#roles">rol</.localized_link> configurado en **Rol para miembros inscritos**, que es `user` a menos que un administrador lo cambie. Establecerlo en `viewer` permite el inicio de sesión a todos los usuarios del directorio sin darles a todos la capacidad de realizar cambios.

La configuración no puede establecerse en `admin`, se aplica a los miembros aprovisionados mediante <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link> sin un rol, así como a los que inician sesión, y nunca sobrescribe un rol establecido manualmente por un administrador.

### Vincular una cuenta de Tuist existente {#link-an-existing-account}

Una identidad de proveedor vinculada inicia sesión en toda la cuenta de Tuist, incluidas todas las demás organizaciones a las que pertenece la cuenta. Para Okta y proveedores personalizados, Tuist vincula automáticamente una cuenta existente solo cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado, o cuando el aprovisionamiento SCIM de la organización creó la cuenta.

Los miembros cuya cuenta no cumple los requisitos vinculan la identidad ellos mismos:

1. Inicia sesión en Tuist con el método de inicio de sesión habitual de la cuenta.
2. Abre Tuist desde el proveedor de identidad, como su icono de aplicación, o abre uno de los proyectos de la organización si esta fuerza el inicio de sesión único.
3. Confirma la organización y la cuenta del proveedor de identidad que muestra Tuist y haz clic en **Vincular cuenta**.

Se pedirá a un miembro que comience con el inicio de sesión único mientras está desconectado que inicie sesión primero, y Tuist volverá a la confirmación después. La vinculación no depende de la verificación del dominio, por lo que los miembros pueden usar el inicio de sesión único antes de que el dominio esté verificado.

### Organizaciones existentes {#existing-organizations}

Todas las organizaciones de Okta y de proveedores personalizados utilizan el modelo de dominio verificado. El modo de compatibilidad temporal se ha eliminado.

Si tu dominio de correo electrónico de inicio de sesión no está verificado:

- Los miembros vinculados existentes pueden seguir iniciando sesión y la aplicación existente de SSO sigue aplicándose a los miembros de la organización.
- La página de inicio de sesión descubre tu proveedor únicamente a través de la membresía existente en la organización.
- La inscripción automática está pausada y el proveedor no puede crear nuevas cuentas de Tuist, ni siquiera con una invitación.
- Los miembros no vinculados inician sesión en su cuenta de Tuist existente y confirman el vínculo como se describe arriba. Las cuentas creadas por el aprovisionamiento SCIM de la organización aún pueden vincularse en el primer inicio de sesión SSO.
- No se exige a los nuevos registros que utilicen tu proveedor únicamente porque su dirección de correo electrónico use tu dominio.

Las configuraciones de inscripción y aplicación de normas habilitadas existentes permanecen guardadas y pueden desactivarse. Los administradores pueden editar la configuración mientras el dominio no está verificado; habilitar cualquiera de estas configuraciones requiere verificación. La verificación reanuda la inscripción automática para las direcciones de correo electrónico coincidentes cuando esa configuración está habilitada. El comportamiento de Google Workspace no cambia.

Tu **Dominio de correo electrónico de inicio de sesión** puede ya estar rellenado a partir de los miembros de tu organización. Confirma el valor, publica el registro de texto y haz clic en **Verificar dominio**. Mantén el registro publicado para las comprobaciones diarias.

## Google Workspace {#google}

El inicio de sesión único de Google Workspace autentica a los usuarios frente a un dominio de Workspace. Los administradores pueden permitir que los usuarios coincidentes se unan automáticamente o exigir una invitación.

> [!NOTE]
> **Requisitos previos**
>
> Necesitas una organización de Google Workspace con un dominio verificado. También debes estar autenticado con Google utilizando un correo electrónico vinculado al dominio que estás configurando.

### Configuración {#google-setup}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Google** como proveedor.
4. Introduce tu dominio de Google Workspace, como `example.com`.
5. Elige **Inscripción automática** o inscripción solo por invitación. La inscripción automática está habilitada de forma predeterminada para Google.
6. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.
7. Haz clic en **Guardar cambios**.

## Okta {#okta}

Okta utiliza [OpenID Connect](https://openid.net/developers/how-connect-works/) para autenticar a los miembros. El dominio de Okta identifica al emisor del proveedor; el dominio de correo electrónico de inicio de sesión verificado por separado controla el descubrimiento, la vinculación de nuevas cuentas y la inscripción.

Si también quieres que Okta cree, actualice o desprovisione miembros automáticamente, configura <.localized_link href="/guides/integrations/authentication/scim#okta">el aprovisionamiento del Sistema de Gestión de Identidades entre Dominios de Okta</.localized_link> después de que el inicio de sesión único funcione.

### Paso 1: Crear una aplicación de Okta {#okta-step-1}

1. En tu panel de administración de Okta, ve a **Aplicaciones > Aplicaciones > Crear integración de aplicación**.
2. Selecciona **OpenID Connect** y **Aplicación web**.
3. Establece el nombre de la aplicación, como `Tuist`. Opcionalmente, sube el [logotipo de Tuist](https://tuist.dev/images/tuist_dashboard.png).
4. Establece el **URI de redirección de inicio de sesión** al valor que se muestra en la página de configuración de Autenticación, como `https://tuist.dev/users/auth/okta/callback`.
5. En **Asignaciones**, elige el control de acceso deseado y guarda.
6. Copia el **ID de cliente** y el **Secreto de cliente** desde la configuración general de la aplicación. Anota tu **dominio de Okta**, como `your-company.okta.com`.
7. Opcionalmente, para permitir el inicio de sesión desde el panel de Okta, haz clic en **Editar** en Configuración general, cambia **Inicio de sesión iniciado por** a **Okta o la aplicación**, selecciona **Mostrar icono de la aplicación a los usuarios** y establece el **URI de inicio de sesión** al valor que se muestra en la página de configuración de Autenticación.

### Paso 2: Configurar Tuist {#okta-step-2}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Okta** como proveedor.
4. Introduce el **dominio de Okta**, el **ID de cliente** y el **Secreto de cliente**.
5. Introduce el dominio de correo electrónico de los empleados en **Dominio de correo electrónico de inicio de sesión**. Por ejemplo, un dominio de Okta de `your-company.okta.com` puede tener un dominio de correo electrónico de inicio de sesión de `example.com`.
6. Haz clic en **Guardar cambios**.
7. Añade el registro de texto mostrado por Tuist al dominio de correo electrónico de inicio de sesión y luego haz clic en **Verificar dominio**.
8. Elige si los usuarios necesitan una invitación o pueden inscribirse automáticamente y luego guarda la configuración de nuevo.
9. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.

### Paso 3: Asignar usuarios a la aplicación de Okta {#okta-step-3}

Asigna los usuarios o grupos que deben poder autenticarse a través de la aplicación de Okta.

La asignación concede acceso al flujo de inicio de sesión, pero la pertenencia a la organización sigue la política de inscripción. Si los mismos usuarios se aprovisionan a través del Sistema de Gestión de Identidades entre Dominios, Tuist vincula la identidad de Okta a la cuenta que SCIM creó la primera vez que el usuario inició sesión. Un miembro cuya cuenta existía antes de que SCIM la añadiera se vincula cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado, o después de confirmar el vínculo desde su cuenta iniciada.

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID autentica a los miembros mediante [OpenID Connect](https://openid.net/developers/how-connect-works/). Tuist deriva los puntos finales de autorización, token e información de usuario a partir de tu identificador de directorio (inquilino), por lo que solo debes introducir ese valor junto con las credenciales de la aplicación.

Si también quieres que Entra ID cree, actualice o desprovisione miembros automáticamente, configura <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">el aprovisionamiento del Sistema de Gestión de Identidades entre Dominios de Microsoft Entra ID</.localized_link> después de que el inicio de sesión único funcione.

### Paso 1: Registrar una aplicación de Entra {#entra-step-1}

1. En el [centro de administración de Microsoft Entra](https://entra.microsoft.com), ve a **Identidad > Aplicaciones > Registros de aplicaciones > Nuevo registro**.
2. Establece el nombre de la aplicación, como `Tuist`.
3. En **URI de redirección**, selecciona la plataforma **Web** e introduce el valor que se muestra en la página de configuración de Autenticación, como `https://tuist.dev/users/auth/oauth2/callback`.
4. Registra la aplicación y luego copia el **ID de directorio (inquilino)** y el **ID de aplicación (cliente)** desde su página de resumen.
5. Ve a **Certificados y secretos > Nuevo secreto de cliente**, crea un secreto y copia su **Valor**. Microsoft muestra el valor solo una vez y cada secreto de cliente tiene una fecha de caducidad, así que registra cuándo debe rotarse.
6. Ve a **Permisos de API** y confirma que los permisos delegados de Microsoft Graph `openid`, `profile` y `email` están concedidos.
7. Opcionalmente, para permitir que los miembros inicien el flujo de inicio de sesión desde el portal Mis aplicaciones, establece la **URL de la página principal** en **Marca y propiedades** al valor que se muestra en la página de configuración de Autenticación.

### Paso 2: Configurar Tuist {#entra-step-2}

1. Navega a la pestaña de configuración de **Autenticación** de tu organización.
2. Habilita el inicio de sesión único.
3. Selecciona **Microsoft Entra ID** como proveedor.
4. Introduce el **ID de directorio (inquilino)**, el **ID de cliente** y el **Secreto de cliente**.
5. Introduce el dominio de correo electrónico de los empleados en **Dominio de correo electrónico de inicio de sesión**. Por ejemplo, un directorio cuyos usuarios inician sesión como `first.last@example.com` tiene un dominio de correo electrónico de inicio de sesión de `example.com`.
6. Haz clic en **Guardar cambios**.
7. Añade el registro de texto mostrado por Tuist al dominio de correo electrónico de inicio de sesión y luego haz clic en **Verificar dominio**.
8. Elige si los usuarios necesitan una invitación o pueden inscribirse automáticamente y luego guarda la configuración de nuevo.
9. Opcionalmente, habilita **Forzar inicio de sesión único** después de probar el flujo de inicio de sesión.

### Paso 3: Asignar usuarios a la aplicación de Entra {#entra-step-3}

Asigna los usuarios o grupos que deben poder autenticarse. Si la aplicación está configurada para requerir asignación, solo los usuarios asignados pueden iniciar sesión.

La asignación otorga acceso al flujo de inicio de sesión, pero la membresía en la organización sigue siguiendo la política de inscripción. Si los mismos usuarios se aprovisionan a través del Sistema para la Gestión de Identidades entre Dominios (SCIM), Tuist vincula la identidad de Entra a la cuenta que SCIM creó la primera vez que el usuario inició sesión. Un miembro cuya cuenta existía antes de que SCIM la añadiera se vincula cuando su dirección de correo electrónico está en el dominio de correo electrónico de inicio de sesión verificado, o después de confirmar el vínculo desde su cuenta con sesión iniciada.

### Requisitos para la reclamación de correo electrónico {#entra-email-claim}

Tuist lee el perfil del usuario autenticado desde el punto final de información de usuario de Microsoft Graph, que devuelve una dirección de correo electrónico solo cuando el usuario tiene una disponible. Un usuario del directorio cuyo atributo `mail` esté vacío no puede iniciar sesión, porque Tuist no tiene ninguna dirección con la que coincidir contra el dominio de correo electrónico de inicio de sesión.

Confirma que los miembros que asignas tienen una dirección de correo electrónico rellenada en el directorio antes de implementar el inicio de sesión único. Los usuarios sincronizados desde Active Directory local sin una bandeja de entrada son el caso más común donde falta este atributo.

### Acceso condicional y autenticación multifactor {#entra-conditional-access}

Las políticas de Acceso condicional, la autenticación multifactor y las políticas de riesgo de inicio de sesión se aplican a la aplicación de Tuist de la misma manera que se aplican a cualquier otra aplicación de Entra, porque se evalúan durante la solicitud de autorización. No se requiere configuración adicional de Tuist.

## Proveedor personalizado de OAuth 2.0 {#custom-oauth-2-provider}

Un proveedor personalizado de OAuth 2.0 permite a una organización utilizar un servicio de identidad distinto de Google Workspace u Okta. El punto final de información de usuario del proveedor debe devolver un identificador de usuario estable y una dirección de correo electrónico.

1. En el proveedor, crea una aplicación web OAuth 2.0.
2. Establece la **URI de redirección de inicio de sesión** y la opcional **URI de inicio de sesión** con los valores mostrados en la configuración de Autenticación de Tuist.
3. En Tuist, habilita el inicio de sesión único y selecciona **OAuth2**.
4. Introduce la URL del proveedor, el punto final de autorización, el punto final de token, el punto final de información de usuario, el identificador de cliente y el secreto de cliente.
5. Introduce y guarda el **Dominio de correo electrónico de inicio de sesión**. Este es el dominio de correo electrónico de los empleados, no la URL del proveedor.
6. Añade el registro de texto mostrado por Tuist al dominio de correo electrónico de inicio de sesión y luego haz clic en **Verificar dominio**.
7. Elige inscripción solo por invitación o automática y guarda la configuración.
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

Microsoft Entra ID y los proveedores personalizados se configuran desde la configuración de Autenticación de la organización, no desde la línea de comandos.

El valor `--organization-id` identifica la organización del proveedor. No es el dominio de correo electrónico de inicio de sesión. Añade y verifica el dominio de correo electrónico de inicio de sesión desde la configuración de Autenticación de la organización antes de inscribir nuevos usuarios de Okta.

## Solución de problemas {#troubleshooting}

### Los miembros existentes pueden iniciar sesión, pero los nuevos usuarios no {#existing-members-can-sign-in-but-new-users-cannot}

Para configuraciones de Okta y proveedores personalizados, confirma que el dominio de correo electrónico de inicio de sesión esté verificado. Luego, invita al usuario o habilita la inscripción automática.

### El inicio de sesión único te pide que inicies sesión primero {#single-sign-on-asks-you-to-log-in-first}

La dirección de correo electrónico de tu cuenta de Tuist no está en el dominio de correo electrónico de inicio de sesión verificado de la organización, o el dominio aún no está verificado, por lo que Tuist no vincula automáticamente la identidad del proveedor. Inicia sesión con tu método habitual y confirma el vínculo, como se describe en <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">Vincular una cuenta existente de Tuist</.localized_link>.
### Tuist no puede encontrar una organización para una dirección de correo electrónico {#tuist-cannot-find-an-organization-for-an-email-address}

Confirma que el usuario introdujo la dirección de correo electrónico de empleado esperada y que su dominio coincide exactamente con el dominio de correo electrónico de inicio de sesión verificado. Los miembros existentes también pueden descubrirse a través de su membresía actual en la organización.

### La verificación del dominio sigue pendiente {#domain-verification-remains-pending}

Confirma que el nombre y el valor del registro de texto coinciden exactamente con los valores mostrados en Tuist. Los cambios en el Sistema de Nombres de Dominio (DNS) pueden tardar en propagarse, así que vuelve a intentar la verificación después de que el registro esté disponible públicamente.

### El inicio de sesión se detuvo después de cambiar el proveedor {#sign-in-stopped-after-changing-the-provider}

Confirma la nueva configuración del proveedor, verifica el dominio de correo electrónico de inicio de sesión y prueba el flujo de inicio de sesión antes de habilitar la aplicación forzosa.
