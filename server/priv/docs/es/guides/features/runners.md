---
{
  "title": "Runners",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Runners de Tuist son entornos gestionados en macOS y Linux para GitHub Actions y Buildkite, con una caché ubicada junto al procesamiento y compartida con tus máquinas locales."
}
---
# Runners {#runners}

> [!IMPORTANT]
> **Solo por invitación**
>
> Tuist Runners está disponible actualmente solo por invitación mientras escalamos la capacidad. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta. Los precios aún no son públicos; los anunciaremos más adelante este año, cuando Runners esté disponible para todo el público.


Tuist Runners son entornos de ejecución gestionados en macOS y Linux para tus flujos de trabajo de GitHub Actions y pipelines de Buildkite. En lugar de ejecutar jobs en las máquinas alojadas por tu proveedor de CI, apuntas un job a un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y se ejecuta en la flota de Tuist, junto a la misma <.localized_link href="/guides/features/cache">caché</.localized_link> que tu equipo ya usa, sin necesidad de instalar ningún agente runner ni mantener infraestructura.

Adoptarlos suele implicar un cambio de una sola línea en un job:

::: code-group

```diff [GitHub Actions]
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

```diff [Buildkite]
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```
<!-- -->
:::

## Emuladores de Android en Linux {#android-emulators}

Los runners Linux ofrecen virtualización acelerada por hardware a través de `/dev/kvm` de forma predeterminada. Usa tu <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> Linux habitual, como `tuist-linux`, para ejecutar emuladores de Android x86_64, incluidos Gradle Managed Devices. No se necesita ningún perfil de runner especial, acción de configuración de KVM, cambio de permisos ni `sudo` para acceder al dispositivo.

La imagen del runner incluye el SDK de Android. Instala el emulador y sus bibliotecas de runtime antes de iniciar un dispositivo. Para un proyecto que ya define un Gradle Managed Device llamado `pixel6`, un job de GitHub Actions tiene este aspecto:

```yaml
jobs:
  android-test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install emulator dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            libx11-6 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 \
            libxrender1 libpulse0 libnss3 libxkbcommon-x11-0 libxcb-cursor0 \
            libasound2 libglu1-mesa
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'emulator'
      - name: Check hardware acceleration
        run: |
          test -r /dev/kvm && test -w /dev/kvm
          "$ANDROID_HOME/emulator/emulator" -accel-check
      - name: Run instrumented tests
        run: ./gradlew :app:pixel6DebugAndroidTest
