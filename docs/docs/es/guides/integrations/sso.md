---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Si tienes una organización de Google Workspace y quieres que cualquier
desarrollador que inicie sesión con el mismo dominio alojado en Google se añada
a tu organización de Tuist, puedes configurarlo con:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: advertencia
<!-- -->
Debes autenticarte con Google mediante una dirección de correo electrónico
vinculada a la organización cuyo dominio estás configurando.
<!-- -->
:::

## Okta {#okta}

SSO con Okta sólo está disponible para clientes empresariales. Si está
interesado en configurarlo, póngase en contacto con nosotros en
[contact@tuist.dev](mailto:contact@tuist.dev).

Durante el proceso, se le asignará un punto de contacto para ayudarle a
configurar el SSO de Okta.

En primer lugar, tendrás que crear una aplicación Okta y configurarla para que
funcione con Tuist:
1. Vaya al panel de administración de Okta
2. Aplicaciones > Aplicaciones > Crear integración de aplicaciones
3. Seleccione "OIDC - OpenID Connect" y "Aplicación Web".
4. Introduce el nombre para mostrar de la aplicación, por ejemplo, "Tuist".
   Cargue un logotipo de Tuist que se encuentra en [esta
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. Por ahora, deje los URI de redirección de inicio de sesión como están
6. En "Asignaciones" elija el control de acceso deseado a la Aplicación SSO y
   guarde.
7. Después de guardar, los ajustes generales de la aplicación estarán
   disponibles. Copia el "ID de cliente" y el "Secreto de cliente": tendrás que
   compartirlos de forma segura con tu punto de contacto.
8. El equipo de Tuist tendrá que volver a desplegar el servidor de Tuist con el
   ID de cliente y el secreto proporcionados. Esto puede tardar hasta un día
   laborable.
9. Una vez desplegado el servidor, haga clic en el botón "Editar" de la
   Configuración General.
10. Pegue la siguiente URL de redirección:
    `https://tuist.dev/users/auth/okta/callback`
13. Cambie "Inicio de sesión iniciado por" a "Okta o aplicación".
14. Seleccione "Mostrar el icono de la aplicación a los usuarios"
15. Actualice la "Initiate login URL" con
    `https://tuist.dev/users/auth/okta?organization_id=1`. El `organization_id`
    será proporcionado por su punto de contacto.
16. Haz clic en "Guardar".
17. Inicia sesión en Tuist desde tu panel de control de Okta.
18. Da acceso automático a tu organización Tuist a los usuarios firmados desde
    tu dominio Okta ejecutando el siguiente comando:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: advertencia
<!-- -->
Los usuarios deben registrarse inicialmente a través de su panel de control
Okta, ya que Tuist actualmente no soporta el aprovisionamiento y
desaprovisionamiento automático de usuarios de tu organización Okta. Una vez que
se registren a través de su panel de Okta, se añadirán automáticamente a tu
organización Tuist.
<!-- -->
:::
