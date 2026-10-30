---
{
  "title": "Webhooks",
  "titleTemplate": ":title | Integraciones | Guías | Tuist",
  "description": "Suscribe endpoints HTTPS a eventos de Tuist, verifica las entregas con una carga útil firmada e inspecciona cada intento desde el panel."
}
---
# Webhooks {#webhooks}

Los webhooks permiten que tus sistemas reaccionen a los cambios dentro de Tuist en el momento en que ocurren. Cada vez que se produce un evento relevante —se observa un nuevo caso de test, una previsualización termina de subirse, un test intermitente se corrige— Tuist realiza una petición HTTP POST a cada endpoint suscrito a ese tipo de evento. El cuerpo de la petición es un envoltorio JSON y cada entrega incluye una cabecera de firma que puedes verificar con el secreto de firma del endpoint.

Registras una URL de destino, eliges los eventos que deseas y Tuist se encarga de la firma, los reintentos y el registro de auditoría de las entregas.

## Pasos para recibir webhooks {#steps}

Puedes empezar a recibir notificaciones de eventos en tu aplicación con estos pasos:

1. [Identifica los eventos](#event-types) que tu aplicación desea recibir.
2. [Crea un endpoint de webhook](#create-an-endpoint) como un endpoint HTTP (URL) en tu servidor local.
3. Gestiona las peticiones de Tuist [analizando la carga útil](#payload) y devolviendo [un estado 2xx](#responding) para que Tuist marque la entrega como exitosa.
4. [Verifica la firma](#verify-signature) en cada petición para demostrar que proviene de Tuist.
5. Utiliza el [registro de eventos](#inspect-deliveries) en el panel de Tuist para depurar mientras desarrollas.

## Tipos de evento {#event-types}

Tuist agrupa los eventos según el recurso que describen. El campo `type` del envoltorio utiliza notación con puntos (`{resource}.{action}`), igual que el valor al que te suscribirías en el panel.

{{webhook_events_table}}

Próximamente habrá más tipos de evento. Si necesitas alguno que aún no emitimos, háznoslo saber y lo añadiremos al catálogo.

## Crear un endpoint {#create-an-endpoint}

Los endpoints se configuran por cuenta. Abre **Webhooks** desde la configuración de tu cuenta, haz clic en **Añadir endpoint** e indica:

- **Nombre**: cómo aparece el endpoint en el listado.
- **URL del endpoint**: debe usar `https://`.
- **Eventos a escuchar**: elige los eventos específicos o usa **Seleccionar todo** a nivel de grupo. Tuist solo realiza peticiones POST al endpoint cuando se dispara uno de los eventos suscritos.

![Listado de endpoints con dos endpoints de webhook suscritos a dos eventos cada uno](/images/guides/integrations/webhooks/endpoints.png)

Al guardar, Tuist genera un nuevo secreto de firma y lo muestra una única vez. Cópialo en la configuración de tu aplicación de inmediato; no podrás recuperarlo de nuevo desde el panel. Si lo pierdes, utiliza **Rotar secreto** en el menú de acciones del endpoint para generar uno nuevo.

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="Modal de creación de endpoint de webhook con nombre, URL y casillas agrupadas por tipo de evento" style="max-width: 500px;" />

## La carga útil {#payload}

Cada entrega es un único objeto JSON. El envoltorio incluye una instantánea del recurso específica del evento dentro de metadatos que puedes usar para deduplicar, enrutar y auditar las entregas:

| Campo     | Descripción                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | Un UUID único para esta entrega. Úsalo para deduplicar cuando se produzcan reintentos. |
| `type`    | El tipo de evento con notación de puntos, por ejemplo `test_case.updated`.                         |
| `created` | Marca de tiempo Unix (segundos) en la que Tuist puso la entrega en cola.           |
| `object`  | La instantánea del recurso. La estructura depende del tipo de evento.              |

El esquema exacto de la carga útil para cada tipo de evento está documentado en la [referencia de la API de Tuist](https://tuist.dev/api/docs#section/Webhook-events) bajo **Eventos de webhook**; cada evento tiene un esquema `WebhookXxxEvent` correspondiente bajo `components.schemas` al que puedes hacer `$ref` desde un generador de código.

Una carga útil de `test_case.updated`, por ejemplo, también incluye un array `events` que enumera las transiciones canónicas que provocaron la escritura (`marked_flaky`, `muted`, `unskipped`, …), además de `actor_id` y `alert_id` para que los receptores puedan distinguir ediciones manuales de cambios impulsados por automatización.

Cada petición también incluye estas cabeceras HTTP:

| Cabecera              | Descripción                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | Siempre `application/json`.                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | El mismo UUID que `id` en el cuerpo; resulta útil si registras las cabeceras antes de analizar la carga útil.     |
| `Tuist-Event-Type`  | La misma cadena que `type` en el cuerpo.                                                            |
| `Tuist-Signature`   | La firma HMAC-SHA256, con el formato `t={timestamp},v1={hex_digest}`; consulta más abajo.          |

## Responder a un webhook {#responding}

Para confirmar una entrega, tu endpoint debe devolver cualquier código de estado `2xx`. Cualquier respuesta fuera del rango `2xx`, junto con fallos de conexión y tiempos de espera agotados, se considera un fallo de entrega y se reintenta. Tuist no sigue respuestas `3xx`, así que responde directamente en la URL canónica en lugar de redirigir.

Mantén tu gestor **rápido**: Tuist espera hasta **10 segundos** por la respuesta. Si tienes tareas pesadas que realizar (llamar a otra API, actualizar una base de datos, enviar notificaciones), acepta la petición y procésala de forma asíncrona. Responder pronto también te hace resistente a lentitudes transitorias en tus servicios downstream.

## Verificar la firma {#verify-signature}

Cualquiera que conozca la URL de tu endpoint puede hacerle POST. El secreto de firma permite a tu servidor rechazar cualquier cosa que no provenga de Tuist.

Para cada petición, Tuist calcula:

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

Para verificar en tu lado:

1. Lee la cabecera `Tuist-Signature` y divídela en las partes `t=` (marca de tiempo) y `v1=` (resumen hexadecimal).
2. Rechaza la petición si la marca de tiempo difiere más de **5 minutos** de la hora actual de tu servidor. Esto *acota* la ventana de reenvío pero no la cierra; combínalo con la idempotencia que se explica más abajo.
3. Vuelve a calcular `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` y compáralo con el resumen en **tiempo constante**.
4. Deduplica las entregas por el `id` de la carga útil (también expuesto como la cabecera `Tuist-Event-Id`). Es estable entre reintentos, así que persistir los IDs que ya has procesado evita que una petición capturada se reenvíe dentro de la ventana de tolerancia y te protege del doble procesamiento en un reintento.

> [!IMPORTANT] USE THE RAW BODY
> La firma se calcula sobre los bytes que envió Tuist. Si tu framework web vuelve a analizar y serializar el JSON antes de verificar, el resumen no coincidirá. Captura el cuerpo sin modificar (por ejemplo, `request.body.read` en Rack, el `Buffer` sin modificar en Express) y pásalo a tu verificador.

Un verificador de referencia en Node.js: adapta los mismos cuatro pasos (analizar la cabecera, comprobar la desviación de la marca de tiempo, volver a calcular el HMAC, comparar en tiempo constante) al lenguaje en el que esté escrito tu receptor:

```javascript
import crypto from "node:crypto";

function verifyTuistSignature(rawBody, header, secret, toleranceSeconds = 300) {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2))
  );
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const drift = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (drift > toleranceSeconds) return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");

  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(signature, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

## Reintentos {#retries}

Tuist reintenta cualquier entrega que devuelva un estado distinto de `2xx`, agote el tiempo de espera o falle al conectar. La programación es fija:

| Intento | Espera antes de enviar |
| ------- | ------------------- |
| 1       | (inmediato)         |
| 2       | 1 minuto            |
| 3       | 5 minutos           |
| 4       | 30 minutos          |
| 5       | 2 horas             |
| 6       | 8 horas             |
| 7       | 24 horas            |

Tras fallar el séptimo intento, la entrega se marca permanentemente como fallida. Como cada intento se firma con la marca de tiempo en la que se envió, tu ventana de protección contra reenvíos sigue aplicándose en los reintentos; no necesitas ampliarla.

## Inspeccionar entregas {#inspect-deliveries}

Abre un endpoint desde la página de **Webhooks** para ver su historial de entregas. La página de detalle muestra:

- Una **tarjeta de resumen** con la URL de destino, el secreto de firma enmascarado, los eventos suscritos y la fecha de creación.
- Un **gráfico de entregas** con totales acumulados y el recuento de fallos, limitado a la ventana de tiempo seleccionada.
- Una **tabla de eventos** que puedes filtrar por estado, tipo de evento o ID de evento.

![Página de detalle de un endpoint de webhook que muestra la tarjeta de resumen y el gráfico de entregas de eventos](/images/guides/integrations/webhooks/endpoint-detail.png)

Haz clic en un evento para ver la petición y la respuesta completas de ese intento: la carga útil exacta que envió Tuist, las cabeceras, el código de estado upstream y el cuerpo de la respuesta. Son los mismos datos que vio tu servidor, lo que convierte esta vista en la forma más rápida de depurar una discrepancia en la verificación de la firma o un error 5xx upstream.

![Página de detalle de un evento de webhook que muestra el resumen, las cabeceras y el cuerpo de la petición, y la respuesta upstream](/images/guides/integrations/webhooks/event-detail.png)

Los registros de entregas se conservan indefinidamente para que puedas revisar el historial al depurar una integración. Si tu sistema downstream necesita copias duraderas (por ejemplo, para cumplimiento normativo), captura las entregas en tu propia infraestructura a medida que llegan.

## Rotar o eliminar un endpoint {#rotate-or-delete}

Ambas acciones están en el menú de tres puntos de la fila del endpoint y en la página de detalle del endpoint:

- **Rotar secreto**: genera un nuevo secreto de firma y lo muestra una vez. Los consumidores existentes fallarán la verificación hasta que los actualices, así que planifica la rotación junto con un despliegue.
- **Eliminar endpoint**: elimina el endpoint y detiene las entregas. Los intentos de entrega ya registrados se conservan hasta que expire la ventana de retención estándar.

## Notas de seguridad {#security}

- Las URLs de los endpoints deben usar HTTPS. Tuist se niega a entregar a destinos en texto plano.
- Tuist resuelve el nombre de host de destino antes de cada entrega y rechaza direcciones de loopback, RFC1918, link-local, ULA y de metadatos de la nube (`169.254.169.254`, `fd00::/8`, …). Esto evita que un webhook mal configurado se use para escanear o atacar el host que ejecuta tu servidor de Tuist.
- La URL del endpoint y el secreto de firma están cifrados en reposo. Se excluyen de las exportaciones de datos GDPR/CCPA como credenciales de portador.
- El secreto de firma se muestra exactamente una vez. Trátalo como una contraseña: guárdalo en tu gestor de secretos, no en el repositorio.
