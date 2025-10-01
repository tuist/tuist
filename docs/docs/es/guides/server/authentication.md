---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Autenticación {#authentication}

Para interactuar con el servidor, la CLI necesita autenticar las peticiones
usando [bearer
authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/).
La CLI admite la autenticación como usuario o como proyecto.

## Como usuario {#as-a-user}

Cuando utilice la CLI localmente en su máquina, le recomendamos que se
autentique como usuario. Para autenticarse como usuario, debe ejecutar el
siguiente comando:

```bash
tuist auth login
```

El comando le llevará a través de un flujo de autenticación basado en web. Una
vez autenticado, la CLI almacenará un token de actualización de larga duración y
un token de acceso de corta duración en `~/.config/tuist/credentials`. Cada
archivo del directorio representa el dominio con el que te has autenticado, que
por defecto debería ser `tuist.dev.json`. La información almacenada en ese
directorio es sensible, así que **asegúrate de mantenerla a salvo**.

La CLI buscará automáticamente las credenciales cuando realice peticiones al
servidor. Si el token de acceso ha caducado, la CLI utilizará el token de
actualización para obtener un nuevo token de acceso.

## Como proyecto {#as-a-project}

En entornos no interactivos, como las integraciones continuas, no puedes
autenticarte a través de un flujo interactivo. Para esos entornos, recomendamos
autenticarse como proyecto utilizando un token de proyecto:

```bash
tuist project tokens create
```

La CLI espera que el token se defina como la variable de entorno
`TUIST_CONFIG_TOKEN`, y que se establezca la variable de entorno `CI=1`. La CLI
usara el token para autenticar las peticiones.

> [IMPORTANTE] ALCANCE LIMITADO Los permisos del token "project-scoped" se
> limitan a las acciones que consideramos seguras para que los proyectos las
> realicen desde un entorno CI. Tenemos previsto documentar los permisos que
> tiene el token en el futuro.
