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
La CLI admite la autenticación como usuario, como cuenta o utilizando un token
OIDC.

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

## Tokens OIDC {#oidc-tokens}

En los entornos CI compatibles con OpenID Connect (OIDC), Tuist puede
autenticarse automáticamente sin necesidad de gestionar secretos de larga
duración. Cuando se ejecuta en un entorno de CI compatible, la CLI detectará
automáticamente el proveedor de token de OIDC e intercambiará el token
proporcionado por CI por un token de acceso de Tuist.

### Proveedores de IC compatibles {#supported-ci-providers}

- Acciones de GitHub
- CircleCI
- Bitrise

### Configuración de la autenticación OIDC {#setting-up-oidc-authentication}

1. **Conecta tu repositorio a Tuist**: Sigue la guía de integración
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub</LocalizedLink>
   para conectar tu repositorio GitHub a tu proyecto Tuist.

2. **Ejecute `tuist auth login`**: En su flujo de trabajo CI, ejecute `tuist
   auth login` antes de cualquier comando que requiera autenticación. La CLI
   detectará automáticamente el entorno CI y se autenticará utilizando OIDC.

Consulte la
<LocalizedLink href="/guides/integrations/continuous-integration">Guía de integración continua</LocalizedLink> para ver ejemplos de configuración
específicos de cada proveedor.

### Ámbitos de token OIDC {#oidc-token-scopes}

A los tokens OIDC se les concede el grupo de alcance `ci`, que proporciona
acceso a todos los proyectos conectados al repositorio. Ver [Grupos de
ámbito](#scope-groups) para más detalles sobre lo que incluye el ámbito `ci`.

::: tip PRESTACIONES DE SEGURIDAD
<!-- -->
La autenticación OIDC es más segura que los tokens de larga duración porque:
- No hay secretos que rotar o gestionar
- Los tokens son efímeros y se limitan a flujos de trabajo individuales.
- La autenticación está vinculada a su identidad de repositorio
<!-- -->
:::

## Fichas de cuenta {#fichas-de-cuenta}

Para entornos CI que no soportan OIDC, o cuando se necesita un control preciso
sobre los permisos, se pueden utilizar tokens de cuenta. Los tokens de cuenta le
permiten especificar exactamente a qué ámbitos y proyectos puede acceder el
token.

### Crear un token de cuenta {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

El comando acepta las siguientes opciones:

| Opción        | Descripción                                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--ámbitos`   | Obligatorio. Lista separada por comas de ámbitos para conceder el token.                                                                               |
| `--name`      | Obligatorio. Un identificador único para el token (de 1 a 32 caracteres, sólo alfanuméricos, guiones y guiones bajos).                                 |
| `--expira en` | Opcional. Fecha de caducidad del token. Utilice un formato como `30d` (días), `6m` (meses), o `1y` (años). Si no se especifica, el token nunca caduca. |
| `--proyectos` | Limita el acceso al token a determinados proyectos. Si no se especifica, el token tiene acceso a todos los proyectos.                                  |

### Ámbitos disponibles {#available-scopes}

| Alcance                            | Descripción                                |
| ---------------------------------- | ------------------------------------------ |
| `cuenta:miembros:leer`             | Leer miembros de la cuenta                 |
| `cuenta:miembros:escribir`         | Gestionar los miembros de la cuenta        |
| `cuenta:registro:leer`             | Lectura del registro de paquetes Swift     |
| `cuenta:registro:escribir`         | Publicar en el registro de paquetes Swift  |
| `proyecto:avances:leer`            | Descargar avances                          |
| `proyecto:avances:escribir`        | Cargar previsualizaciones                  |
| `proyecto:admin:leer`              | Leer la configuración del proyecto         |
| `proyecto:admin:escribir`          | Gestionar la configuración del proyecto    |
| `proyecto:caché:leer`              | Descargar binarios en caché                |
| `proyecto:caché:escribir`          | Cargar binarios en caché                   |
| `proyecto:paquetes:leer`           | Ver paquetes                               |
| `proyecto:paquetes:escribir`       | Cargar paquetes                            |
| `proyecto:pruebas:leer`            | Leer los resultados de las pruebas         |
| `proyecto:pruebas:escribir`        | Cargar los resultados de las pruebas       |
| `proyecto:construcciones:leer`     | Leer análisis de construcción              |
| `proyecto:construcciones:escribir` | Cargar análisis de construcción            |
| `proyecto:carreras:leer`           | El comando de lectura se ejecuta           |
| `proyecto:corre:escribe`           | Crear y actualizar ejecuciones de comandos |

### Grupos de alcance {#scope-groups}

Los grupos de ámbitos ofrecen una forma cómoda de conceder varios ámbitos
relacionados con un único identificador. Cuando se utiliza un grupo de ámbitos,
se amplía automáticamente para incluir todos los ámbitos individuales que
contiene.

| Grupo Scope | Visores incluidos                                                                                                                             |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`        | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Integración continua (CI) {#continuous-integration-ci}

Para entornos CI que no admiten OIDC, puede crear un token de cuenta con el
grupo de ámbito `ci` para autenticar sus flujos de trabajo CI:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Esto crea un token con todos los ámbitos necesarios para las operaciones típicas
de CI (caché, vistas previas, paquetes, pruebas, compilaciones y ejecuciones).
Guarde el token generado como un secreto en su entorno CI y establézcalo como la
variable de entorno `TUIST_TOKEN`.

### Gestión de fichas de cuenta {#managing-account-tokens}

Para listar todos los tokens de una cuenta:

```bash
tuist account tokens list my-account
```

Para revocar un token por su nombre:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Uso de fichas de cuenta {#using-account-tokens}

Se espera que los tokens de cuenta se definan como la variable de entorno
`TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: consejo CUÁNDO UTILIZAR LOS TOKENS DE CUENTA
<!-- -->
Utiliza las fichas de cuenta cuando lo necesites:
- Autenticación en entornos CI que no admiten OIDC
- Control detallado de las operaciones que puede realizar el token
- Un token que puede acceder a varios proyectos dentro de una cuenta
- Fichas de duración limitada que caducan automáticamente
<!-- -->
:::
