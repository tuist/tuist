---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Autenticación {#authentication}

Para interactuar con el servidor, la CLI necesita autenticar las solicitudes mediante [autenticación bearer](https://swagger.io/docs/specification/authentication/bearer-authentication/). La CLI admite la autenticación como usuario, como cuenta o mediante un token OIDC.

## Como usuario {#as-a-user}

Cuando uses la CLI localmente en tu máquina, te recomendamos autenticarte como usuario. Para autenticarte como usuario, debes ejecutar el siguiente comando:

```bash
tuist auth login
```

El comando te guiará a través de un flujo de autenticación web. Una vez que te autentiques, la CLI almacenará un token de actualización de larga duración y un token de acceso de corta duración en `~/.config/tuist/credentials`. Cada archivo del directorio representa el dominio contra el que te has autenticado, que por defecto debería ser `tuist.dev.json`. La información almacenada en ese directorio es sensible, así que **asegúrate de mantenerla segura**.

La CLI buscará automáticamente las credenciales al realizar solicitudes al servidor. Si el token de acceso ha caducado, la CLI utilizará el token de actualización para obtener un nuevo token de acceso.

> [!NOTE]
> Si tu organización utiliza inicio de sesión único, elige la opción de inicio de sesión empresarial en el navegador e introduce tu dirección de correo electrónico corporativo. Tuist puede encontrar el proveedor a partir de tu membresía existente en la organización o de un <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">dominio de correo electrónico de inicio de sesión verificado</.localized_link>.

## Tokens OIDC {#oidc-tokens}

Para entornos de CI que admiten OpenID Connect (OIDC), Tuist puede autenticarse automáticamente sin que tengas que gestionar secretos de larga duración. Cuando se ejecuta en un entorno de CI compatible, la CLI detectará automáticamente el proveedor de tokens OIDC e intercambiará el token proporcionado por la CI por un token de acceso de Tuist.

### Proveedores compatibles {#supported-ci-providers}

Tuist reconoce estos proveedores de CI y asigna sus tokens a los proyectos a través de la conexión de tu repositorio:

- GitHub Actions
- CircleCI
- Bitrise

Cualquier otro proveedor de identidad que emita tokens OpenID Connect puede autenticarse mediante una [política de confianza de identidad de carga de trabajo](#workload-identity-trust-policies) que configures una vez para todos los proyectos actuales y futuros de tu cuenta, por ejemplo [Fly.io Machines](#flyio-machines).

### Configuración de la autenticación OIDC {#setting-up-oidc-authentication}

Para GitHub Actions, CircleCI y Bitrise:

1. **Conecta tu repositorio a Tuist**: Sigue la <.localized_link href="/guides/integrations/gitforge/github">guía de integración de GitHub</.localized_link> para conectar tu repositorio de GitHub a tu proyecto de Tuist.

2. **Ejecuta `tuist auth login`**: En tu flujo de trabajo de CI, ejecuta `tuist auth login` antes de cualquier comando que requiera autenticación. La CLI detectará automáticamente el entorno de CI y se autenticará mediante OIDC.

Consulta la <.localized_link href="/guides/integrations/continuous-integration">guía de Integración Continua</.localized_link> para ver ejemplos de configuración específicos del proveedor.

### Políticas de confianza de identidad de carga de trabajo {#workload-identity-trust-policies}

Una política de confianza permite que las cargas de trabajo de otro proveedor de identidad, como una plataforma de despliegue, un clúster de Kubernetes o un sistema de CI autoadministrado, accedan a un proyecto sin necesidad de un secreto de Tuist de larga duración. El proveedor debe:

- Ser accesible mediante HTTPS en una dirección pública. Tuist no sigue redirecciones y no se conecta a direcciones de red privadas o internas, incluidas las de servidores de Tuist autoalojados.
- Emitir JWT firmados con una clave asimétrica, por ejemplo `RS256` o `ES256`. Los tokens sin firmar y los tokens firmados con un secreto compartido (`HS256` y similares) son rechazados.
- Publicar sus claves de firma como un conjunto de claves web JSON (JWKS) en una URL HTTPS fija. La respuesta debe tener como máximo 64 KiB y contener como máximo 20 claves.
- Incluir una fecha de expiración (`exp`) en cada token.

Los emisores de GitHub Actions, CircleCI y Bitrise están reservados para el flujo basado en repositorio descrito anteriormente y no pueden utilizarse en una política de confianza.

> [!NOTE]
> Para un despliegue autoalojado, aplica las migraciones de base de datos y actualiza cada réplica del servidor de Tuist en servicio antes de configurar identidades de carga de trabajo o mover trabajos a ellas. A continuación, actualiza la CLI o la integración de Elixir a una versión que admita `TUIST_OIDC_TOKEN` y `TUIST_OIDC_ACCOUNT`. Los trabajos existentes de GitHub Actions, CircleCI y Bitrise siguen utilizando la autorización basada en repositorio y no requieren un identificador de cuenta. Antes de cambiar los trabajos de producción, verifica un intercambio de tokens de corta duración y una operación de caché con la carga de trabajo prevista. Para detener nuevos intercambios, elimina la política; permite hasta una hora para que caduquen los tokens de acceso de Tuist ya emitidos. Eliminar una política no revoca inmediatamente esos tokens.

#### Crear una política {#create-a-trust-policy}

En el panel de control de Tuist, abre la sección **Configuración** > **Autenticación** de tu cuenta y busca la sección **Identidades de carga de trabajo**. Debes ser administrador de la cuenta (o el propietario de una cuenta personal). Cada cuenta puede tener hasta 20 políticas. Configura una identidad una vez para el acceso de CI en toda la cuenta; no es necesario seleccionar ningún proyecto.

Utiliza el interruptor junto a **Identidades de carga de trabajo** para abrir el formulario de política. El interruptor se activa cuando la cuenta tiene identidades guardadas y permanece activado después de guardar. Se desactiva para cuentas sin identidades. La sección aparece debajo de **Aprovisionamiento SCIM** para las organizaciones. Ocultar el formulario conserva tu borrador y no deshabilita la autenticación de carga de trabajo: las tarjetas de identidad guardada y el enlace a la documentación de configuración permanecen visibles. Cada tarjeta muestra el nombre de la identidad, las URL del emisor y de JWKS, la audiencia, las reclamaciones JSON exactas, el ámbito de toda la cuenta y la hora de creación. Elimina una identidad mediante la acción en su tarjeta.

Elige **Proveedor personalizado** para introducir los campos siguientes, o **Fly.io Machines** para generarlos a partir del slug de tu organización y de los ID numéricos de organización y aplicación. La plantilla de Fly mantiene el emisor generado, la URL de JWKS y las reclamaciones editables bajo **Configuración avanzada**. Cambiar plantillas o valores auxiliares conserva los campos que hayas editado manualmente. Si tu emisor, URL de JWKS o reclamaciones anulan la plantilla, Tuist expande **Configuración avanzada** y muestra una advertencia para que puedas revisar la política que se guardará. Vuelve a **Proveedor personalizado** para continuar sin los asistentes de Fly. Las plantillas solo rellenan la configuración y no cambian la forma en que Tuist verifica los tokens.

| Campo | Descripción |
| --- | --- |
| Nombre | Una etiqueta para reconocer la política, única dentro de la cuenta. |
| URL del emisor | La reclamación `iss` del token. Debe coincidir exactamente, incluida cualquier barra final. |
| URL de JWKS | La URL HTTPS de las claves de firma del proveedor. Tuist utiliza esta URL directamente y no lee el documento de descubrimiento de OpenID Connect del proveedor, así que copia la `jwks_uri` de la documentación del proveedor o de `<issuer>/.well-known/openid-configuration`. |
| Audiencia | La audiencia para la que debe emitirse el token, `tuist` por defecto. La `aud` del token debe ser igual a ella o, cuando `aud` es una lista, contenerla. Utiliza un valor que solo Tuist acepte para que los tokens emitidos para otros servicios no puedan reutilizarse aquí. |
| Reclamaciones | Un objeto JSON con de 1 a 10 reclamaciones que el token debe contener, por ejemplo `{"sub": "system:serviceaccount:ci:builder"}`. La entrada JSON está limitada a 8 KiB. Los valores deben ser cadenas, enteros con signo de 64 bits o booleanos, y deben coincidir exactamente, incluido su tipo: `"123"` no coincide con `123`. No se permiten objetos anidados, listas ni reclamaciones de tiempo o token como `iss`, `aud`, `exp`, `nbf`, `iat` y `jti`. |

Cada política otorga acceso de CI a **todos los proyectos actuales y futuros propiedad de la cuenta**, sin seleccionar proyectos individuales. Puedes configurar una identidad antes de crear el primer proyecto. Esto no otorga administración de la cuenta ni acceso a otra cuenta.

Cualquier carga de trabajo que pueda obtener un token con reclamaciones coincidentes puede acceder a todos esos proyectos, así que elige reclamaciones que el proveedor garantice y que nadie pueda reutilizar. Prefiere IDs numéricos estables en lugar de nombres que puedan renombrarse o registrarse de nuevo después de su eliminación.

> [!WARNING]
> En un proveedor de identidad compartido, vincula la política a tu organización o inquilino **y** a la aplicación, proyecto o cuenta de servicio prevista. Un nombre de rama como `main`, un entorno como `production` o un rol genérico por sí solo no constituyen un límite de identidad: otro inquilino podría obtener un token con los mismos valores. Por ejemplo, una política de GitLab.com debe incluir el `project_id` estable del proyecto previsto, no solo `ref`. Un token coincidente otorga acceso de CI a toda la cuenta, incluidas las escrituras en caché, por lo que una política que confíe en cargas de trabajo no relacionadas podría permitir el envenenamiento de la caché.

Tuist otorga acceso solo para políticas cuya propia URL de JWKS contiene la clave que firmó el token, tras verificar el emisor, la audiencia, la expiración, la hora de no antes (con hasta 60 segundos de desviación del reloj) y cada reclamación. El token de CI emitido con una hora de validez es para toda la cuenta, no una instantánea de IDs de proyecto: incluye proyectos creados o transferidos a la cuenta después de la emisión. La autorización del proyecto sigue requiriendo la propiedad actual de la cuenta, por lo que transferir un proyecto fuera elimina su acceso bajo el token de esa cuenta.

#### Autenticar una carga de trabajo {#authenticate-a-workload}

1. Solicita un token de identidad a tu proveedor con la audiencia de la política.
2. Establece `TUIST_OIDC_TOKEN` en ese token y `TUIST_OIDC_ACCOUNT` en el identificador de la cuenta de Tuist que posee el proyecto. La cuenta es necesaria para cada intercambio de política de confianza. Solo selecciona dónde buscar y no otorga nada por sí misma.
3. Ejecuta `tuist auth login`. Para proyectos Elixir, puedes usar `mix tuist.login` en su lugar, o permitir que la integración de Elixir intercambie el token automáticamente cuando no haya `TUIST_TOKEN` ni credenciales almacenadas válidas disponibles.

El token de acceso de Tuist resultante tiene solo el grupo de ámbito `ci` y cubre todos los proyectos actuales y futuros propiedad de la cuenta seleccionada. Los intercambios fallan si más de 20 políticas en la cuenta coinciden con el mismo token o si utilizan más de dos URLs de JWKS diferentes.

Tuist no actualiza estas sesiones. Los tokens de acceso caducan después de una hora y no tienen token de actualización. Los tokens de identidad del proveedor suelen ser válidos solo durante unos minutos, por lo que conservar un `TUIST_OIDC_TOKEN` antiguo no es una estrategia de renovación: para trabajos que duran más de una hora, solicita un nuevo token de identidad e inicia sesión de nuevo antes de que expire la sesión de Tuist. Eliminar una política detiene nuevos intercambios, pero los tokens de acceso ya emitidos permanecen válidos hasta que caduquen.

Tuist almacena en caché las claves de firma de un proveedor durante hasta 15 minutos después de una obtención exitosa en una caché dedicada y de tamaño limitado. Las entradas pueden eliminarse antes y volverse a obtener. Las obtenciones fallidas no se almacenan en caché. Si tu proveedor rota las claves, debe publicar la nueva clave en su JWKS al menos 15 minutos antes de firmar tokens con ella, porque los tokens firmados con una clave que no está en el conjunto almacenado en caché se rechazan hasta que la caché caduque. Los tokens sin ID de clave (`kid`) se aceptan solo cuando el JWKS contiene una única clave de firma elegible. Cuando hay un ID de clave presente en el JWKS, debe ser una cadena de como máximo 256 bytes.

> [!NOTE]
> `TUIST_OIDC_TOKEN` es una entrada de token genérica, no una forma de omitir la confianza del servidor. Tiene prioridad sobre la detección del proveedor de CI, y el servidor sigue aceptando solo los proveedores integrados e identidades con una política de confianza coincidente. No pongas un token de identidad en `TUIST_TOKEN`, que espera una credencial de Tuist.

Si el intercambio falla, verifica que el emisor, la audiencia y cada reclamación en la política coincidan exactamente con el token, que la URL de JWKS sirva la clave que firmó el token, que la política no se haya eliminado y que `TUIST_OIDC_ACCOUNT` nombre la cuenta que posee el proyecto. Para evitar exponer qué identidades son de confianza, Tuist devuelve el mismo error para todos estos casos.

### Fly.io Machines {#flyio-machines}

[Fly.io admite la identidad de carga de trabajo OIDC](https://docs.fly.io/reference/openid-connect/). Una Machine puede solicitar un token de identidad firmado de corta duración desde su socket Unix local `/.fly/api`, sin un token de API de Fly ni un secreto de Tuist de larga duración. Los tokens de Fly identifican una organización y una aplicación, no un repositorio de origen, así que usa una política de confianza en lugar de conectar un repositorio de GitHub:

1. Obtén el emisor (`iss`), el ID de organización (`org_id`) y el ID de aplicación (`app_id`) de un token de identidad emitido dentro de tu Fly Machine. El emisor es `https://oidc.fly.io/<organization-slug>`. Usa los IDs numéricos, no los nombres de organización o aplicación.
2. [Crea una política de confianza](#create-a-trust-policy) usando la plantilla **Fly.io Machines** e introduce el slug de la organización y ambos IDs numéricos. Rellena los valores siguientes y mantiene los IDs como cadenas. También puedes introducirlos manualmente usando **Proveedor personalizado**; mantén las comillas alrededor de los IDs en las reclamaciones.

   | Campo | Valor |
   | --- | --- |
   | URL del emisor | `https://oidc.fly.io/<organization-slug>` |
   | URL de JWKS | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audiencia | `tuist` |
   | Reclamaciones | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Dentro de la Machine, establece `TUIST_OIDC_ACCOUNT` en el identificador de la cuenta de Tuist que posee el proyecto (no el slug de la organización de Fly), solicita un token con audiencia `tuist` y pásalo a `tuist auth login` usando `TUIST_OIDC_TOKEN`:

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

Para la configuración inicial, puedes inspeccionar solo los campos de identidad localmente, después de exportar el token y antes de eliminarlo. Esto decodifica las reclamaciones para la configuración; Tuist verifica la firma por separado durante la autenticación:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

No imprimas ni hagas commit del token en sí. Cada Machine en la aplicación de Fly autorizada puede autenticarse en todos los proyectos actuales y futuros de la cuenta de Tuist. Crea una política separada para cada aplicación adicional. Los tokens de identidad de Fly caducan después de unos diez minutos, así que en Machines de larga duración solicita uno nuevo y ejecuta `tuist auth login` de nuevo antes de que caduque la sesión de Tuist de una hora.

### Ámbitos de token OIDC {#oidc-token-scopes}

Los tokens OIDC reciben el grupo de ámbitos `ci`. Para GitHub Actions, CircleCI y Bitrise, esto proporciona acceso a todos los proyectos conectados al repositorio. Para las políticas de confianza de identidad de carga de trabajo, esto proporciona acceso a todos los proyectos actuales y futuros propiedad de la cuenta seleccionada, sin otorgar creación de proyectos, administración de proyectos, administración de runners o administración de miembros de la cuenta. Consulta [Grupos de ámbitos](#scope-groups) para obtener detalles sobre qué incluye el ámbito `ci`.

> [!TIP]
> **Beneficios de seguridad**
>
> La autenticación OIDC es más segura que los tokens de larga duración porque:
> - No hay secretos que rotar o gestionar
> - Los tokens son de corta duración
> - La autenticación está vinculada a la identidad de tu repositorio o a una identidad de carga de trabajo explícitamente autorizada


## Autenticación del plugin de Gradle {#gradle-plugin-authentication}

El plugin de Gradle utiliza el estado de autenticación de la CLI de Tuist y no define un flujo de inicio de sesión separado. Autentícate una vez con la CLI y el plugin reutilizará esas credenciales.

Para la configuración del proyecto y del servidor, incluyendo `project` y `url`, usa la referencia canónica de <.localized_link href="/references/tuist-toml">tuist.toml</.localized_link>.

Para uso local, ejecuta:

```bash
tuist auth login
```

Para CI, usa cualquiera de las siguientes opciones:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">Autenticación OIDC</.localized_link> (recomendado cuando esté disponible)
- <.localized_link href="/guides/server/authentication#continuous-integration">Autenticación con token de cuenta</.localized_link> mediante `TUIST_TOKEN`

Para servidores de Tuist autoalojados, define la URL del servidor en `tuist.toml` (por ejemplo, `url = "https://tuist.your-company.com"`) y ejecuta el flujo de inicio de sesión estándar. La URL se resuelve desde el mismo archivo de configuración utilizado por el plugin.

Después de configurar la autenticación, ejecuta tus comandos y tareas de caché de Gradle normalmente.

## Tokens de cuenta {#account-tokens}

Para entornos de CI que no admiten OIDC, o cuando necesitas un control granular sobre los permisos, puedes usar tokens de cuenta. Los tokens de cuenta te permiten especificar exactamente a qué ámbitos y proyectos puede acceder el token.

### Crear un token de cuenta {#creating-an-account-token}

La forma más fácil de crear un token de cuenta es desde el panel de control:

1. Abre la organización en el panel de control de Tuist.
2. Ve a **Configuración** > **Tokens**.
3. Selecciona **Generar token**.
4. Elige un nombre, una caducidad opcional, el acceso al proyecto y los ámbitos que necesita el token.
5. Copia el valor del token generado antes de cerrar el cuadro de diálogo. Los valores de los tokens solo se muestran una vez.

También puedes crear tokens de cuenta desde la CLI, lo cual es útil para scripts o automatización:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> Reemplaza `account-handle` con el identificador de la cuenta que posee los proyectos a los que quieres que acceda el token. Puede ser una cuenta de organización, no necesariamente tu cuenta personal.

El comando acepta las siguientes opciones:

| Opción | Descripción |
| --- | --- |
| `--scopes` | Obligatorio. Lista separada por comas de ámbitos que se concederán al token. |
| `--name` | Obligatorio. Un identificador único para el token (1-32 caracteres, solo alfanuméricos, guiones y guiones bajos). |
| `--expires` | Opcional. Cuándo debe caducar el token. Usa formatos como `30d` (días), `6m` (meses) o `1y` (años). Si no se especifica, el token nunca caduca. |
| `--projects` | Limita el token a identificadores de proyecto específicos. El token tiene acceso a todos los proyectos si no se especifica. |

### Ámbitos disponibles {#available-scopes}

| Ámbito | Descripción |
| --- | --- |
| `account:cache:read` | Descargar binarios en caché con ámbito de cuenta |
| `account:cache:write` | Subir binarios en caché con ámbito de cuenta |
| `account:members:read` | Leer miembros de la cuenta |
| `account:members:write` | Gestionar miembros de la cuenta |
| `account:registry:read` | Leer desde el registro de paquetes Swift |
| `account:registry:write` | Publicar en el registro de paquetes Swift |
| `account:runners:read` | Leer trabajos, flujos de trabajo, perfiles y volúmenes de runners |
| `account:runners:write` | Gestionar perfiles de runners y limpiar volúmenes de runners |
| `project:previews:read` | Descargar previsualizaciones |
| `project:previews:write` | Subir previsualizaciones |
| `project:admin:read` | Leer proyectos y su configuración |
| `project:admin:write` | Crear, actualizar y eliminar proyectos. Crear un proyecto requiere un token con acceso a todos los proyectos |
| `project:cache:read` | Descargar binarios en caché |
| `project:cache:write` | Subir binarios en caché |
| `project:bundles:read` | Ver bundles |
| `project:bundles:write` | Subir bundles |
| `project:tests:read` | Leer resultados de tests |
| `project:tests:write` | Subir resultados de tests |
| `project:builds:read` | Leer analíticas de compilación |
| `project:builds:write` | Subir analíticas de compilación |
| `project:runs:read` | Leer ejecuciones de comandos |
| `project:runs:write` | Crear y actualizar ejecuciones de comandos |

### Grupos de ámbitos {#scope-groups}

Los grupos de ámbitos ofrecen una forma conveniente de conceder múltiples ámbitos relacionados con un único identificador. Cuando usas un grupo de ámbitos, este se expande automáticamente para incluir todos los ámbitos individuales que contiene.

| Grupo de ámbitos | Ámbitos incluidos |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Integración Continua {#continuous-integration}

Para entornos de CI que no admiten OIDC, crea un token de cuenta con el grupo de ámbitos `ci` para autenticar tus flujos de trabajo de CI. En el panel de control, selecciona la opción predeterminada **CI** al generar el token.

También puedes crear el mismo token desde la CLI:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

Esto crea un token con todos los ámbitos necesarios para las operaciones típicas de CI (caché, previsualizaciones, bundles, tests, compilaciones y ejecuciones). Almacena el token generado como un secreto en tu entorno de CI y configúralo como la variable de entorno `TUIST_TOKEN`.

### Gestionar tokens de cuenta {#managing-account-tokens}

Abre **Configuración** > **Tokens** en el panel de control de la cuenta para ver los tokens de cuenta, inspeccionar los ámbitos y el acceso a proyectos de un token, y revocar tokens durante la rotación.

Para listar todos los tokens de una cuenta:

```bash
tuist account tokens list account-handle
```

Para revocar un token por nombre:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Usar tokens de cuenta {#using-account-tokens}

Se espera que los tokens de cuenta se definan como la variable de entorno `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **Cuándo usar tokens de cuenta**
>
> Usa tokens de cuenta cuando necesites:
> - Autenticación en entornos de CI que no admiten OIDC
> - Control granular sobre qué operaciones puede realizar el token
> - Un token que pueda acceder a múltiples proyectos dentro de una cuenta
> - Tokens con límite de tiempo que caducan automáticamente
