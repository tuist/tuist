---
{
  "title": "API",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta trabajos en los Runners de Tuist desde tu propia forja de Git u orquestador: crea un trabajo con una sola solicitud a la API y hazle seguimiento mediante webhooks."
}
---
# API {#api}

Las forjas de Git, las colas de merge y los orquestadores de agentes que no tienen su propio protocolo de runner pueden ejecutar trabajos directamente en Tuist Runners. Creas un trabajo con una sola solicitud, una máquina de Tuist del <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> que elijas obtiene el commit y ejecuta tu script, y Tuist informa del resultado a tu endpoint de webhook.

## Ejecutar un trabajo {#run-a-job}

1. **Crea un token de cuenta** con el ámbito `account:runners:write`:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **Crea el trabajo.** Un llamador típico hace esto desde su hook de push, con un token de corta duración que permite a la máquina clonar el repositorio:

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   La respuesta es el trabajo, con su `workflow_job_id`. Aparece inmediatamente en la sección **Runners** de tu panel de Tuist y comienza tan pronto como haya una máquina libre del perfil. Las máquinas en caliente suelen iniciarlo en cuestión de segundos.

3. **Sigue el trabajo.** Suscribe un <.localized_link href="/guides/integrations/webhooks">endpoint de webhook</.localized_link> a `runner_job.started` y `runner_job.completed`. El evento de completado incluye la `conclusion` del trabajo: `success`, `failure` o `cancelled`. También puedes sondear `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` y leer el registro desde `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`.

## Integrar una forja de git {#integrate-a-git-forge}

Una forja sin protocolo de runner se conecta a través de un pequeño puente, que puede ser un servicio de la propia forja o una función que esta llama desde sus hooks:

1. **En el push**, el hook de push de la forja llega al puente. El puente verifica el hook, decide qué comprobaciones necesita el commit y genera un token de clonación de solo lectura para el repositorio que caduca tras el tiempo de espera del trabajo.
2. **Para cada comprobación**, el puente crea un trabajo con `idempotency_key` establecido en `<repository>:<commit>:<check>`, de modo que un hook reenviado no crea nada nuevo. Almacena el `workflow_job_id` devuelto y puede marcar la comprobación como pendiente en la forja.
3. **En `runner_job.started` y `runner_job.completed`**, el puente verifica la cabecera `Tuist-Signature` con el secreto del endpoint, busca la comprobación por `workflow_job_id` o `idempotency_key` y actualiza el estado del commit en la forja con la `conclusion`. Puede enlazar el estado a la página del trabajo en el panel de Tuist.
4. **Cuando un push sustituye a un commit**, el puente cancela los trabajos que creó para el commit anterior.

## Cómo se ejecuta el trabajo {#how-the-job-runs}

La máquina obtiene `commit_sha` de `repository_url` mediante HTTPS. Cuando el servidor no sirve un commit por su SHA, obtiene `ref` en su lugar, que debe contener el commit. El `clone_token`, si lo proporcionas, se envía como `Authorization: Bearer <token>` únicamente al host del repositorio. Nunca llega a tu script ni al registro del trabajo.

Tu script se ejecuta con Bash en un shell de login, con `set -eo pipefail`, desde la raíz del checkout. El trabajo falla cuando el script sale con un estado distinto de cero o supera el `timeout_minutes`, cuyo valor predeterminado es 60 y puede llegar hasta 360. Además de tu `env` y `secrets`, el script ve `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` y `TUIST_JOB_COMMIT_SHA`. Los valores de `secrets` se ocultan en el registro del trabajo.

## Reintentos e idempotencia {#idempotency}

Asigna a cada trabajo una `idempotency_key` que indique su propósito, como `<repository>:<commit>:<check>`. Una solicitud con una clave ya utilizada en tu cuenta devuelve el trabajo existente, con estado 200 en lugar de 201, y no crea nada. Esto permite que tu hook de push envíe la solicitud a una cola de reintentos sin riesgo de duplicar trabajos.

Las entregas de webhook se reintentan hasta que tu endpoint responda con un estado 2xx, por lo que un evento puede llegar más de una vez. Usa el `id` del sobre, o el `workflow_job_id` del trabajo junto con el tipo de evento, para eliminar duplicados.

## Cancelar un trabajo {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

Un trabajo que ninguna máquina ha iniciado se cancela inmediatamente. Un trabajo en ejecución se detiene en unos segundos y su evento de completado informa de `cancelled`. Un trabajo que ninguna máquina inicia en 24 horas se cancela automáticamente.

## Caché y confianza {#trust}

Cualquiera que pueda hacer push al repositorio puede cambiar lo que ejecuta un trabajo, por lo que los trabajos de API se tratan como no confiables: no obtienen los <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link> compartidos de tu cuenta ni su permiso de firma de caché. Los secretos, el script y el token de clonación de un trabajo se almacenan cifrados y se eliminan una vez finalizado el trabajo.
