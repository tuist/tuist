---
{
  "title": "Aprovisionamiento SCIM",
  "titleTemplate": ":title | Autenticación | Integraciones | Guías | Tuist",
  "description": "Aprende a configurar el aprovisionamiento SCIM con Okta o Microsoft Entra ID."
}
---
# Aprovisionamiento SCIM {#scim-provisioning}

Tuist admite el aprovisionamiento SCIM 2.0 para que un proveedor de identidad pueda crear, actualizar y desaprovisionar miembros de la organización automáticamente.

SCIM se configura desde la pestaña **Authentication** en la configuración de tu organización. El token SCIM es un token de cuenta propiedad de la organización con ámbito de acceso SCIM y se muestra solo una vez al generarse.

> [!NOTE]
> SCIM controla la membresía y el ciclo de vida. No reemplaza <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>. Configura SSO por separado si los usuarios aprovisionados también deben iniciar sesión a través de tu proveedor de identidad.

Los usuarios aprovisionados ya son miembros de la organización. Cuando inician sesión con la misma dirección de correo electrónico, esa membresía puede establecer confianza para vincular su identidad del proveedor. El <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">dominio de correo electrónico de inicio de sesión verificado</.localized_link> y la <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">política de inscripción</.localized_link> controlan a los usuarios que aún no han sido aprovisionados ni añadidos a la organización.

## Okta {#okta}

Okta utiliza dos aplicaciones separadas para Tuist:

- Una **OIDC Web Application** para iniciar sesión en Tuist.
- Una aplicación **SCIM 2.0 Test App (Header Auth)** para aprovisionar usuarios y grupos en Tuist.

Configura primero <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> si los usuarios deben iniciar sesión con Okta, luego configura el aprovisionamiento SCIM con los pasos siguientes.

### Paso 1: Generar un token SCIM de Tuist {#okta-step-1}

1. En Tuist, navega a la pestaña de configuración **Authentication** de tu organización.
2. En la sección **SCIM provisioning**, copia la **SCIM endpoint URL**. Debe terminar en `/scim/v2`.
3. Haz clic en **Generate token**.
4. Asigna un nombre al token (por ejemplo, `Okta`).
5. Copia el token generado. Tuist muestra el token solo una vez.

### Paso 2: Añadir la aplicación SCIM de Okta {#okta-step-2}

1. En tu panel de administración de Okta, ve a **Applications > Applications > Browse App Catalog**.
2. Busca y añade **SCIM 2.0 Test App (Header Auth)**.
3. Asígnale un nombre reconocible, como `Tuist SCIM`.
4. Completa la configuración de inicio de sesión para la aplicación de prueba SCIM. Tuist no usa esta aplicación para iniciar sesión; el inicio de sesión lo gestiona la aplicación OIDC de la guía de SSO.

### Paso 3: Configurar la integración de API {#okta-step-3}

1. Abre la pestaña **Provisioning** de la aplicación SCIM.
2. En **Settings > Integration**, haz clic en **Configure API Integration** o **Edit**.
3. Marca **Enable API integration**.
4. Pega la **SCIM endpoint URL** de Tuist en el campo **Base URL** de Okta.
5. Pega el token SCIM de Tuist en **API Token** con el prefijo `Bearer `. Por ejemplo, `Bearer tuist_scim_...`. Okta envía este campo como la cabecera `Authorization`, y Tuist espera un token bearer.
6. Habilita **Import Groups** si quieres que Okta lea los grupos SCIM de Tuist.
7. Haz clic en **Test API Credentials**. Okta debería informar de que la integración se verificó correctamente.
8. Haz clic en **Save**.

### Paso 4: Habilitar acciones de aprovisionamiento {#okta-step-4}

1. En la pestaña **Provisioning** de la aplicación SCIM, abre **Settings > To App**.
2. Haz clic en **Edit**.
3. Habilita:
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. Haz clic en **Save**.

### Paso 5: Asignar usuarios o grupos {#okta-step-5}

1. Abre la pestaña **Assignments** de la aplicación SCIM.
2. Asigna los usuarios o grupos que deben aprovisionarse en Tuist.
3. Asigna los mismos usuarios o grupos a la aplicación OIDC de Okta si también deben poder iniciar sesión con SSO.
4. Consulta la pestaña **Members** de Tuist para verificar que los usuarios asignados aparezcan en la organización.

Para probar el desaprovisionamiento, anula la asignación o desactiva un usuario en Okta y verifica que desaparezca de la pestaña **Members** de la organización de Tuist.

### Asignación de roles {#okta-assigning-roles}

