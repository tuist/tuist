---
{
  "title": "Autenticación",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Aprende a autenticarte con el servidor de Tuist desde la CLI."
}
---
# Autenticación {#authentication}

Para interactuar con el servidor, la CLI necesita autenticar las solicitudes mediante [autenticación bearer](https://swagger.io/docs/specification/authentication/bearer-authentication/). La CLI admite autenticarse como usuario, como cuenta o mediante un token OIDC.

## Como usuario {#as-a-user}

Cuando uses la CLI de forma local en tu máquina, te recomendamos autenticarte como usuario. Para autenticarte como usuario, debes ejecutar el siguiente comando:

```bash
tuist auth login
```

El comando te guiará por un flujo de autenticación web. Una vez que te autentiques, la CLI almacenará un token de actualización de larga duración y un token de acceso de corta duración en `~/.config/tuist/credentials`. Cada archivo del directorio representa el dominio frente al que te has autenticado, que por defecto debería ser `tuist.dev.json`. La información almacenada en ese directorio es sensible, así que **asegúrate de mantenerla segura**.

La CLI buscará automáticamente las credenciales al realizar solicitudes al servidor. Si el token de acceso ha caducado, la CLI usará el token de actualización para obtener uno nuevo.

> [!NOTE]
> Si tu organización utiliza inicio de sesión único, elige la opción de inicio de sesión empresarial en el navegador e introduce tu correo electrónico corporativo. Tuist puede encontrar el proveedor a partir de tu membresía existente en la organización o de un <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">dominio de correo electrónico de inicio de sesión verificado</.localized_link>.

## Tokens OIDC {#oidc-tokens}

Para entornos de CI que admiten OpenID Connect (OIDC), Tuist puede autenticarse automáticamente sin que tengas que gestionar secretos de larga duración. Cuando se ejecuta en un entorno de CI compatible, la CLI detecta automáticamente el proveedor de tokens OIDC y cambia el token proporcionado por la CI por un token de acceso de Tuist.

### Proveedores compatibles {#supported-ci-providers}

Tuist reconoce estos proveedores de CI y asigna sus tokens a proyectos a través de la conexión de tu repositorio:

- GitHub Actions
- CircleCI
- Bitrise

Los orbs de [Amp](#amp-orbs) se autentican mediante espacios de trabajo de Amp que conectas a tu cuenta de Tuist, y las [sesiones de Claude Code](#claude-code-sessions) mediante los entornos de Claude Code que conectas para ejecutarlos en Tuist Sandboxes.

Cualquier otro proveedor de identidad que emita tokens OpenID Connect puede autenticarse mediante una [política de confianza de identidad de carga de trabajo](#workload-identity-trust-policies) que configuras una vez para todos los proyectos actuales y futuros de tu cuenta, por ejemplo [Fly.io Machines](#flyio-machines).

### Configurar la autenticación OIDC {#setting-up-oidc-authentication}

Para GitHub Actions, CircleCI y Bitrise:

1. **Conecta tu repositorio a Tuist**: sigue la <.localized_link href="/guides/integrations/gitforge/github">guía de integración con GitHub</.localized_link> para conectar tu repositorio de GitHub a tu proyecto de Tuist.

2. **Otorga el token de identidad**: en GitHub Actions, concede al job `permissions: id-token: write`; en CircleCI y Bitrise, habilita OIDC para el proyecto. A partir de Tuist 4.218.0, cuando la CLI no ha iniciado sesión y no se establece `TUIST_TOKEN`, detecta el entorno de CI y cambia el token de identidad en su primera solicitud, por lo que no hace falta iniciar sesión. Las versiones anteriores necesitan `tuist auth login` primero, y aún puedes ejecutarlo para iniciar sesión explícitamente y fallar pronto si el intercambio es rechazado.

Consulta la <.localized_link href="/guides/integrations/continuous-integration">guía de Integración Continua</.localized_link> para ver ejemplos de configuración específicos de cada proveedor.

### Orbs de Amp {#amp-orbs}

Los orbs de [Amp](https://ampcode.com) pueden emitir tokens OIDC que identifican su espacio de trabajo de Amp. Conecta un espacio de trabajo a tu cuenta de Tuist una vez y la CLI de Tuist y las tareas Mix de `tuist_ex` en cualquier orb de ese espacio de trabajo inician sesión por sí mismas, sin necesidad de un token almacenado ni de un paso de inicio de sesión:

1. Encuentra los IDs: en un hilo del espacio de trabajo que se ejecute en un orb, ejecuta `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`.
2. En tu cuenta de Tuist, abre **Settings → Integrations**, selecciona **Connect workspace** en la tarjeta de Amp y pega el ID del espacio de trabajo. Para admitir solo los orbs de un proyecto de Amp, pega también su ID de proyecto. Debes ser administrador o propietario de la cuenta.
3. Usa Tuist en los orbs del espacio de trabajo. Cuando no haya iniciado sesión, la CLI o la tarea Mix detecta el orb, emite un token con `amp orb id-token --audience https://tuist.dev` y lo cambia por una sesión de Tuist. `tuist auth login` y `mix tuist.login` realizan el mismo intercambio de forma explícita.

Al igual que las configuraciones de confianza de la [guía de OIDC de Amp](https://ampcode.com/manual/orbs/oidc), Tuist verifica la firma de Amp en cada token y lo acepta solo cuando su audiencia es `https://tuist.dev`, su `token_use` es `exchanged`, su `workspace_id` coincide con un espacio de trabajo conectado y, para una conexión limitada a un proyecto, su `project_id` coincide con ese proyecto. Su `sub` debe nombrar el mismo espacio de trabajo y, para una conexión de proyecto, el mismo proyecto, que esas claims: `workspace:<workspace-id>:project:<project-id>:…`, que `amp orb id-token` emite por defecto.

Cada orb admitido por una conexión obtiene acceso de CI a todos los proyectos actuales y futuros propiedad de la cuenta, incluidas las subidas a la caché. También obtiene el ámbito `account:sandboxes:write`, por lo que puede crear <.localized_link href="/guides/features/sandboxes">sandboxes</.localized_link> y ejecutar comandos en ellos como miembro de la cuenta, por ejemplo para compilar en un sandbox de macOS desde un orb de Linux. Conecta solo espacios de trabajo cuyos miembros tengan tu confianza para ese acceso. Revisa el ID con cuidado: Tuist no puede confirmar que pertenezcas al espacio de trabajo que conectas. Si un espacio de trabajo está conectado a varias cuentas de Tuist, los orbs deben establecer `TUIST_OIDC_ACCOUNT` con la cuenta en la que iniciar sesión; establecerlo en el entorno del proyecto de Amp también mantiene el inicio de sesión vinculado a tu cuenta. Los hilos fuera de un espacio de trabajo no tienen identidad de espacio de trabajo y no pueden usar una conexión. Desconecta un espacio de trabajo desde la tarjeta de Amp para detener nuevos inicios de sesión; las sesiones ya emitidas siguen siendo válidas hasta que caduquen tras una hora. Las sesiones no necesitan un token de actualización: cuando una está a punto de caducar, la CLI en el orb emite un nuevo token de Amp y lo vuelve a cambiar, de modo que los orbs de larga duración permanecen iniciados mientras el espacio de trabajo esté conectado.

Las políticas de confianza para el emisor de Amp que creaste antes de conectar un espacio de trabajo siguen funcionando cuando estableces `TUIST_OIDC_ACCOUNT`.

### Sesiones de Claude Code {#claude-code-sessions}

Cada sesión en la nube de Claude Code en un entorno autoalojado lleva un token de identidad firmado por Anthropic (`CLAUDE_CODE_SESSION_ACCESS_TOKEN`). En los entornos que <.localized_link href="/guides/features/sandboxes/claude#claude-code">conectas para ejecutar en Tuist Sandboxes</.localized_link>, Tuist lo pasa a la sesión como `TUIST_OIDC_TOKEN`, de modo que la CLI de Tuist y las tareas Mix de `tuist_ex` inician sesión por sí mismas.

Tuist verifica la firma de Anthropic y acepta el token solo cuando es un token de sesión (`ccr:role` es `session_worker`) cuyo entorno, nombrado en su audiencia, está conectado a una cuenta de Tuist y habilitado. Cada sesión de un entorno conectado obtiene acceso de CI a todos los proyectos actuales y futuros propiedad de la cuenta, incluidas las subidas a la caché, por lo que cualquier persona a la que tu organización de Claude permita usar el entorno puede publicar en tu caché. Las sesiones de Tuist de una sesión caducan tras una hora o con su token de identidad, lo que ocurra primero; el token es el que tenía la sesión al iniciar y dura cuatro horas por defecto, por lo que una sesión más larga pierde el acceso a Tuist hasta que su siguiente mensaje lo reanude en un nuevo runner. Desconecta o deshabilita el entorno para detener nuevos inicios de sesión.

### Políticas de confianza de identidad de carga de trabajo {#workload-identity-trust-policies}

Una política de confianza permite que cargas de trabajo de otro proveedor de identidad, como una plataforma de despliegue, un clúster de Kubernetes o un sistema de CI autogestionado, accedan a un proyecto sin un secreto de Tuist de larga duración. El proveedor debe:

- Ser accesible mediante HTTPS en una dirección pública. Tuist no sigue redirecciones y no se conecta a direcciones de red privadas o internas, incluidas las de servidores de Tuist autoalojados.
- Emitir JWTs firmados con una clave asimétrica, por ejemplo `RS256` o `ES256`. Los tokens sin firmar y los tokens firmados con un secreto compartido (`HS256` y similares) son rechazados.
- Publicar sus claves de firma como un conjunto de claves web JSON (JWKS) en una URL HTTPS fija. La respuesta debe tener como máximo 64 KiB y contener como máximo 20 claves.
- Incluir una expiración (`exp`) en cada token.

Los emisores de GitHub Actions, CircleCI y Bitrise están reservados para el flujo basado en repositorio anterior y no pueden usarse en una política de confianza.

> [!NOTE]
> Para un despliegue autoalojado, aplica las migraciones de base de datos y actualiza cada réplica del servidor de Tuist en servicio antes de configurar identidades de carga de trabajo o mover trabajos a ellas. Luego actualiza la CLI o la integración de Elixir a una versión que soporte `TUIST_OIDC_TOKEN` y `TUIST_OIDC_ACCOUNT`. Los trabajos existentes de GitHub Actions, CircleCI y Bitrise siguen usando la autorización basada en repositorio y no requieren un identificador de cuenta. Antes de cambiar los trabajos de producción, verifica un intercambio de token de corta duración y una operación de caché con la carga de trabajo prevista. Para detener nuevos intercambios, elimina la política; permite hasta una hora para que caduquen los tokens de acceso de Tuist ya emitidos. Eliminar una política no revoca inmediatamente esos tokens.

#### Crear una política {#create-a-trust-policy}

En el panel de Tuist, abre **Configuración** > **Autenticación** de tu cuenta y busca la sección **Identidades de carga de trabajo**. Debes ser administrador de la cuenta (o propietario de una cuenta personal). Cada cuenta puede tener hasta 20 políticas. Configura una identidad una vez para el acceso de CI en toda la cuenta; no se requiere seleccionar proyectos.

Usa el interruptor junto a **Identidades de carga de trabajo** para abrir el formulario de política. El interruptor se activa cuando la cuenta tiene identidades guardadas y permanece activado después de guardar. Se inicia desactivado para cuentas sin identidades. La sección aparece debajo de **Aprovisionamiento SCIM** para organizaciones. Ocultar el formulario conserva tu borrador y no deshabilita la autenticación de carga de trabajo: las tarjetas de identidad guardada y el enlace a la documentación de configuración permanecen visibles. Cada tarjeta muestra el nombre de la identidad, las URLs del emisor y JWKS, la audiencia, las reclamaciones JSON exactas, el ámbito de toda la cuenta y la hora de creación. Elimina una identidad usando la acción en su tarjeta.

Elige **Proveedor personalizado** para introducir los campos siguientes, o **Máquinas de Fly.io** para generarlos a partir del slug de tu organización y los IDs numéricos de organización y aplicación. La plantilla de Fly mantiene el emisor generado, la URL de JWKS y las reclamaciones editables bajo **Configuración avanzada**. Cambiar plantillas o valores auxiliares conserva los campos que hayas editado manualmente. Si tu emisor, URL de JWKS o reclamaciones anulan la plantilla, Tuist expande **Configuración avanzada** y muestra una advertencia para que revises la política que se guardará. Vuelve a **Proveedor personalizado** para continuar sin los asistentes de Fly. Las plantillas solo rellenan la configuración y no cambian cómo Tuist verifica los tokens.

| Campo | Descripción |
| --- | --- |
| Nombre | Una etiqueta para reconocer la política, única dentro de la cuenta. |
| URL del emisor | La reclamación `iss` del token. Debe coincidir exactamente, incluida cualquier barra final. |
| URL de JWKS | La URL HTTPS de las claves de firma del proveedor. Tuist usa esta URL directamente y no lee el documento de descubrimiento de OpenID Connect del proveedor, así que copia `jwks_uri` de la documentación del proveedor o de `<issuer>/.well-known/openid-configuration`. |
| Audiencia | La audiencia para la que debe emitirse el token, `tuist` por defecto. La `aud` del token debe ser igual a ella o, cuando `aud` es una lista, contenerla. Usa un valor que solo Tuist acepte para que los tokens emitidos para otros servicios no puedan reutilizarse aquí. |
| Reclamaciones | Un objeto JSON con de 1 a 10 reclamaciones que el token debe contener, por ejemplo `{"sub": "system:serviceaccount:ci:builder"}`. La entrada JSON está limitada a 8 KiB. Los valores deben ser cadenas, enteros con signo de 64 bits o booleanos, y deben coincidir exactamente, incluido su tipo: `"123"` no coincide con `123`. No se permiten objetos anidados, listas ni reclamaciones de tiempo o token como `iss`, `aud`, `exp`, `nbf`, `iat` y `jti`. |

Cada política otorga acceso de CI a **todos los proyectos actuales y futuros propiedad de la cuenta**, sin seleccionar proyectos individuales. Puedes configurar una identidad antes de crear el primer proyecto. Esto no otorga administración de la cuenta ni acceso a otra cuenta.

Cualquier carga de trabajo que pueda obtener un token con reclamaciones coincidentes puede acceder a todos esos proyectos, así que elige reclamaciones que el proveedor garantice y que nadie pueda reutilizar. Prefiere IDs numéricos estables frente a nombres que puedan renombrarse o registrarse de nuevo tras su eliminación.

> [!WARNING]
> En un proveedor de identidad compartido, vincula la política a tu organización o inquilino **y** a la aplicación, proyecto o cuenta de servicio previstos. Un nombre de rama como `main`, un entorno como `production` o un rol genérico por sí solos no constituyen un límite de identidad: otro inquilino puede obtener un token con los mismos valores. Por ejemplo, una política de GitLab.com debe incluir el `project_id` estable del proyecto previsto, no solo `ref`. Un token coincidente otorga acceso de CI en toda la cuenta, incluidas las escrituras en caché, por lo que una política que confíe en cargas de trabajo no relacionadas podría permitir el envenenamiento de la caché.

Tuist otorga acceso solo para políticas cuya propia URL de JWKS contenga la clave que firmó el token, tras verificar el emisor, la audiencia, la expiración, la hora de no antes (con hasta 60 segundos de desviación de reloj) y cada reclamación. El token de CI emitido, válido durante una hora, tiene alcance en toda la cuenta, no es una instantánea de IDs de proyectos: incluye proyectos creados o transferidos a la cuenta después de su emisión. La autorización del proyecto sigue requiriendo la propiedad actual de la cuenta, por lo que transferir un proyecto fuera elimina su acceso bajo el token de esa cuenta.

#### Autenticar una carga de trabajo {#authenticate-a-workload}

1. Solicita un token de identidad a tu proveedor con la audiencia de la política.
2. Establece `TUIST_OIDC_TOKEN` en ese token y `TUIST_OIDC_ACCOUNT` en el identificador de la cuenta de Tuist que posee el proyecto. La cuenta es necesaria para cada intercambio de política de confianza. Solo selecciona dónde buscar y no otorga nada por sí misma.
3. Ejecuta Tuist. Cuando no hay `TUIST_TOKEN` ni credenciales almacenadas válidas disponibles, la CLI y la integración de Elixir intercambian el token automáticamente. `tuist auth login` y `mix tuist.login` realizan el mismo intercambio explícitamente.

El token de acceso de Tuist resultante tiene solo el grupo de ámbitos `ci` y cubre todos los proyectos actuales y futuros propiedad de la cuenta seleccionada. Los intercambios fallan si más de 20 políticas en la cuenta coinciden con el mismo token o si usan más de dos URLs de JWKS diferentes.

Tuist no actualiza estas sesiones. Los tokens de acceso caducan después de una hora y no tienen token de actualización. Los tokens de identidad del proveedor suelen ser válidos solo durante unos minutos, por lo que mantener un `TUIST_OIDC_TOKEN` antiguo no es una estrategia de renovación: para trabajos que duran más de una hora, solicita un nuevo token de identidad e inicia sesión de nuevo antes de que expire la sesión de Tuist. Eliminar una política detiene nuevos intercambios, pero los tokens de acceso ya emitidos siguen siendo válidos hasta que caduquen.

Tuist almacena en caché las claves de firma de un proveedor durante hasta 15 minutos después de una recuperación exitosa en una caché dedicada y de tamaño limitado. Las entradas pueden ser expulsadas antes y recuperarse de nuevo. Las recuperaciones fallidas no se almacenan en caché. Si tu proveedor rota las claves, debe publicar la nueva clave en su JWKS al menos 15 minutos antes de firmar tokens con ella, porque los tokens firmados con una clave que no está en el conjunto almacenado en caché son rechazados hasta que la caché caduque. Los tokens sin ID de clave (`kid`) se aceptan solo cuando el JWKS contiene una única clave de firma elegible. Cuando hay un ID de clave presente en el JWKS, debe ser una cadena de como máximo 256 bytes.

> [!NOTE]
> `TUIST_OIDC_TOKEN` es una entrada de token genérica, no una forma de eludir la confianza del servidor. Tiene prioridad sobre la detección del proveedor de CI, y el servidor sigue aceptando solo los proveedores integrados e identidades con una política de confianza coincidente. No pongas un token de identidad en `TUIST_TOKEN`, que espera una credencial de Tuist.

Si el intercambio falla, verifica que el emisor, la audiencia y cada reclamación en la política coincidan exactamente con el token, que la URL de JWKS sirva la clave que firmó el token, que la política no haya sido eliminada y que `TUIST_OIDC_ACCOUNT` nombre la cuenta que posee el proyecto. Para evitar exponer qué identidades son de confianza, Tuist devuelve el mismo error para todos estos casos.

### Máquinas de Fly.io {#flyio-machines}

[Fly.io admite la identidad de carga de trabajo OIDC](https://docs.fly.io/reference/openid-connect/). Una máquina puede solicitar un token de identidad firmado de corta duración desde su socket Unix local `/.fly/api`, sin un token de API de Fly ni un secreto de Tuist de larga duración. Los tokens de Fly identifican una organización y una aplicación, no un repositorio de código fuente, así que usa una política de confianza en lugar de conectar un repositorio de GitHub:

1. Obtén el emisor (`iss`), el ID de organización (`org_id`) y el ID de aplicación (`app_id`) de un token de identidad emitido dentro de tu máquina de Fly. El emisor es `https://oidc.fly.io/<organization-slug>`. Usa los IDs numéricos, no los nombres de organización o aplicación.
2. [Crea una política de confianza](#create-a-trust-policy) usando la plantilla **Máquinas de Fly.io** e introduce el slug de la organización y ambos IDs numéricos. Rellena los valores siguientes y mantiene los IDs como cadenas. También puedes introducirlos manualmente usando **Proveedor personalizado**; mantén las comillas alrededor de los IDs en las reclamaciones.

   | Campo | Valor |
   | --- | --- |
   | URL del emisor | `https://oidc.fly.io/<organization-slug>` |
   | URL de JWKS | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audiencia | `tuist` |
   | Reclamaciones | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Dentro de la máquina, establece `TUIST_OIDC_ACCOUNT` en el identificador de la cuenta de Tuist que posee el proyecto (no el slug de la organización de Fly), solicita un token con audiencia `tuist` y pásalo a `tuist auth login` usando `TUIST_OIDC_TOKEN`:

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

Para la configuración inicial, puedes inspeccionar solo los campos de identidad localmente, después de exportar el token y antes de desestablecerlo. Esto decodifica las reclamaciones para la configuración; Tuist verifica la firma por separado durante la autenticación:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

No imprimas ni hagas commit del token en sí. Cada máquina en la aplicación de Fly autorizada puede autenticarse en todos los proyectos actuales y futuros de la cuenta de Tuist. Crea una política separada para cada aplicación adicional. Los tokens de identidad de Fly caducan después de unos diez minutos, así que en máquinas de larga ejecución solicita uno nuevo y ejecuta `tuist auth login` de nuevo antes de que expire la sesión de Tuist de una hora.

### Ámbitos de token OIDC {#oidc-token-scopes}

Los tokens OIDC reciben el grupo de ámbitos `ci`. Para GitHub Actions, CircleCI y Bitrise, esto proporciona acceso a todos los proyectos conectados al repositorio. Para espacios de trabajo de Amp conectados, entornos de Claude Code conectados y políticas de confianza de identidad de carga de trabajo, esto proporciona acceso a todos los proyectos actuales y futuros propiedad de la cuenta seleccionada, sin otorgar creación de proyectos, administración de proyectos, administración de runners o administración de miembros de la cuenta. Consulta [Grupos de ámbitos](#scope-groups) para obtener detalles sobre qué incluye el ámbito `ci`.

> [!TIP]
> **Beneficios de seguridad**
>
> La autenticación OIDC es más segura que los tokens de larga duración porque:
> - No hay secretos que rotar o gestionar
> - Los tokens son de corta duración
> - La autenticación está vinculada a la identidad de tu repositorio o a una identidad de carga de trabajo explícitamente autorizada


## Autenticación del plugin de Gradle {#gradle-plugin-authentication}

El plugin de Gradle utiliza el estado de autenticación de la CLI de Tuist y no define un flujo de inicio de sesión separado. Autentícate una vez con la CLI y el plugin reutilizará esas credenciales.

Para la configuración del proyecto y del servidor, incluidos `project` y `url`, consulta la referencia canónica de <.localized_link href="/references/tuist-toml">tuist.toml</.localized_link>.

Para uso local, ejecuta:

```bash
tuist auth login
```

Para CI, usa cualquiera de las siguientes opciones:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">Autenticación OIDC</.localized_link> (recomendada cuando esté disponible)
- <.localized_link href="/guides/server/authentication#continuous-integration">Autenticación mediante token de cuenta</.localized_link> a través de `TUIST_TOKEN`

Para servidores de Tuist autoalojados, define la URL del servidor en `tuist.toml` (por ejemplo, `url = "https://tuist.your-company.com"`) y ejecuta el flujo estándar de inicio de sesión. La URL se resuelve desde el mismo archivo de configuración que usa el plugin.

Una vez configurada la autenticación, ejecuta tus comandos y tareas de caché de Gradle con normalidad.

## Tokens de cuenta {#account-tokens}

Para entornos de CI que no admiten OIDC, o cuando necesitas un control granular sobre los permisos, puedes usar tokens de cuenta. Los tokens de cuenta te permiten especificar exactamente a qué ámbitos y proyectos puede acceder el token.

### Creación de un token de cuenta {#creating-an-account-token}

La forma más fácil de crear un token de cuenta es desde el panel de control:

1. Abre la organización en el panel de control de Tuist.
2. Ve a **Configuración** > **Tokens**.
3. Selecciona **Generar token**.
4. Elige un nombre, una caducidad opcional, el acceso a proyectos y los ámbitos que necesita el token.
5. Copia el valor del token generado antes de cerrar el diálogo. Los valores de los tokens solo se muestran una vez.

También puedes crear tokens de cuenta desde la CLI, lo cual es útil para scripts o automatización:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> Reemplaza `account-handle` por el identificador de la cuenta que posee los proyectos a los que quieres que acceda el token. Puede ser una cuenta de organización, no necesariamente tu cuenta personal.

El comando acepta las siguientes opciones:

| Opción | Descripción |
| --- | --- |
| `--scopes` | Obligatorio. Lista de ámbitos separados por espacios que se otorgarán al token. |
| `--name` | Obligatorio. Un identificador único para el token (1-32 caracteres, solo alfanuméricos, guiones y guiones bajos). |
| `--expires` | Opcional. Cuándo debe caducar el token. Usa formatos como `30d` (días), `6m` (meses) o `1y` (años). Si no se especifica, el token nunca caduca. |
| `--projects` | Limita el token a identificadores de proyectos específicos. El token tiene acceso a todos los proyectos si no se especifica. |

### Ámbitos disponibles {#available-scopes}

| Ámbito | Descripción |
| --- | --- |
| `account:cache:read` | Descargar binarios en caché con ámbito de cuenta |
| `account:cache:write` | Subir binarios en caché con ámbito de cuenta |
| `account:members:read` | Leer miembros de la cuenta |
| `account:members:write` | Gestionar miembros de la cuenta |
| `account:registry:read` | Leer del registro de paquetes Swift |
| `account:registry:write` | Publicar en el registro de paquetes Swift |
| `account:runners:read` | Leer trabajos, flujos de trabajo, perfiles y volúmenes de runners |
| `account:runners:write` | Gestionar perfiles de runners y eliminar volúmenes de runners |
| `account:sandboxes:write` | Crear sandboxes y ejecutar comandos en ellos, como un miembro de la cuenta |
| `project:previews:read` | Descargar previsualizaciones |
| `project:previews:write` | Subir previsualizaciones |
| `project:admin:read` | Leer proyectos y su configuración |
| `project:admin:write` | Crear, actualizar y eliminar proyectos. Para crear un proyecto se necesita un token con acceso a todos los proyectos |
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

Los grupos de ámbitos ofrecen una forma cómoda de otorgar varios ámbitos relacionados con un único identificador. Cuando usas un grupo de ámbitos, este se expande automáticamente para incluir todos los ámbitos individuales que contiene.

| Grupo de ámbitos | Ámbitos incluidos |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Integración continua {#continuous-integration}

Para entornos de CI que no admiten OIDC, crea un token de cuenta con el grupo de ámbitos `ci` para autenticar tus flujos de trabajo de CI. En el panel de control, selecciona la opción predefinida **CI** al generar el token.

También puedes crear el mismo token desde la CLI:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

Esto crea un token con todos los ámbitos necesarios para las operaciones típicas de CI (caché, previsualizaciones, bundles, tests, compilaciones y ejecuciones). Guarda el token generado como secreto en tu entorno de CI y configúralo como la variable de entorno `TUIST_TOKEN`.

### Gestión de tokens de cuenta {#managing-account-tokens}

Abre **Configuración** > **Tokens** en el panel de control de la cuenta para ver los tokens de cuenta, inspeccionar los ámbitos y el acceso a proyectos de un token, y revocar tokens durante la rotación.

Para listar todos los tokens de una cuenta:

```bash
tuist account tokens list account-handle
```

Para revocar un token por nombre:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Uso de tokens de cuenta {#using-account-tokens}

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
> - Un token que pueda acceder a varios proyectos dentro de una cuenta
> - Tokens con límite de tiempo que caducan automáticamente
