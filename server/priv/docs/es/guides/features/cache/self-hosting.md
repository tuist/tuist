---
{
  "title": "Caché autoalojada",
  "titleTemplate": ":title | Caché | Guías | Tuist",
  "description": "Despliega nodos de caché autoalojados y conéctalos a Tuist."
}
---

# Caché autoalojada {#self-hosted-cache}

Los nodos de caché autoalojados te permiten mantener los artefactos de compilación y los metadatos de la caché cerca de las máquinas que producen y consumen los resultados de la compilación. Úsalos cuando la latencia de la caché sea importante en CI, oficinas de desarrollo, estaciones de trabajo remotas o clústeres de cómputo regionales.

El objetivo es tener una caché de baja latencia en todas partes, no solo en el único entorno donde una caché central está casualmente cerca. Cada nodo de caché atiende lecturas y escrituras desde el disco local, mientras que la malla replica artefactos y metadatos entre pares para que otras ubicaciones puedan beneficiarse de la misma caché con el tiempo.

> [!NOTE]
> Los nodos de caché autoalojados de Tuist funcionan gracias a [Kura](https://github.com/tuist/tuist/tree/main/kura), la malla de caché descentralizada de Tuist. Kura es el plano de datos para los nodos de caché: atiende lecturas y escrituras de la caché, almacena el estado local en disco y replica artefactos y metadatos a los nodos pares.

## Cómo se integra la caché autoalojada con Tuist {#how-self-hosted-cache-fits-with-tuist}

La caché gestionada de Tuist utiliza `https://<account>.cache.tuist.dev`. Con un servidor Tuist autoalojado, la CLI obtiene la URL de la caché desde la configuración `TUIST_CACHE_ENDPOINTS` del servidor. Establécela en la URL de tu servidor de caché principal o balanceador de carga. Si contiene varias URL, se utiliza la primera.

Para nodos de caché privados o personalizados conectados al **servidor Tuist alojado**, establece un endpoint explícito en los shells de desarrollo y en CI:

```sh
export TUIST_CACHE_ENDPOINT=https://cache.example.com
```

Esta anulación tiene prioridad en ambos tipos de servidor y es opcional para los servidores Tuist autoalojados. Para el demonio de caché de Xcode, vuelve a ejecutar `tuist setup cache` después de configurarlo para que LaunchAgent reciba el entorno actualizado.

Un servidor Tuist autoalojado toma los endpoints de la configuración estática. En el servidor alojado por Tuist, los nodos se autentican con una credencial y se registran. Despliega primero un nodo con una de las dos secciones siguientes y consulta [Conectar nodos a Tuist](#connect-nodes-to-tuist).

## Despliegue en Kubernetes {#deploy-on-kubernetes}

Kura se distribuye como un chart de Helm a través de GitHub Container Registry. Despliega Kura como un `StatefulSet` con volúmenes persistentes, un servicio headless para el descubrimiento de pares y un servicio regular para el tráfico HTTP y gRPC.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

Para un servidor Tuist autoalojado en el mismo clúster, configura su endpoint de caché principal:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

Esto establece `TUIST_CACHE_ENDPOINTS` en el pod del servidor. Usa una dirección a la que puedan acceder las máquinas de los desarrolladores y CI; el nombre de servicio local del clúster anterior es adecuado para clientes que se ejecutan dentro del clúster.

> [!IMPORTANT]
> Cada nodo de Kura debe poseer su propio `KURA_DATA_DIR`. Kura toma un bloqueo de escritura a nivel de aplicación en el directorio de datos y espera que exactamente un proceso lo posea. En Kubernetes, usa un volumen persistente por pod. Fuera de Kubernetes, no apuntes múltiples procesos al mismo directorio montado.

## Despliegue sin Kubernetes {#deploy-without-kubernetes}

Kura también puede ejecutarse como un contenedor normal en máquinas virtuales o hosts bare-metal. En este modo, eres responsable de la supervisión de procesos, el almacenamiento persistente, el enrutamiento y el descubrimiento de pares.

Como mínimo, cada nodo necesita un directorio de datos persistente, un directorio temporal, un puerto de caché público (un listener atiende tanto la API de caché HTTP como REAPI gRPC), una URL interna de par y ya sea una lista estática de pares o un mecanismo de descubrimiento:

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/var/cache/kura/tmp \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

En un servidor Tuist autoalojado, configura la URL de caché principal a la que puedan acceder las máquinas de los desarrolladores y CI:

```bash
TUIST_CACHE_ENDPOINTS=https://cache.example.com
```

## Colocar nodos detrás de un balanceador de carga {#load-balancers}

Los clientes utilizan cada URL de endpoint de caché tanto para HTTP como para gRPC: HTTP para comprobaciones de estado y la API de caché HTTP, y gRPC para la caché de módulos y la caché remota de Bazel. Cualquier ingress, balanceador de carga o CDN entre los clientes y Kura debe reenviar ambos protocolos en el mismo nombre de host y puerto. Esto se aplica a cada endpoint que reciben los clientes, porque la CLI elige el que responda más rápido. Si gRPC no llega a Kura, la CLI advierte que la caché remota de módulos no está disponible y utiliza solo la caché local de módulos.

Enruta estos prefijos de ruta a Kura como gRPC sobre HTTP/2, y todo lo demás como HTTP:

| Prefijo de ruta | Utilizado por |
| --- | --- |
| `/build.bazel.remote.execution.v2.` | Caché de módulos, Bazel |
| `/google.bytestream.` | Caché de módulos, Bazel |
| `/build.bazel.remote.asset.v1.` | Bazel |
| `/google.devtools.build.v1.` | Eventos de compilación de Bazel |

Kura acepta HTTP/2 en texto plano (h2c) en `KURA_PORT`, y HTTP/2 sobre TLS en `KURA_HTTPS_PORT` cuando `KURA_PUBLIC_TLS_CERT_PATH` y `KURA_PUBLIC_TLS_KEY_PATH` están configurados. Si tu proxy reutiliza conexiones ascendentes entre solicitudes, como hace ingress-nginx, establece `KURA_GATEWAY_GRPC_PORT` y envía el tráfico gRPC a ese puerto en su lugar. Solo sirve gRPC, por lo que las solicitudes HTTP/1.1 y gRPC nunca comparten una conexión.

Configura las rutas gRPC con:

- Sin límite de tamaño del cuerpo de la solicitud. Una subida envía un archivo en una sola solicitud, hasta 2 GiB.
- Búfer de solicitud y respuesta desactivado.
- Tiempos de espera de lectura, envío e inactividad de al menos 300 segundos.

Kura no sirve el servicio de comprobación de estado gRPC. Comprueba el estado de los nodos por HTTP en `/ready`. Si tu balanceador de carga requiere una comprobación de estado gRPC, llama a `/build.bazel.remote.execution.v2.Capabilities/GetCapabilities` y acepta los códigos de estado gRPC `0` y `16`. Un nodo con autorización habilitada responde a una solicitud sin token con `16` (`UNAUTHENTICATED`).

### ingress-nginx {#load-balancers-ingress-nginx}

Con el chart de Helm, mantén el ingress HTTP en `/` y añade un ingress gRPC para el mismo host. Solo el ingress HTTP declara TLS:

```yaml
service:
  gatewayGrpcPort: 4001

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - kura.example.com
      secretName: kura-tls

grpcIngress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  hosts:
    - host: kura.example.com
      paths:
        - path: /build\.bazel\.remote\.execution\.v2\.
          pathType: ImplementationSpecific
        - path: /google\.bytestream\.
          pathType: ImplementationSpecific
        - path: /build\.bazel\.remote\.asset\.v1\.
          pathType: ImplementationSpecific
        - path: /google\.devtools\.build\.v1\.
          pathType: ImplementationSpecific
```

### AWS Application Load Balancer {#load-balancers-aws-alb}

Los grupos de destino gRPC necesitan un listener HTTPS. En ese listener:

1. Reenvía la regla predeterminada a un grupo de destino con versión de protocolo `HTTP1` en `KURA_PORT`, con comprobación de estado por HTTP en `/ready`.
2. Crea un segundo grupo de destino con versión de protocolo `gRPC`, usando el protocolo `HTTP` en `KURA_GATEWAY_GRPC_PORT` (o `KURA_PORT`), o el protocolo `HTTPS` en `KURA_HTTPS_PORT`. Configura su comprobación de estado como se describe arriba.
3. Añade una regla que reenvíe los patrones de ruta `/build.bazel.remote.execution.v2.*`, `/google.bytestream.*`, `/build.bazel.remote.asset.v1.*` y `/google.devtools.build.v1.*` al segundo grupo de destino.
4. Aumenta el tiempo de espera de inactividad del balanceador de carga a al menos 300 segundos.

### CDN {#load-balancers-cdns}

Un CDN situado delante de un nodo debe admitir gRPC y no debe bloquear las rutas gRPC en sus reglas de firewall. Los clientes suben artefactos grandes en fragmentos de como máximo 2 MiB y hacen que el nodo los ensamble, por lo que ninguna solicitud necesita un cuerpo grande ni una subida prolongada. La caché de módulos y la caché de compilación de Xcode hacen esto, y Bazel también lo hace cuando se compila con `--experimental_remote_cache_chunking` (Bazel 8.7 y 9.1 o posterior). Sin esa opción, Bazel sube cada salida en una sola solicitud, por lo que el CDN también debe permitir cuerpos de solicitud grandes y subidas que tarden tanto como necesiten tus salidas más grandes en tu enlace más lento. Si tu CDN no puede cumplir estos requisitos, proporciona a los clientes un nombre de host que lo omita, por ejemplo un registro solo DNS.

#### Cloudflare {#load-balancers-cloudflare}

La caché de módulos funciona a través de un nombre de host de Cloudflare con proxy en cualquier plan. En la zona:

1. En **Network**, activa **gRPC**.
2. En **SSL/TLS**, establece el modo de cifrado en **Full** o **Full (strict)**. Cloudflare se conecta al origen en el puerto 443, por lo que el origen debe servir TLS allí y ofrecer HTTP/2 mediante ALPN.
3. Asegúrate de que ninguna regla personalizada de WAF ni regla administrada bloquee las rutas gRPC indicadas arriba.

Cloudflare finaliza una solicitud cuando el origen no ha empezado a responder tras unos dos minutos. Una subida de Bazel sin `--experimental_remote_cache_chunking` solo recibe respuesta cuando llega su último byte, por lo que en Cloudflare esas subidas fallan si tardan más que eso.

## Conectar nodos a Tuist {#connect-nodes-to-tuist}

Configura el enrutamiento de clientes y registra tus nodos en Tuist para que sus direcciones, estado de preparación y uso aparezcan en el panel.

En un **servidor Tuist autoalojado**, declaras los puntos de conexión de forma estática con `TUIST_CACHE_ENDPOINTS`, como se muestra en las secciones de despliegue anteriores. La CLI usa la primera URL configurada. `TUIST_CACHE_ENDPOINT` anula esa URL para un cliente individual.

En el **servidor alojado por Tuist**, establece `TUIST_CACHE_ENDPOINT` en los entornos de desarrollo y en la CI para enrutar las solicitudes de caché a tus nodos. Cada nodo se autentica con una credencial que generas, luego registra su dirección e informa de su estado de preparación al panel. Esta sección cubre el registro de nodos.

> [!IMPORTANT]
> **Plan Enterprise**
>
> Los nodos de caché autoalojados están disponibles en el plan Enterprise. La sección **Servidores autoalojados** descrita más abajo solo aparece para cuentas en ese plan.

### Generar una credencial de nodo {#generate-a-node-credential}

En el panel de Tuist, abre tu cuenta, ve a **Caché** y busca **Servidores autoalojados**. Elige **Generar credencial** para crear un ID de cliente y un secreto.

La credencial solo autoriza el tráfico de la cuenta que la creó.

El secreto se muestra una vez y no se puede recuperar después de cerrar el diálogo, así que cópialo directamente en el almacén de secretos del que leen tus nodos. Revocar una credencial detiene inmediatamente la autenticación de todos los nodos que la usan, por lo que debes generar un reemplazo antes de revocar una que esté en servicio.

### Inscribir el nodo al arrancar {#enroll-the-node-on-boot}

La inscripción es la forma recomendada de poner en marcha un nodo. Establece `KURA_ENROLL_ON_BOOT` y proporciona al nodo su credencial y su propia URL de peer:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

El nodo genera su par de claves localmente, por lo que la clave privada nunca sale de él, y recibe un certificado de peer firmado, la CA de la cuenta, su identificador de tenant y la lista de peers. Eso es todo lo que de otro modo configurarías manualmente: un nodo inscrito no necesita `KURA_TENANT_ID`, ni `KURA_PEERS`, ni configuración de TLS entre peers.

Deja `KURA_INTERNAL_TLS_*` sin establecer: la inscripción escribe el material del certificado en un directorio `tls` bajo `KURA_DATA_DIR`. Configura esas rutas tú mismo solo cuando proporciones los certificados en lugar de inscribirte, como se describe en [Crear una malla de caché](#build-a-cache-mesh).

Un nodo que se une por primera vez a la malla de una cuenta extrae la caché existente de la cuenta antes de convertirse en un miembro activo del anillo. Dimensiona el volumen de datos para toda la caché y espera que la primera unión tarde un tiempo a través de un enlace de área extensa. El nodo informa `joining` hasta que se pone al día, y luego `serving`.

### Anunciar el punto de conexión {#advertise-the-endpoint}

La inscripción une el nodo a la malla. El registro informa a Tuist de la dirección orientada al cliente del nodo y de su estado de preparación. Establece las variables de registro:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

El nodo envía latidos cada 60 segundos frente a un arrendamiento de 180 segundos. Tuist considera que su registro no está disponible cuando expira el arrendamiento. Tuist nunca llama al nodo, por lo que solo tiene que ser alcanzable por tus clientes, no desde internet.

### Verificar que el nodo está sirviendo {#verify-the-node-is-serving}

De vuelta en **Caché** en el panel, el nodo aparece bajo **Nodos registrados** con su punto de conexión, región, estado y último latido. Un nodo que nunca aparece no está alcanzando el punto de conexión de registro o está fallando en la autorización. Un nodo que aparece y luego desaparece ha dejado de enviar latidos o ha dejado de informarse como listo.

### Hacer coincidir el identificador de tenant con el handle de tu cuenta {#match-the-tenant-identifier}

`KURA_TENANT_ID` debe ser igual al handle de tu cuenta de Tuist. El plano de control compara el tenant del latido con la cuenta resuelta a partir de la credencial y rechaza una discrepancia con `409 tenant_mismatch`, por lo que un nodo con el valor incorrecto se autentica correctamente pero nunca se registra.

> [!IMPORTANT]
> Tanto el chart de Helm como el ejemplo de contenedor anterior en esta guía establecen por defecto esto en `default`. Ese valor es correcto para un servidor Tuist autoalojado, donde el tenant es una etiqueta local, e incorrecto para una cuenta en el servidor alojado por Tuist, donde debe nombrar la cuenta. Inscribir el nodo evita por completo la cuestión, porque el plano de control proporciona el valor.

Un `KURA_TENANT_ID` no establecido no omite la comprobación. Deshabilita el registro por completo: el nodo sigue sirviendo tráfico de caché, nada aparece en el panel y no se informa de ningún error. Si un nodo está sano pero falta en **Nodos registrados**, comprueba primero esta variable.

### Elegir una URL anunciada que tus clientes puedan alcanzar {#choose-an-advertised-url}

Usa una dirección alcanzable por el cliente para `KURA_ADVERTISED_HTTP_URL` y para la URL de caché configurada en el servidor Tuist o en la CLI.

Un nombre de host solo interno es adecuado cuando cada cliente configurado para usarlo puede resolver y alcanzar ese nombre. Para clientes en diferentes redes, usa una dirección compartida alcanzable o configura un nodo de caché alcanzable para cada entorno.

## Crear una malla de caché {#build-a-cache-mesh}

Una malla de caché te permite situar la capacidad de caché junto al cómputo que la necesita. Una empresa podría ejecutar un nodo cerca de sus principales runners de CI, otro cerca de los desarrolladores en Europa y otro cerca de una oficina en EE. UU. o de un clúster de compilación regional. Cada ubicación lee y escribe en el nodo más cercano, mientras Kura replica artefactos y metadatos en segundo plano para que las compilaciones posteriores en otras ubicaciones puedan reutilizar los mismos resultados.

La malla solo funciona si los nodos pueden alcanzarse entre sí por el puerto interno de pares de Kura. Ese plano de pares es independiente de los puntos de conexión públicos de caché que usan los clientes de Tuist. Kura lo utiliza para comprobar la pertenencia, realizar backfill de los nodos recién incorporados y replicar artefactos una vez aceptadas las escrituras locales.

Recomendamos encarecidamente asegurar el plano de pares con [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) cuando los nodos se comunican a través de regiones, nubes, VPC, oficinas o cualquier red que no sea totalmente privada para el despliegue de caché. Con mTLS habilitado, Kura solo sirve los puntos de conexión internos de replicación a pares que presenten un certificado firmado por la CA configurada. Los certificados de pares deben cubrir los nombres DNS que los nodos utilizan para llamarse entre sí, y las URL de pares deben usar `https://` en el puerto interno.

> [!NOTE]
> Los nodos que se inscriben en un plano de control alojado por Tuist reciben su certificado de par y la CA de la cuenta durante la inscripción, por lo que los pasos manuales siguientes se aplican a mallas que no se inscriben.

Por ejemplo, esto genera una CA privada y un certificado de par que puede montar cada nodo en una malla pequeña. Sustituye los nombres DNS por los nombres internos que tus nodos usan en `KURA_NODE_URL` y `KURA_PEERS`.

```bash
mkdir -p kura-peer-tls
cd kura-peer-tls

openssl ecparam -genkey -name prime256v1 -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=kura-peer-ca" \
  -out ca.pem

openssl ecparam -genkey -name prime256v1 -noout -out tls.key
openssl req -new -key tls.key \
  -subj "/CN=kura-peer" \
  -out peer.csr

cat > peer.ext <<'EOF'
subjectAltName = DNS:kura-0.kura-headless.kura.svc.cluster.local,DNS:kura-1.kura-headless.kura.svc.cluster.local,DNS:kura-2.kura-headless.kura.svc.cluster.local,DNS:kura-1.internal,DNS:kura-2.internal
extendedKeyUsage = serverAuth,clientAuth
keyUsage = digitalSignature,keyEncipherment
EOF

openssl x509 -req -in peer.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 730 \
  -sha256 \
  -extfile peer.ext
```

### Sincronización entre nodos {#catch-up-between-nodes}

Un nodo que se une o vuelve a unirse a una malla realiza **backfill**: recorre las entradas de cada par de la más reciente a la más antigua y descarga lo que le falta, mientras la replicación en vivo cubre las escrituras realizadas mientras el par está visible. Un pase de backfill retrocede desde la entrada más reciente del par hasta el horizonte más antiguo entre el anillo de segmentos del nodo y su último pase completado, por lo que se garantiza que el nodo conserva los datos recientes, aunque no necesariamente todos. `KURA_BACKFILL_MARGIN_PERCENT` establece cuán atrás se sitúa el horizonte.

Hay dos consecuencias que conviene conocer antes de ejecutar una malla:

- Un nodo informa `/ready` una vez que su anillo de segmentos está lleno al `KURA_BACKFILL_READY_RING_PERCENT` **o** su primer ciclo de backfill se estabiliza, y la disponibilidad se mantiene durante el resto de la vida del proceso. Una fluctuación posterior de un par nunca saca de rotación a un nodo que está sirviendo.
- Un ciclo también se estabiliza cuando un par es inalcanzable durante el tiempo suficiente. Por tanto, un nodo cuyo único par está caído pasa a estar Ready aunque tenga pocos o ningún dato. Sirve fallos de caché en lugar de errores. `/status/rollout` informa `backfill_initial_cycle` (`pending`, `complete` o `degraded`) si quieres condicionar un despliegue a esa diferencia.

**Actualizar una malla ante el cambio de backfill.** Las versiones de Kura anteriores al backfill se sincronizaban mediante un protocolo de pares diferente, ya eliminado. Despliega cada nodo a una versión que ejecute backfill **antes** de adoptar una versión que solo hable backfill. Los nodos en los dos protocolos no pueden sincronizarse entre sí: un nodo con datos sigue sirviendo desde su volumen pero deja de cerrar su brecha, y un nodo que arranca con un volumen vacío en esa ventana nunca pasa a Ready. El chart establece `KURA_BACKFILL_ENABLED=true` por ti, por lo que una actualización primero del chart lo cubre. Un único `helm upgrade` que mueve el chart y la imagen juntos no lo hace.

Usa restricciones a nivel de red además de mTLS. En Kubernetes, ejecuta Kura como un `StatefulSet` con un volumen persistente por pod y un servicio headless para el descubrimiento de pares, y permite el puerto interno de pares solo entre pods que pertenezcan al mismo despliegue de caché, por ejemplo con una `NetworkPolicy`. Fuera de Kubernetes, asigna a cada nodo un nombre DNS o una dirección IP estables, inicializa la malla con las URL internas de los demás nodos y usa reglas de firewall o grupos de seguridad para que solo los nodos de caché puedan alcanzar el puerto de pares. El tráfico público de caché debe entrar por los puntos de conexión HTTP o gRPC públicos, no por el plano interno de pares.

## Configuración {#configuration}

El chart de Helm renderiza la configuración común de runtime a partir de `values.yaml`. Si ejecutas Kura sin Kubernetes, establece las mismas variables directamente en el proceso. Las variables que el chart no mapea directamente se pueden inyectar mediante `extraEnv` o `extraEnvFrom`.

| Variable de entorno | Descripción | Requerido | Predeterminado | Valor de Helm |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | Puerto público de caché. Un único listener sirve la API HTTP de caché, los endpoints de salud y gRPC (h2c) de Bazel/Buck2 REAPI. | Sí | Sin predeterminado | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Puerto HTTP interno o mTLS utilizado por los pares de Kura. | Sí | Sin predeterminado | `peerTls.internalPort` |
| `KURA_TENANT_ID` | Identificador de tenant predeterminado para el nodo. | Sí | Sin predeterminado | `config.tenantId` |
| `KURA_REGION` | Etiqueta de región utilizada en métricas y estado de replicación. | Sí | Sin predeterminado | `config.region` |
| `KURA_TMP_DIR` | Directorio temporal para cuerpos de solicitud escalonados y ensamblaje multipart. | Sí | Sin predeterminado | Fijado a `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | Número máximo de bytes escalonados admitidos en `KURA_TMP_DIR` antes de que las solicitudes reciban contrapresión. | No | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | Directorio persistente para el estado de metadatos y archivos de segmentos. | Sí | Sin predeterminado | Fijado a `/var/cache/kura` |
| `KURA_NODE_URL` | URL interna canónica que otros pares usan para alcanzar este nodo. | Sí | Sin predeterminado | Derivada del nombre DNS del pod y `peerTls.internalPort` |
| `KURA_PEERS` | Lista de pares de inicialización usada antes de que converja el descubrimiento. | No | `KURA_NODE_URL` | Derivada de las réplicas del StatefulSet |
| `KURA_DISCOVERY_DNS_NAME` | Nombre DNS usado para el descubrimiento automático de pares. | No | Deshabilitado | Habilitado por `config.discovery.enabled` |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | Certificado de CA usado para verificar mTLS entre pares. | No | Deshabilitado, o derivado bajo `KURA_DATA_DIR` cuando el nodo se registra | `peerTls.enabled` y `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | Certificado usado por el listener interno de mTLS entre pares. | No | Deshabilitado, o derivado bajo `KURA_DATA_DIR` cuando el nodo se registra | `peerTls.enabled` y `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | Clave privada usada por el listener interno de mTLS entre pares. | No | Deshabilitado, o derivado bajo `KURA_DATA_DIR` cuando el nodo se registra | `peerTls.enabled` y `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | Certificado usado para terminar TLS en el listener HTTPS compartido (`KURA_HTTPS_PORT`). | No | Deshabilitado | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | Clave privada asociada con `KURA_PUBLIC_TLS_CERT_PATH`. | No | Deshabilitado | `extraEnv` |
| `KURA_HTTPS_PORT` | Puerto TLS que sirve la misma superficie HTTP + gRPC compartida (negociada por ALPN). Solo se vincula cuando se establecen las rutas públicas de TLS. | No | `4443` | `extraEnv` |
| `KURA_GATEWAY_GRPC_PORT` | Puerto HTTP/2 en texto plano que sirve solo las APIs gRPC, para proxies que reutilizan conexiones upstream. Consulta [Pon nodos detrás de un balanceador de carga](#load-balancers). | No | Deshabilitado | `service.gatewayGrpcPort` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | Presupuesto de descriptores de archivo para I/O de solicitudes y en segundo plano. | No | Derivado automáticamente | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | Cuánto tiempo espera una solicitud antes de que la contrapresión de FD falle la reserva. | No | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | Número máximo de manejadores de lectura de segmentos fijados. | No | Derivado automáticamente | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Ventana de gracia para el trabajo HTTP y gRPC en curso durante el apagado. | No | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Umbral blando de memoria donde Kura comienza a reducir el uso opcional de memoria. | No | Derivado automáticamente | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Umbral duro de memoria donde Kura pausa la replicación y recorta las cachés activas. | No | Derivado automáticamente | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | Tamaño máximo de la caché de manifiestos en memoria. | No | Derivado automáticamente | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | Tamaño máximo de la carga útil keyvalue por solicitud. | No | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | Presupuesto de descriptores de archivo reservado para el almacén de metadatos. | No | Derivado automáticamente | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | Concurrencia de flush y compactación en segundo plano para el almacén de metadatos. | No | Derivado automáticamente | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | Capacidad de la caché de lectura del almacén de metadatos. | No | Derivado automáticamente | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | Presupuesto total de memoria reservado para el buffering de escritura de metadatos. | No | Derivado automáticamente | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | Tamaño de cada buffer de escritura de metadatos antes del flush. | No | Derivado automáticamente | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | Número máximo de buffers de escritura de metadatos mantenidos en memoria. | No | Derivado automáticamente | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | Cuánto tiempo puede permanecer una carga multipart en progreso antes de expirar. | No | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | Con qué frecuencia Kura busca cargas multipart obsoletas. | No | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | Porción del anillo de segmentos ordenados por antigüedad, contado desde el más nuevo, que limita hasta dónde llega una pasada de backfill. | No | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | Porcentaje de llenado del anillo de segmentos en el que un nodo que aún está ejecutando su primer ciclo de backfill se reporta como listo. | No | La mitad de `KURA_BACKFILL_MARGIN_PERCENT` | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | Umbral de bytes con el que se compone un lote de cuerpos de backfill, y el tamaño por encima del cual una entrada se recupera por sí sola. | No | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Número de hilos de trabajo de Tokio. | No | Derivado automáticamente | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Endpoint de trazas OTLP. Déjalo vacío para deshabilitar el tracing. | No | Deshabilitado | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | Nombre del servicio de OpenTelemetry. | Sí | Sin valor predeterminado | Nombre del pod en Helm |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | Entorno de despliegue de OpenTelemetry. | Sí | Sin valor predeterminado | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | DSN de Sentry para reportes de pánico y errores. | No | Deshabilitado | `extraEnv` o `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | País ISO 3166-1 alpha-2 del centro de datos donde se ejecuta el nodo, etiquetado en las trazas exportadas como `geo.country.iso_code`. | No | Derivado de `KURA_REGION` cuando su prefijo es un código de país | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | Subdivisión ISO 3166-2 de ese centro de datos (por ejemplo, `US-CA`), etiquetada como `geo.region.iso_code`. | No | Sin establecer | `extraEnv` |
| `KURA_AUTH_ENABLED` | Requiere que los solicitantes presenten un token válido de Tuist. Establecer `KURA_AUTH_TUIST_URL` habilita la autorización por sí solo, y establecer esto en `false` no la desactiva; deja la URL sin establecer para ejecutar un nodo sin autorización. | No | Deshabilitado | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Servidor de Tuist contra el que el nodo se autoriza. Habilita la autorización por sí solo. | Requerido cuando la autorización está habilitada | Sin valor predeterminado | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | Tiempo de espera de conexión para llamadas a ese servidor. | No | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Tiempo de espera de solicitud para llamadas a ese servidor. | No | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | Secreto compartido para tokens que el nodo puede leer por sí mismo, evitando un viaje de ida y vuelta. Firma tanto como verifica, así que úsalo solo donde el nodo y el servidor estén en el mismo límite de confianza. Los nodos autohospedados normalmente dejan esto sin establecer. | No | Deshabilitado | `extraEnv` o `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | Parte pública del par de claves con el que el servidor firma los tokens de caché, como uno o más bloques PEM concatenados. Lee esos tokens sin poder generar uno, que es lo que debe tener un nodo accesible desde internet. Es mutuamente excluyente con `KURA_AUTH_JWT_SECRET`. | No | Deshabilitado | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | Algoritmo para esa clave: `HS256`, `HS384` o `HS512` con un secreto, `ES256` con una clave pública. | No | `HS256` con un secreto, `ES256` con una clave pública | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | Emisor que deben llevar los tokens. | No | Sin verificar | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | Audiencias separadas por comas que deben llevar los tokens. | No | Sin verificar | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | Número máximo de entradas mantenidas en cada una de las cachés de autenticación y autorización. | No | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | Inscribe el nodo en el plano de control en cada arranque, aprovisionando su certificado de peer y proporcionando `KURA_TENANT_ID` y `KURA_PEERS`. | No | Deshabilitado | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Servidor de Tuist contra el que el nodo se inscribe. | Requerido al inscribirse | Sin valor predeterminado | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | ID de cliente de la credencial del nodo generada en el dashboard. | Requerido al inscribirse o registrarse | Sin valor predeterminado | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Secreto de cliente asociado a `KURA_CONTROL_PLANE_CLIENT_ID`. | Requerido al inscribirse o registrarse | Sin valor predeterminado | `extraEnv` |
| `KURA_REGISTRATION_URL` | URL absoluta a la que el nodo envía latidos de registro, anunciando su endpoint visible para clientes. | Requerido al registrarse | Sin valor predeterminado | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | URL de caché visible para clientes que el plano de control entrega a los clientes. Debe ser accesible para todos los clientes de la cuenta. | Requerido al registrarse | Sin valor predeterminado | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | Frecuencia de los latidos de registro. El lease abarca varios latidos perdidos, por lo que un solo latido perdido no elimina el endpoint. | No | `60000` | `extraEnv` |

Si habilitas mTLS interno entre peers, configura `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH` y `KURA_INTERNAL_TLS_KEY_PATH` juntos. `KURA_NODE_URL` y cada valor en `KURA_PEERS` deben usar entonces `https://` con el puerto interno de peer.
