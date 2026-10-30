---
{
  "title": "Análisis de compilaciones de Elixir",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Sigue cuánto tarda en compilarse tu proyecto de Elixir con Mix, sus advertencias y los archivos que ralentizan tus compilaciones."
}
---
# Análisis de compilaciones de Elixir {#elixir-build-insights}

El paquete Hex de Tuist puede enviar análisis de compilación a Tuist. Los tiempos de compilación, el grafo de dependencias entre tus archivos y cómo ambos evolucionan con el tiempo te proporcionan lo necesario para optimizar tu grafo de compilación y aprovechar al máximo todos los núcleos disponibles en el entorno donde tiene lugar la compilación.

> [!IMPORTANT] REQUIREMENTS
> - Completa <.localized_link href="/guides/get-started/elixir-project">Get started with Elixir</.localized_link>

## Informa de tus compilaciones {#report-your-builds}

La configuración compartida instala la integración de compilación. Sigue usando tus comandos habituales:

```bash
mix compile
```

La integración cubre `mix compile` y cada compilación que otra tarea desencadene, como `mix test` o `mix phx.server`. Una compilación que no encuentra nada que hacer no se informa, por lo que el panel solo lista compilaciones que realizaron trabajo.

## Informar de la reclamación de actor {#report-actor-claim}

Las solicitudes de informe de compilación y prueba de Mix incluyen la cabecera opcional `x-tuist-actor-id` solo cuando configuras explícitamente una etiqueta. Establece `TUIST_ACTOR_ID` con una etiqueta con ámbito de organización, o añade `actor_id: "developer-label"` a la configuración `tuist` del proyecto. La resolución prioriza la variable de entorno, luego las opciones `:actor_id` en tiempo de ejecución y, finalmente, la configuración del proyecto. Por defecto no se envía ninguna etiqueta y el paquete no detecta los nombres de usuario del sistema operativo. Una etiqueta fija del proyecto se aplica a todos los que usan esa configuración. Las anulaciones vacías o inválidas omiten la reclamación en lugar de recurrir a un respaldo; esto no elimina la identidad verificada basada en credenciales. Si un proxy personalizado rechaza cabeceras desconocidas, exclúyete con `TUIST_ACTOR_ID=""`.

Los identificadores deben ser de 1 a 128 bytes de ASCII imprimible sin espacios. Las anulaciones inválidas se omiten sin recurrir a un respaldo. Las credenciales individuales verificadas tienen prioridad; otros identificadores reportados por el cliente se muestran como **Sin verificar**, nunca autorizan el acceso y nunca se vinculan automáticamente a usuarios. Cualquiera que pueda ver los informes del proyecto puede ver estos identificadores, incluidos los espectadores públicos cuando el proyecto es público, y se incluyen en las exportaciones de datos, así que no incluyas secretos. Los servidores antiguos ignoran la cabecera opcional y los nuevos servidores aceptan clientes antiguos sin ella. Los nuevos informes con token compartido sin identificador muestran **Desconocido**, en lugar de la organización que publica; los informes históricos conservan su atribución anterior. Los informes de compilación y prueba requieren autenticación por defecto. Las instalaciones autoalojadas pueden habilitar explícitamente los informes sin credenciales como se describe a continuación.

## Informes sin credenciales en una red privada {#network-trusted-publishing}

