---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta trabajos de GitLab CI en los Runners de Tuist con selección de máquina mediante etiquetas de pipeline."
}
---
# GitLab CI {#gitlab-ci}

> [!IMPORTANT]
> **Solo por invitación**
>
> Tuist Runners está disponible solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) para solicitar acceso para tu cuenta.

Tus pipelines permanecen en GitLab. Tuist proporciona una máquina Linux o macOS aislada para cada trabajo e informa sus registros y resultados a GitLab y al panel de control de Tuist. Se requiere GitLab 19.3 o superior. Se admiten GitLab.com e instancias autoalojadas accesibles mediante HTTPS público.

1. **Crea un runner de GitLab.** En la sección **Ajustes → CI/CD → Runners** de tu proyecto, crea un runner de proyecto. También puedes usar un runner de grupo. Añade todas las etiquetas de perfil de Tuist que quieras utilizar como etiquetas del runner, por ejemplo `tuist-linux` y `tuist-macos`, y desactiva **Ejecutar trabajos sin etiqueta**. Conserva el token de autenticación que muestra GitLab, que comienza por `glrt-`. No necesitas instalar un runner en tu propia máquina.
2. **Conecta una vez en Tuist.** En **Ajustes → Integraciones**, selecciona **Conectar** en la tarjeta de GitLab CI. Introduce tu URL de GitLab y el token de autenticación del runner. La conexión puede atender trabajos que usen distintos perfiles. Los tokens se almacenan cifrados y no vuelven a mostrarse. Opcionalmente, añade un token de acceso a la API para que los pipelines de solicitudes de fusión puedan guardar volúmenes de caché; consulta [Pipelines de solicitudes de fusión](#merge-request-pipelines).
3. **Elige la máquina en cada trabajo.** Establece exactamente una <.localized_link href="/guides/features/runners/profiles">etiqueta de perfil de Tuist</.localized_link> en las `tags` del trabajo. Se permiten otras etiquetas, siempre que el runner de GitLab registrado también las tenga:

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

4. **Haz push y supervisa.** Tuist comienza a sondear en menos de un minuto. Los trabajos aparecen en **Runners**, con un enlace al trabajo de GitLab, los registros y las métricas de la máquina. GitLab recibe los registros mientras el trabajo se ejecuta; Tuist recibe el registro enmascarado cuando finaliza.

Tuist lee `CI_JOB_TAGS` de cada asignación y resuelve el perfil dentro de la cuenta de Tuist conectada. No infiere la máquina a partir de `CI_RUNNER_TAGS` ni utiliza un perfil predeterminado. Las etiquetas de perfil de Tuist faltantes, desconocidas o múltiples hacen que el trabajo adquirido falle, con una explicación en su registro de GitLab. No sobrescribas `CI_JOB_TAGS` en las variables de tu pipeline.

## Entorno de ejecución {#execution-environment}

Los trabajos utilizan el **ejecutor de shell** de GitLab dentro de una máquina aislada. El checkout, las variables de CI, `before_script`, `script`, `after_script`, los artefactos y la cancelación los gestiona GitLab Runner. Las configuraciones `image:` y `services:` del pipeline no configuran este entorno de shell; utiliza las herramientas instaladas en la <.localized_link href="/guides/features/runners/profiles">imagen del runner</.localized_link> o instálalas en tu script.

El token de autenticación reutilizable del runner permanece en el servidor de Tuist. Las máquinas reciben credenciales únicamente para el trabajo que se les ha asignado. Actualmente, los permisos de firma de caché están retenidos para los trabajos de GitLab. Los volúmenes de caché de Linux personalizados verifican la identidad del trabajo y el permiso de guardado a través de la API de GitLab; las variables de CI sobrescribibles no establecen confianza.

GitLab marca un trabajo como en ejecución y comienza su tiempo de espera tan pronto como Tuist lo adquiere. Mientras los trabajos que Tuist ya ha adquirido consumen el límite de concurrencia de tu cuenta, los siguientes trabajos permanecen pendientes en GitLab. Un trabajo adquirido espera una máquina hasta su tiempo de espera de trabajo, como máximo 12 horas. Si ninguna máquina está disponible para entonces, Tuist hace fallar la asignación con `runner_system_failure`, y la política de reintento anterior permite que GitLab lo reintente. La misma política cubre una máquina runner perdida.

## Rotación de tokens y desconexión {#rotating-tokens-and-disconnecting}

Actualiza los tokens de la conexión y selecciona **Guardar cambios** para rotarlos. Dejar un token en blanco conserva la credencial existente.

**Desconectar** detiene la adquisición y hace fallar las asignaciones en espera. Los trabajos en ejecución continúan con sus propias credenciales. Si no se puede alcanzar GitLab, Tuist mantiene la conexión deshabilitada mientras reintenta la cancelación de las asignaciones en espera. La conexión se elimina una vez que esas asignaciones se han resuelto.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre trabajos con <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilicen.

### Pipelines de solicitudes de fusión {#merge-request-pipelines}

Los pipelines de push, programados y web del proyecto guardan sus cambios en volúmenes de caché. Los pipelines de solicitudes de fusión utilizan la caché y guardan sus cambios solo cuando la conexión tiene un token de acceso a la API:

1. En GitLab, crea un token de acceso de proyecto o de grupo con el rol **Reporter** y el ámbito `read_api`. Un token de grupo cubre todos los proyectos del grupo que se ejecutan en runners de Tuist.
2. En **Ajustes → Integraciones**, pégalo en **Token de acceso a la API** en la tarjeta de GitLab CI y selecciona **Guardar cambios**.

A continuación, Tuist lee la solicitud de fusión de cada pipeline de solicitud de fusión. Los pipelines de solicitudes de fusión abiertas desde una rama del propio proyecto guardan sus cambios bajo la rama de origen de la solicitud de fusión, por lo que la <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">configuración de ramas</.localized_link> del perfil del runner se aplica a esa rama. Las solicitudes de fusión desde forks nunca se guardan. Si Tuist no puede leer la solicitud de fusión, el trabajo sigue ejecutándose y utiliza la caché, pero sus cambios se descartan.
