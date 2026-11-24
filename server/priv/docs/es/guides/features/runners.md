---
{
  "title": "Runners",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Runners de Tuist son entornos gestionados en macOS y Linux para GitHub Actions, Buildkite, GitLab CI y Bitrise, con una caché ubicada junto al procesamiento y compartida con tus máquinas locales."
}
---
# Runners {#runners}

Tuist Runners son ejecutores gestionados en macOS y Linux para tus pipelines de GitHub Actions, Buildkite, GitLab CI y Bitrise. En lugar de ejecutar trabajos en las máquinas alojadas por tu proveedor de CI, configuras un trabajo para que use un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y se ejecute en la flota de Tuist, junto a la misma <.localized_link href="/guides/features/cache">caché</.localized_link> que ya usa tu equipo, sin necesidad de instalar ningún agente de ejecución ni mantener infraestructura. Para entender qué impulsa tu factura de CI antes de cambiar de máquinas, consulta [Costes de CI](https://tuist.dev/solutions/ci-costs).

Adoptarlos suele requerir un cambio de una sola línea en un trabajo:

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

Los ejecutores Linux ofrecen virtualización acelerada por hardware a través de `/dev/kvm` de forma predeterminada. Usa tu <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> Linux habitual, como `tuist-linux`, para ejecutar emuladores de Android x86_64, incluidos los Gradle Managed Devices. No hace falta ningún perfil de runner especial, acción de configuración de KVM, cambio de permisos ni `sudo` para acceder al dispositivo.

La imagen del runner incluye el SDK de Android. Instala el emulador y sus bibliotecas de tiempo de ejecución antes de iniciar un dispositivo. Para un proyecto que ya define un Gradle Managed Device llamado `pixel6`, un trabajo de GitHub Actions tendría este aspecto:

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

Usa la versión de Java requerida por tu Android Gradle Plugin y sustituye la tarea de test por la tarea de managed-device de tu proyecto. Configura una imagen de sistema **x86_64**. Elige una forma de runner con suficiente memoria tanto para Gradle como para los emuladores; los dispositivos concurrentes comparten la asignación de CPU y memoria del trabajo.

Ejecuta el emulador como el usuario normal del runner. `sudo` en este ejemplo solo se usa para instalar paquetes del sistema operativo.

Los emuladores usan virtualización anidada, por lo que sus tiempos pueden diferir de los de un dispositivo Android físico. Considera los benchmarks de emuladores como mediciones de ese entorno de CI, no como rendimiento de un dispositivo físico.

## Límites de concurrencia {#concurrency-limits}

Cada cuenta tiene límites independientes de concurrencia de vCPU y memoria para macOS y Linux. Antes de admitir un trabajo, Tuist comprueba la <.localized_link href="/guides/features/runners/profiles#machine-shapes">forma de máquina</.localized_link> del trabajo frente a todos los trabajos que se están ejecutando actualmente en esa plataforma. El trabajo solo comienza cuando tanto su vCPU como su memoria caben dentro de la capacidad restante; de lo contrario, permanece en cola hasta que haya capacidad disponible. El trabajo en una plataforma nunca consume la capacidad de la otra plataforma.

Las cuentas Air tienen límites de concurrencia fijos. Para las cuentas Pro y Enterprise, Tuist añade automáticamente margen adicional según el uso recurrente y el trabajo en cola reciente que no cabe junto a los runners activos. Los ajustes automáticos solo aumentan los límites: se conservan las concesiones existentes y la capacidad mínima contractual. El crecimiento es gradual y está acotado por techos de seguridad, por lo que un pico repentino no otorga concurrencia ilimitada. Un límite de cuenta más alto no garantiza máquinas disponibles de inmediato.

La sección **Concurrencia** del panel de Runners muestra el pico de uso de vCPU y memoria admitido por cada hora, con una línea escalonada para el límite conocido al inicio de cada hora. Las barras rojas alcanzaron ese umbral histórico; por sí solas no demuestran que un trabajo esperara. Un aumento durante una hora puede situar su pico por encima de la línea de inicio del intervalo. Los límites actuales se muestran junto a cada gráfico. Los periodos anteriores al inicio del seguimiento histórico no tienen línea de límite, en lugar de asumir un valor histórico.

Si los flujos de trabajo siguen poniéndose en cola en el techo de seguridad, [contáctanos](mailto:contact@tuist.dev) indicando el identificador de tu cuenta, la plataforma y la carga paralela esperada para que podamos revisar la capacidad necesaria.

## Acceso a la red {#network-access}

Los trabajos pueden abrir conexiones salientes a Internet público. Los rangos de direcciones privadas (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) están bloqueados y los runners no aceptan conexiones entrantes.

| Plataforma | Puertos salientes |
| --- | --- |
| Linux | TCP 22 (SSH), 80 (HTTP) y 443 (HTTPS), además de DNS |
| macOS | Todos los puertos |

SSH cubre dependencias `git@`, submódulos SSH, claves de despliegue y despliegues mediante `ssh` o `scp`. Si un flujo de trabajo Linux necesita otro puerto saliente, [contáctanos](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="Conecta GitHub, apunta runs-on a un perfil de Tuist y ejecuta tu primer trabajo en la flota."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Conecta tu clúster, nombra una cola con el nombre de un perfil de Tuist y apúntala desde un paso."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="Conecta GitLab una vez y elige la máquina de cada trabajo con etiquetas de pipeline."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="Conecta tu espacio de trabajo y ejecuta compilaciones de tus pools de runners autoalojados en perfiles de Tuist."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="Ejecuta trabajos desde tu propia forja git u orquestador con una sola solicitud y síguelos con webhooks."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Perfiles"
    details="Elige una plataforma, tamaño y versión de Xcode con perfiles de máquina con nombre a los que haces referencia desde tus trabajos."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="Imágenes"
    details="Consulta qué viene preinstalado en los runners de macOS y Linux: Xcode, simuladores, la toolchain de Metal, Docker, el SDK de Android y más."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Volúmenes de caché"
    details="Mantén las cachés de Xcode, de módulos y de Gradle, así como cualquier otro directorio, entre trabajos, con una copia privada con escritura habilitada para cada ejecución."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Acciones de grafo de Struo {#struo-graph-actions}

<a id="once-graph-actions"></a>

Struo puede ejecutar acciones de comando de grafo elegibles en los workers Linux de Tuist cuando la cuenta tiene habilitada la ejecución remota y el servidor anuncia capacidades de worker compatibles. Se trata de ejecución a nivel de acción, separada de los trabajos del proveedor de CI mencionados anteriormente. Consulta <.localized_link href="/guides/features/runners/struo">Ejecución remota de Struo</.localized_link> para conocer la configuración, los requisitos de imagen y las comprobaciones de compatibilidad.

## Por qué usar Tuist Runners {#why-tuist-runners}

La mayoría de los proveedores de runners de CI aceleran los trabajos ofreciéndote máquinas más potentes y una caché persistente, normalmente un volumen compartido que se monta de nuevo en tus ejecuciones de CI. Eso ayuda, pero un volumen es solo un disco: conserva lo que las ejecuciones anteriores de CI hayan dejado en él. No se replica para mantener únicamente los artefactos más recientes cerca de donde se ejecutan las compilaciones, y nunca llega a los otros lugares donde se compila tu código.

Ya no se compila en un único lugar. El mismo código se compila en los portátiles de los desarrolladores, en entornos de CI y, cada vez más, mediante agentes de programación y otros entornos automatizados. Los Tuist Runners son diferentes porque comparten la misma <.localized_link href="/guides/features/cache">caché</.localized_link> desde la que todos esos entornos ya leen y escriben, independientemente del sistema de compilación que uses. Los artefactos que un compañero ha calentado en su portátil, que ha producido un agente o que ha dejado una compilación anterior suponen un acierto en el runner, y viceversa. No hay una caché de CI separada que calentar, y la mejora de velocidad no se limita a CI.

Además, la caché está ubicada junto al runner en la misma red privada, por lo que las lecturas y escrituras de caché permanecen internas y cerca del cómputo en lugar de cruzar Internet público.

En conjunto:

- **Compartida en todos los entornos.** El runner lee y escribe en la misma caché que tus máquinas de desarrollo, CI y agentes de programación, de modo que el trabajo realizado en cualquier lugar calienta la caché en todas partes.
- **Ubicada junto al cómputo.** El tráfico de caché permanece en la red interna junto al runner, no a través de una entrada pública.
- **Un único sistema, no añadido posteriormente.** La caché, los <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link>, la <.localized_link href="/guides/features/test-sharding">fragmentación de tests</.localized_link> y los <.localized_link href="/guides/features/build-insights">análisis de compilaciones</.localized_link> se ejecutan contra el mismo proyecto y cuenta, por lo que el runner no constituye un silo separado de datos de compilación.