Tuist tiene tres <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>: `admin`, `user` y `viewer`. Tuist expone un grupo SCIM por rol: `Tuist Admins`, `Tuist Users` y `Tuist Viewers`. Asocia los grupos de Okta a ellos mediante **Group Push**:

1. Elige o crea un grupo de Okta para cada rol que quieras asignar y asigna esos grupos en la pestaña **Assignments** de la aplicación SCIM.
2. Asegúrate de que **Import Groups** esté habilitado en la integración de API, luego abre la pestaña **Import** de la aplicación SCIM y haz clic en **Import Now** para que Okta conozca los grupos de Tuist.
3. Abre la pestaña **Push Groups** de la aplicación SCIM y haz clic en **Push Groups > Find groups by name**.
4. Selecciona un grupo de Okta, elige **Link Group** como acción de push y selecciona el grupo de Tuist correspondiente. Tuist no admite la creación de grupos a través de SCIM, así que enlaza a un grupo existente en lugar de crear uno nuevo.
5. Haz clic en **Save** y repite el proceso para los roles restantes.

Añadir un usuario a un grupo enlazado le otorga ese rol. Eliminarlo del grupo lo devuelve al rol con el que la organización registra a los miembros de inicio de sesión único, que es `user` a menos que un administrador lo haya cambiado en **Settings > Authentication**. Los usuarios que no están en ningún grupo enlazado también obtienen ese rol. Eliminar a un usuario de un grupo no lo elimina de la organización; para hacerlo, anula su asignación o desactívalo en Okta.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID aprovisiona Tuist a través de una aplicación empresarial fuera de la galería. Configura primero <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> si los usuarios también deben iniciar sesión con Entra ID.

La aplicación que registras para el inicio de sesión único y la aplicación empresarial que usas para el aprovisionamiento pueden ser la misma. El aprovisionamiento se configura en la entrada de la aplicación empresarial.

### Paso 1: Generar un token SCIM de Tuist {#entra-step-1}

1. En Tuist, navega a la pestaña de configuración **Authentication** de tu organización.
2. En la sección **SCIM provisioning**, copia la **SCIM endpoint URL**. Debe terminar en `/scim/v2`.
3. Haz clic en **Generate token**.
4. Asigna un nombre al token (por ejemplo, `Entra ID`).
5. Copia el token generado. Tuist muestra el token solo una vez.

### Paso 2: Configurar el aprovisionamiento {#entra-step-2}

1. En el centro de administración de Microsoft Entra, ve a **Identity > Applications > Enterprise applications** y abre la aplicación de Tuist.
2. Abre **Provisioning** y establece **Provisioning Mode** en **Automatic**.
3. Establece **Tenant URL** en la SCIM endpoint URL de Tuist.
4. Establece **Secret Token** en el token SCIM de Tuist. Introduce el token solo, sin el prefijo `Bearer `; Entra ID añade el esquema por sí mismo.
5. Haz clic en **Test Connection**. Entra ID debería informar de que las credenciales proporcionadas están autorizadas.
6. Guarda la configuración.

### Paso 3: Establecer el atributo de coincidencia {#entra-step-3}

1. En **Mappings**, abre **Provision Microsoft Entra ID Users**.
2. Confirma que `userPrincipalName` o `mail` se asigne al atributo SCIM `userName`, y que este atributo sea el utilizado para **Matching precedence 1**.
3. Elimina `externalId` de los atributos de coincidencia si está presente.

Tuist coincide con los usuarios aprovisionados por `userName`. No almacena el identificador de objeto de directorio que Entra ID envía como `externalId`, por lo que un filtro sobre ese atributo no encuentra un miembro existente y los ciclos de aprovisionamiento pueden comportarse de manera impredecible.

### Paso 4: Deshabilitar el aprovisionamiento de grupos {#entra-step-4}

En **Mappings**, deshabilita **Provision Microsoft Entra ID Groups**.

Los grupos SCIM de Tuist son un grupo fijo por rol de organización en lugar de grupos de directorio que puedas crear, por lo que un intento de aprovisionar un grupo de directorio falla. Asigna roles como se describe a continuación en su lugar.

### Paso 5: Asignar usuarios e iniciar el aprovisionamiento {#entra-step-5}

1. Abre la pestaña **Users and groups** de la aplicación y asigna los usuarios o grupos que deben aprovisionarse en Tuist.
2. Vuelve a **Provisioning** e inícialo.
3. Consulta la pestaña **Members** de Tuist para verificar que los usuarios asignados aparezcan en la organización.

Entra ID realiza el aprovisionamiento según su propia programación, que suele ser cada 40 minutos, por lo que los miembros no aparecen al instante. Usa **Provision on demand** para probar un único usuario de inmediato.

Para probar la desaprovisión, anula la asignación o deshabilita un usuario en Entra ID y verifica que desaparezca de la pestaña **Members** de la organización de Tuist.

