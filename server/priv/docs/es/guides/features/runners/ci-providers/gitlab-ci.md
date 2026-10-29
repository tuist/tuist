---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run GitLab CI jobs on Tuist Runners with machine selection through pipeline tags."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **Solo por invitación**
>
> Tuist Runners está actualmente disponible solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) para solicitar acceso para tu cuenta.

Tus pipelines permanecen en GitLab. Tuist proporciona una máquina Linux o macOS aislada para cada job e informa sus registros y resultados a GitLab y al panel de control de Tuist. Se requiere GitLab 19.3 o superior. Se admiten GitLab.com e instancias autoalojadas accesibles a través de HTTPS público.

1. **Crea un runner de GitLab.** En la sección **Settings → CI/CD → Runners** de tu proyecto, crea un runner de proyecto. También puedes usar un runner de grupo. Añade todas las etiquetas de perfil de Tuist que quieras utilizar como etiquetas del runner, por ejemplo `tuist-linux` y `tuist-macos`, y desactiva **Run untagged jobs**. Conserva el token de autenticación que muestra GitLab, que comienza con `glrt-`. No necesitas instalar un runner en tu propia máquina.
2. **Conecta una vez en Tuist.** En **Settings → Integrations**, selecciona **Connect** en la tarjeta de GitLab CI. Introduce tu URL de GitLab y el token de autenticación del runner. La conexión puede atender jobs que utilizan diferentes perfiles. Los tokens se almacenan cifrados y nunca se vuelven a mostrar. Opcionalmente, añade un token de acceso a la API para que los pipelines de merge request puedan guardar volúmenes de caché; consulta [Merge request pipelines](#merge-request-pipelines).
3. **Elige la máquina en cada job.** Establece exactamente una <.localized_link href="/guides/features/runners/profiles">etiqueta de perfil de Tuist</.localized_link> en las `tags` del job. Se permiten otras etiquetas, siempre que el runner de GitLab registrado también las tenga:

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **Haz push y supervisa.** Tuist comienza a sondear en menos de un minuto. Los jobs aparecen bajo **Runners**, con un enlace de vuelta al job de GitLab, registros y métricas de la máquina. GitLab recibe los registros mientras el job se ejecuta; Tuist recibe el registro enmascarado cuando finaliza.

Tuist lee `CI_JOB_TAGS` de cada asignación y resuelve el perfil dentro de la cuenta de Tuist conectada. No infiere la máquina a partir de `CI_RUNNER_TAGS` ni utiliza un perfil predeterminado. Las etiquetas de perfil de Tuist faltantes, desconocidas o múltiples hacen que el job adquirido falle con una explicación en su registro de GitLab. No anules `CI_JOB_TAGS` en las variables de tu pipeline.

## Entorno de ejecución {#execution-environment}

Los jobs utilizan el **shell executor** de GitLab dentro de una máquina aislada. El checkout, las variables de CI, `before_script`, `script`, `after_script`, los artefactos y la cancelación son gestionados por GitLab Runner. Las configuraciones `image:` y `services:` del pipeline no configuran este entorno de shell; utiliza las herramientas instaladas en la <.localized_link href="/guides/features/runners/profiles">imagen del runner</.localized_link> o instálalas en tu script.

El token de autenticación reutilizable del runner permanece en el servidor de Tuist. Las máquinas reciben credenciales solo para el job que tienen asignado. Las concesiones de firma de caché están actualmente retenidas para los jobs de GitLab. Los volúmenes de caché personalizados de Linux verifican la identidad del job y el permiso de guardado a través de la API de GitLab; las variables de CI anulables no establecen confianza.

GitLab marca un job como en ejecución y comienza su tiempo de espera tan pronto como Tuist lo adquiere. Mientras los jobs que Tuist ya ha adquirido consumen el límite de concurrencia de tu cuenta, los jobs adicionales permanecen pendientes en GitLab. Un job adquirido espera una máquina hasta su tiempo de espera de job, como máximo 12 horas. Si ninguna máquina está disponible para entonces, Tuist hace fallar la asignación con `runner_system_failure`, y la política de reintento anterior permite que GitLab lo reintente. La misma política cubre una máquina runner perdida.

## Rotación de tokens y desconexión {#rotating-tokens-and-disconnecting}

Actualiza los tokens de la conexión y selecciona **Save changes** para rotarlos. Dejar un token en blanco conserva la credencial existente.

**Disconnect** detiene la adquisición y hace fallar las asignaciones en espera. Los jobs en ejecución continúan con sus propias credenciales. Si no se puede acceder a GitLab, Tuist mantiene la conexión deshabilitada mientras reintenta la cancelación de las asignaciones en espera. La conexión se elimina una vez que esas asignaciones se han resuelto.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre jobs con <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilicen.

### Pipelines de merge request {#merge-request-pipelines}

Los pipelines de push, programados y web del proyecto guardan sus cambios en volúmenes de caché. Los pipelines de merge request utilizan la caché y guardan sus cambios solo cuando la conexión tiene un token de acceso a la API:

1. En GitLab, crea un token de acceso de proyecto o grupo con el rol **Reporter** y el ámbito `read_api`. Un token de grupo cubre todos los proyectos del grupo que se ejecutan en runners de Tuist.
2. En **Settings → Integrations**, pégalo en **API access token** en la tarjeta de GitLab CI y selecciona **Save changes**.

Tuist lee entonces el merge request de cada pipeline de merge request. Los pipelines de merge requests abiertos desde una rama del propio proyecto guardan sus cambios bajo la rama de origen del merge request, por lo que la <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">configuración de ramas</.localized_link> del perfil del runner se aplica a esa rama. Los merge requests desde forks nunca guardan. Si Tuist no puede leer el merge request, el job sigue ejecutándose y utilizando la caché, pero sus cambios se descartan.