Después de que un operador configure `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` en la instancia y la reinicie como se describe en la <.localized_link href="/guides/server/self-host/server#network-trusted-access">guía de autoalojamiento</.localized_link>, configura tu destino. El SDK descubre automáticamente si la instancia permite informes sin credenciales cuando estas están ausentes. La configuración de la instancia cubre todos los proyectos compatibles y no tiene ningún interruptor en el panel:

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` y `mix tuist.test` publican informes estructurados sin inicio de sesión cuando las credenciales están realmente ausentes y la descubierta confirma que el servidor lo permite. No se requiere ninguna bandera del cliente ni opt-in del proyecto. Las credenciales presentes, incluida la identidad OIDC de CI suministrada, se utilizan o se rechazan, nunca se ignoran para degradar a informes no firmados. Un `TUIST_TOKEN` que contenga solo espacios en blanco es un error. Un `TUIST_TOKEN` vacío puede recurrir a credenciales almacenadas válidas o a OIDC suministrado, y las credenciales almacenadas obsoletas pueden recurrir a OIDC suministrado; ambas rutas permanecen autenticadas y nunca habilitan informes no firmados. Las credenciales inutilizables se conservan y fallan cuando ningún respaldo autenticado tiene éxito. Actualiza cada réplica del servidor a una versión capaz de descubierta antes de actualizar los clientes sin credenciales; los servidores antiguos sin descubierta, las instancias deshabilitadas y los fallos de descubierta aún requieren autenticación.

Las ejecuciones no firmadas son telemetría, no evidencia confiable de inestabilidad, cuarentena, cobertura o ejecución selectiva. La planificación de fragmentos, los archivos de compilación y los puntos finales de cobertura/artefactos aún requieren credenciales. Establece `TUIST_ACTOR_ID=""` de forma independiente para omitir la reclamación de actor configurada; la identidad de credencial verificada no se ve afectada.

## Qué se rastrea {#what-is-tracked}

Para cada compilación, el paquete recopila:
- Su duración, si tuvo éxito y el entorno de Elixir, Erlang/OTP y Mix con el que se ejecutó
- Cada advertencia y error, con su archivo y línea
- Cuánto tardó en compilarse cada archivo y los módulos que define
- Los archivos de los que depende cada archivo y si los necesita en tiempo de compilación o solo en tiempo de ejecución
- Lo que hizo la compilación además de compilar archivos, como la comprobación de tipos, la escritura en disco y los otros compiladores de Mix
- El uso de procesador, memoria, red y disco de la máquina durante la compilación
- La rama y el commit, y en integración continua, el proveedor y la ejecución

## Encuentra qué ralentiza una compilación {#find-what-slows-a-build-down}

Abre una compilación desde **Compilaciones → Ejecuciones de compilación** en el panel. Las compilaciones, sus recuentos de diagnósticos y sus resúmenes de caché de dependencias también están disponibles a través de `tuist build mix list` y `tuist build mix show`, `GET /api/projects/{account_handle}/{project_handle}/mix/builds`, y las `list_mix_builds` y `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">herramientas MCP</.localized_link>.

La pestaña **Resumen** lista los archivos que compiló la compilación. Puedes agruparlos por módulo, buscarlos y ordenarlos por:
- **Duración de compilación**, para encontrar los archivos que son lentos por sí mismos.
- **Dependientes en tiempo de compilación**, el número de archivos que no pueden compilarse hasta que este lo haga. Un archivo lento con muchos dependientes retrasa el resto de la compilación y cambiarlo recompila todos ellos.
- **Dependencias en tiempo de compilación**, el número de archivos que este espera.

![Resumen de una compilación Mix de una aplicación Phoenix](/images/guides/features/elixir/build.png)

La pestaña **Cronología** muestra la misma compilación a lo largo del tiempo: qué archivos se compilaron en paralelo, dónde la compilación realizó comprobaciones de tipos y escribió en disco, y cómo estaba la máquina en cada momento. Un tramo con una sola barra es un tramo donde la compilación no pudo usar los núcleos que tenía.

![Cronología de una compilación Mix completa de una aplicación Phoenix](/images/guides/features/elixir/build-timeline.png)

Las pestañas **Advertencias** y **Errores** listan los diagnósticos de la compilación.

## Metadatos personalizados {#custom-metadata}

Adjunta etiquetas y datos clave-valor a las compilaciones de Mix para distinguir ejecuciones de diferentes equipos, hardware o flujos de trabajo. Ambos aparecen en la página de detalles de cada compilación.

Establece metadatos con variables de entorno:

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

También puedes configurar metadatos en `mix.exs`:

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

Las etiquetas de ambos lugares se combinan. Cuando la misma clave está configurada en ambos lugares, el valor de la variable de entorno tiene prioridad.

Las etiquetas deben contener solo letras, números, guiones y guiones bajos. Una compilación puede tener hasta 50 etiquetas, y cada etiqueta puede contener hasta 50 caracteres. Una compilación puede tener hasta 20 entradas clave-valor, cada clave puede contener hasta 50 caracteres y cada valor puede contener hasta 500 caracteres. Estos son los mismos límites del servidor utilizados para los metadatos de compilación de Xcode. El paquete omite las etiquetas no válidas y las entradas de metadatos vacías o demasiado grandes antes de enviar el informe, por lo que una configuración no válida no puede impedir que el resto del informe de análisis de compilaciones se almacene. Usa metadatos clave-valor para valores que no cumplan la restricción de etiquetas.

Los metadatos personalizados se adjuntan a las compilaciones, no a las ejecuciones de tests.

Los metadatos personalizados son visibles para los miembros del proyecto en el panel. No los uses para credenciales, tokens de acceso u otros datos sensibles. Tuist conserva los datos de compilación de Mix, incluidos estos metadatos, durante 90 días. Consulta la <.localized_link href="/guides/server/data-retention">política de retención de datos</.localized_link> para más detalles.

## Solución de problemas {#troubleshooting}

El envío de informes nunca cambia el resultado de tu compilación: si el informe no se puede enviar, la compilación finaliza como lo habría hecho y no se imprime nada. Para ver por qué no se envió un informe, establece `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix compile --force
```