Si más adelante cambias el alcance del aprovisionamiento, por ejemplo de **Sync all users and groups** a **Sync only assigned users and groups**, haz clic en **Restart provisioning** después. Entra ID aplica el nuevo alcance, incluida la desaprovisión de usuarios que ya no están en él, solo después de un reinicio.

### Asignación de roles {#entra-assigning-administrators}

Tuist tiene tres <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>: `admin`, `user` y `viewer`. Para configurarlos desde Entra ID:

1. En **App registrations**, abre la aplicación de Tuist y añade un rol de aplicación por cada rol de Tuist que quieras asignar. Establece **Allowed member types** en **Users/Groups** y **Value** en `admin`, `user` o `viewer`.
2. En la pestaña **Users and groups** de la aplicación empresarial, asigna a cada usuario o grupo uno de esos roles de aplicación. Un usuario puede tener varios roles de aplicación. Tuist aplica el más privilegiado, donde `admin` tiene prioridad sobre `user` y `user` sobre `viewer`, por lo que un usuario que pertenezca a grupos asignados a distintos roles obtiene el de mayor privilegio.
3. En **Provisioning > Mappings**, abre el menú desplegable **Advanced Options** y selecciona **Edit target User attributes**. Añade un atributo llamado `roles` con **Type** establecido en `String` y marca la casilla **Multi-Value**.
4. En **Provisioning > Mappings > Provision Microsoft Entra ID Users**, haz clic en **Add New Mapping**. Establece **Mapping type** en **Expression**, **Expression** en `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])` y **Target attribute** en el atributo `roles` que has añadido.
5. Mantén el alcance del aprovisionamiento configurado en **Sync only assigned users and groups**. `AssertiveAppRoleAssignmentsComplex` no es compatible con **Sync all users and groups**.

`AssertiveAppRoleAssignmentsComplex` envía todos los roles de aplicación que tiene un usuario y también envía eliminaciones, por lo que quitar un rol en Entra ID reduce al usuario al rol más privilegiado que aún conserve. `SingleAppRoleAssignment([appRoleAssignments])` mapeado a `roles[primary eq "True"].value` también funciona, pero solo envía un rol y Entra ID no garantiza cuál elige cuando un usuario tiene varios.

Cambiar los roles de aplicación de un usuario en Entra ID actualiza su rol en Tuist en el siguiente ciclo de aprovisionamiento. Un usuario aprovisionado sin un rol de aplicación, o con valores distintos de `admin`, `user` o `viewer`, obtiene el rol con el que la organización inscribe a los miembros de inicio de sesión único, que es `user` a menos que un administrador lo haya cambiado en **Settings > Authentication**.

## Comportamiento del ciclo de vida {#lifecycle-behavior}

Cuando tu proveedor de identidad asigna un usuario a la aplicación de aprovisionamiento, Tuist crea el usuario si el correo electrónico no es conocido previamente por Tuist y luego lo añade a la organización. Si el correo electrónico ya pertenece a un usuario existente de Tuist fuera de la organización, Tuist rechaza la solicitud para evitar que un IdP reclame un usuario que no gestiona ya en esa organización.

Cuando tu proveedor de identidad anula la asignación o desactiva al usuario, Tuist elimina su rol en la organización mientras conserva el registro del usuario y cualquier trabajo que posea. La desaprovisión no deshabilita al usuario a nivel global, porque el mismo usuario de Tuist puede pertenecer a otras organizaciones.

Tuist expone tres grupos SCIM sintéticos: `Tuist Admins`, `Tuist Users` y `Tuist Viewers`. Añadir un miembro a un grupo establece su rol en la organización. Eliminar a un miembro del grupo que coincide con su rol actual lo devuelve al rol de inscripción, y la pertenencia en sí misma solo finaliza cuando se anula la asignación o se desactiva al usuario. Los proveedores de identidad también pueden establecer el rol mediante el atributo SCIM `roles` en un usuario, con un valor de `admin`, `user` o `viewer`. Un proveedor de identidad que envía varios valores obtiene el más privilegiado de ellos, donde `admin` tiene prioridad sobre `user` y `user` sobre `viewer`.

## Funcionalidades SCIM compatibles {#supported-scim-features}

Tuist admite los puntos finales SCIM 2.0 que necesitan los proveedores de identidad para la gestión del ciclo de vida:

- `POST`, `GET`, `PUT`, `PATCH` y `DELETE` para `/Users`.
- `GET` y `PATCH` para `/Groups`.
- Puntos finales de descubrimiento SCIM para `/ServiceProviderConfig`, `/ResourceTypes` y `/Schemas`.
