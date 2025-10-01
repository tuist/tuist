---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Registro {#logging}

La CLI registra mensajes internamente para ayudarle a diagnosticar problemas.

## Diagnosticar problemas utilizando registros {#diagnose-issues-using-logs}

Si la invocación de un comando no produce los resultados esperados, puede
diagnosticar el problema inspeccionando los registros. La CLI envía los
registros a [OSLog](https://developer.apple.com/documentation/os/oslog) y al
sistema de archivos.

En cada ejecución, crea un archivo de registro en
`$XDG_STATE_HOME/tuist/logs/{uuid}.log` donde `$XDG_STATE_HOME` toma el valor
`~/.local/state` si la variable de entorno no está establecida.

Por defecto, la CLI muestra la ruta de logs cuando la ejecución finaliza
inesperadamente. Si no lo hace, puede encontrar los registros en la ruta
mencionada anteriormente (es decir, el archivo de registro más reciente).

> [IMPORTANTE] La información sensible no se elimina, así que ten cuidado al
> compartir los registros.

### Integración continua {#diagnose-issues-using-logs-ci}

En CI, donde los entornos son desechables, es posible que desee configurar su
tubería CI para exportar los registros de Tuist. La exportación de artefactos es
una capacidad común en todos los servicios de CI, y la configuración depende del
servicio que utilices. Por ejemplo, en GitHub Actions, puedes usar la acción
`actions/upload-artifact` para subir los registros como un artefacto:

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