```

Usa la versión de Java requerida por tu Android Gradle Plugin y sustituye la tarea de test por la tarea de managed-device de tu proyecto. Configura una imagen de sistema **x86_64**. Elige una forma de runner con suficiente memoria tanto para Gradle como para los emuladores; los dispositivos concurrentes comparten la asignación de CPU y memoria del job.

Ejecuta el emulador como el usuario normal del runner. `sudo` en este ejemplo solo sirve para instalar paquetes del sistema operativo.

Los emuladores usan virtualización anidada, por lo que sus tiempos pueden diferir de los de un dispositivo Android físico. Considera los benchmarks del emulador como mediciones de ese entorno de CI, en lugar del rendimiento de un dispositivo físico.

## Límites de concurrencia {#concurrency-limits}

Cada cuenta tiene límites de concurrencia independientes de vCPU y memoria para macOS y Linux. Antes de que Tuist admita un job, comprueba la <.localized_link href="/guides/features/runners/profiles#machine-shapes">forma de máquina</.localized_link> del job frente a todos los jobs que se están ejecutando actualmente en esa plataforma. El job solo comienza cuando tanto su vCPU como su memoria caben dentro de la capacidad restante; de lo contrario, permanece en cola hasta que haya capacidad disponible. El trabajo en una plataforma nunca consume la capacidad de la otra plataforma.

La sección **Concurrencia** del panel de Runners muestra el pico de uso de vCPU y memoria admitido por hora. Una barra roja significa que el uso alcanzó el límite configurado en algún momento durante esa hora. El uso no puede superar la línea porque los jobs que llevarían cualquier recurso por encima de su límite permanecen en cola.

Tus límites actuales se muestran junto a cada gráfico. Si tus flujos de trabajo los alcanzan con frecuencia y pasan tiempo en cola, [contacta con nosotros](mailto:contact@tuist.dev) indicando el identificador de tu cuenta, la plataforma y la carga de trabajo paralela esperada. Revisaremos la capacidad necesaria y te ayudaremos a aumentar los límites.

## Acceso a la red {#network-access}

Los jobs pueden abrir conexiones salientes hacia Internet público. Los rangos de direcciones privadas (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) están bloqueados y los runners no aceptan conexiones entrantes.

| Plataforma | Puertos salientes |
| --- | --- |
| Linux | TCP 22 (SSH), 80 (HTTP) y 443 (HTTPS), además de DNS |
| macOS | Todos los puertos |

SSH cubre dependencias `git@`, submódulos SSH, claves de despliegue y despliegues mediante `ssh` o `scp`. Si un flujo de trabajo de Linux necesita otro puerto saliente, [contacta con nosotros](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="Conecta GitHub, apunta runs-on a un perfil de Tuist y ejecuta tu primer job en la flota."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Conecta tu clúster, nombra una cola con el nombre de un perfil de Tuist y apúntala desde un paso."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="Conecta GitLab una vez y elige la máquina de cada job con etiquetas de pipeline."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Perfiles"
    details="Elige una plataforma, tamaño y versión de Xcode con perfiles de máquina con nombre a los que haces referencia desde tus jobs."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Volúmenes de caché"
    details="Mantén las cachés de Xcode, de módulos y de Gradle, así como cualquier otro directorio, entre jobs, con una copia privada con escritura habilitada para cada ejecución."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Por qué Tuist Runners {#why-tuist-runners}

La mayoría de proveedores de runners de CI aceleran los jobs ofreciéndote máquinas más potentes y una caché persistente, normalmente un volumen compartido montado de nuevo en tus ejecuciones de CI. Eso ayuda, pero un volumen es solo un disco: conserva lo que las ejecuciones anteriores de CI hayan dejado en él. No se replica para mantener únicamente los artefactos más recientes cerca de donde se ejecutan las compilaciones y nunca llega a los otros lugares donde se compila tu código.

Ya no se compila en un único lugar. El mismo código se compila en los portátiles de los desarrolladores, en CI y, cada vez más, mediante agentes de programación y otros entornos automatizados. Tuist Runners es diferente porque comparte la misma <.localized_link href="/guides/features/cache">caché</.localized_link> desde la que todos esos entornos ya leen y escriben, independientemente del sistema de build que uses. Los artefactos que un compañero preparó en su portátil, que generó un agente o que dejó una compilación anterior suponen un acierto en el runner, y viceversa. No hay una caché de CI separada que preparar y la mejora de velocidad no se limita a CI.

Además, la caché está ubicada junto al runner en la misma red privada, por lo que las lecturas y escrituras de caché permanecen internas y cerca del cómputo en lugar de cruzar Internet público.

En resumen:

- **Compartido en todos los entornos.** El runner lee y escribe en la misma caché que tus máquinas de desarrollo, CI y agentes de programación, por lo que el trabajo realizado en cualquier lugar prepara la caché en todas partes.
- **Ubicado junto al cómputo.** El tráfico de caché permanece en la red interna junto al runner, no a través de una entrada pública.
- **Un solo sistema, no añadido.** La caché, los <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link>, la <.localized_link href="/guides/features/test-sharding">distribución de tests</.localized_link> y los <.localized_link href="/guides/features/build-insights">análisis de compilaciones</.localized_link> se ejecutan sobre el mismo proyecto y cuenta, por lo que el runner no es un silo separado de datos de compilación.
