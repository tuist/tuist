---
{
  "title": "Compatibilidad",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Cuánto tiempo el servidor de Tuist admite versiones anteriores de la CLI, qué significa esta ventana de soporte para las actualizaciones y qué ocurre con las versiones que quedan fuera de ella."
}
---

# Compatibilidad {#compatibility}

La CLI de Tuist se comunica con el servidor de Tuist para funcionalidades como la caché, los análisis de compilación y tests, las previews y el registro. El servidor se actualiza de forma continua e independiente de cuándo actualices la CLI, por lo que un cambio en el servidor no debe romper la versión de la CLI que estás ejecutando. Para garantizarlo, el servidor mantiene la compatibilidad con las versiones recientes de la CLI durante un periodo definido.

## Ventana de soporte {#support-window}

El servidor de Tuist admite versiones de la CLI de los **últimos 3 meses**. Durante ese periodo, el servidor mantiene la compatibilidad hacia atrás: cualquier CLI publicada en los últimos 3 meses sigue compilando, usando la caché y ejecutando tests contra el servidor, y puedes actualizar la CLI según tu propio calendario sin que un cambio en el servidor te afecte.

La CLI sigue el [versionado semántico](https://semver.org). Se admite cualquier versión publicada en los últimos 3 meses.

## Fuera de la ventana {#outside-the-window}

Las versiones de la CLI anteriores a la ventana de soporte se consideran obsoletas. El servidor sigue respondiendo, pero:

- Es posible que las nuevas funcionalidades del lado del servidor no funcionen con esa versión.
- Los comandos respaldados por el servidor pueden mostrar una advertencia pidiéndote que actualices.

No se garantiza el comportamiento en versiones obsoletas. Si estás usando una, actualiza a una versión dentro de la ventana de soporte.

## Cómo cumplimos la promesa {#how-we-keep-the-promise}

La compatibilidad hacia atrás se verifica, no se da por sentada. Cada despliegue del servidor ejecuta una prueba de aceptación automatizada contra la **versión de la CLI más antigua que aún está dentro de la ventana de soporte**, que actualmente es `{{minimum_supported_cli_version}}`, probando de extremo a extremo el flujo de descarga de la caché. Si un cambio rompiera esa versión, el despliegue se bloquea antes de llegar a producción. Esto se ejecuta junto con las pruebas contra la última CLI, de modo que una regresión para clientes antiguos se detecta de la misma manera que una regresión para la versión más reciente.

## Recomendación {#recommendation}

Actualiza la CLI al menos una vez cada 3 meses para mantenerte dentro de la ventana soportada. Fijar la versión de la CLI en CI y aumentarla con regularidad mantiene a tu equipo en una versión consistente y soportada.
