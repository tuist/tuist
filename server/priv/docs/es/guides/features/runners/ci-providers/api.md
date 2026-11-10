---
{
  "title": "API",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta trabajos en los runners de Tuist desde tu propia forja de Git u orquestador: crea un trabajo con una sola solicitud a la API y hazle seguimiento mediante webhooks."
}
---
# API {#api}

<!-- @snippet: ./_invite-only -->

Los forges de Git, las colas de merge y los orquestadores de agentes que no tienen su propio protocolo de runner pueden ejecutar jobs directamente en Tuist Runners. Creas un job con una sola solicitud, una máquina de Tuist del <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> que elijas hace checkout del commit y ejecuta tu script, y Tuist informa del resultado a tu endpoint de webhook.

## Ejecutar un job {#run-a-job}

1. **Crea un token de cuenta** con el ámbito `account:runners:write`:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **Crea el job.** Un llamador típico lo hace desde su hook de push, con un token de corta duración que permite a la máquina clonar el repositorio:

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

   La respuesta es el job, con su `workflow_job_id`. Aparece inmediatamente en la sección **Runners** de tu dashboard de Tuist y comienza tan pronto como haya una máquina libre del perfil. Las máquinas calientes suelen iniciarlo en cuestión de segundos.

3. **Sigue el job.** Suscribe un <.localized_link href="/guides/integrations/webhooks">endpoint de webhook</.localized_link> a `runner_job.started` y `runner_job.completed`. El evento de completado incluye la `conclusion` del job: `success`, `failure` o `cancelled`. También puedes hacer polling en `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` y leer el log desde `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`.

## Integrar un forge de git {#integrate-a-git-forge}

Un forge sin protocolo de runner se conecta a través de un pequeño puente, que puede ser un servicio del propio forge o una función que invoca desde sus hooks:

1. **En el push**, el hook de push del forge llega al puente. El puente verifica el hook, decide qué checks necesita el commit y genera un token de clonación de solo lectura para el repositorio que expira tras el timeout del job.
2. **Para cada check**, el puente crea un job con `idempotency_key` establecido en `<repository>:<commit>:<check>`, de modo que un hook reenviado no crea nada nuevo. Almacena el `workflow_job_id` devuelto y puede marcar el check como pendiente en el forge.
3. **En `runner_job.started` y `runner_job.completed`**, el puente verifica la cabecera `Tuist-Signature` con el secreto del endpoint, busca el check por `workflow_job_id` o `idempotency_key` y actualiza el estado del commit en el forge con la `conclusion`. Puede enlazar el estado a la página del job en el dashboard de Tuist.
4. **Cuando un push sustituye a un commit**, el puente cancela los jobs que creó para el commit anterior.

## Cómo se ejecuta el job {#how-the-job-runs}

La máquina obtiene `commit_sha` de `repository_url` mediante HTTPS. Cuando el servidor no sirve un commit por su SHA, obtiene `ref` en su lugar, que debe contener el commit. El `clone_token`, si lo proporcionas, se envía como `Authorization: Bearer <token>` únicamente al host del repositorio. Nunca llega a tu script ni al log del job.

Tu script se ejecuta con Bash en un shell de login, con `set -eo pipefail`, desde la raíz del checkout. El job falla cuando el script termina con un estado distinto de cero o supera `timeout_minutes`, cuyo valor predeterminado es 60 y puede llegar hasta 360. Además de tus `env` y `secrets`, el script ve `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` y `TUIST_JOB_COMMIT_SHA`. Los valores de `secrets` se ocultan en el log del job.

## Reintentos e idempotencia {#idempotency}

Asigna a cada job una `idempotency_key` que indique su propósito, como `<repository>:<commit>:<check>`. Una solicitud con una clave ya usada en tu cuenta devuelve el job existente, con estado 200 en lugar de 201, y no crea nada. Esto permite que tu hook de push envíe la solicitud a una cola de reintentos sin riesgo de jobs duplicados.

Las entregas de webhook se reintentan hasta que tu endpoint responda con un estado 2xx, por lo que un evento puede llegar más de una vez. Usa el `id` del envelope, o el `workflow_job_id` del job junto con el tipo de evento, para deduplicar.

## Cancelar un job {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

Un job que ninguna máquina ha iniciado se cancela inmediatamente. Un job en ejecución se detiene en unos segundos y su evento de completado reporta `cancelled`. Un job que ninguna máquina inicia en 24 horas se cancela automáticamente.

## Caché y confianza {#trust}

Cualquiera que pueda hacer push al repositorio puede cambiar lo que ejecuta un job, por lo que los jobs de API se tratan como no confiables: no obtienen los <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link> compartidos de tu cuenta ni su permiso de firma de caché. Los secretos, el script y el token de clonación de un job se almacenan cifrados y se eliminan una vez finalizado el job.
