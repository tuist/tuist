## Canales con tuist share {#share-tracks}

Para flujos de trabajo que publican con `tuist share`, usa `--track` para seleccionar un canal:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## Notas de la versión {#release-notes}

Usa canales para grupos de entornos y notas de la versión para el propósito de una compilación individual:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Reemplaza `App` por el nombre de tu app, la ruta del archivo de la aplicación o la distribución ejecutable y su opción `--executable`. Las notas de la versión son texto plano opcional, de hasta 10.000 caracteres. La primera línea no vacía aparece como un fragmento de una sola línea en las listas de previsualizaciones, de modo que los números de compilación y otra información identificativa son visibles de un vistazo. Las líneas largas se truncan; las notas completas aparecen en las páginas de detalle. Las búsquedas coinciden con los nombres mostrados y las notas de la versión completas, incluidas las líneas que no se muestran en el fragmento. Se admiten notas multilínea, por ejemplo `--release-notes "$(< release-notes.txt)"`. No cambian el nombre mostrado de la app ni su canal.

### Compatibilidad {#preview-metadata-compatibility}

Las notas de la versión no cambian a qué previsualización pertenece una compilación. Se conservan las primeras notas que recibe una previsualización: una carga posterior puede añadir notas a una previsualización que no tenga ninguna, pero no puede sobrescribir ni borrar las existentes. Las previsualizaciones subidas antes de que existieran las notas de la versión siguen siendo válidas sin ellas.

Los despliegues autoalojados necesitan una versión del servidor que admita notas de la versión y filtrado por canal, junto con un cliente actualizado. Los servidores antiguos ignoran las notas. Para los filtros de canal y búsqueda de los endpoints de lista, consulta la [referencia de la API](https://tuist.dev/api/docs).

## Comentarios en solicitudes de extracción/fusión {#pullmerge-request-comments}

> [!WARNING]
> **Integración con Git forge requerida**
>
> Para obtener comentarios automáticos en solicitudes de extracción/fusión, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto remoto</.localized_link> con una Git forge: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> o <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, añade <.localized_link href="/cli/share">`tuist share`</.localized_link> después de una compilación exitosa de la aplicación en CI. Tuist publicará un enlace de previsualización directamente en tus solicitudes de extracción/fusión, para que los revisores puedan probar sin compilar localmente:

![Comentario de la app de GitHub con un enlace a Tuist Preview](/images/guides/features/github-app-with-preview.png)

## Automatizaciones {#automations}

Usa `--json` para obtener salida JSON de `tuist share`:

```bash
tuist share --json
```

Usa el resultado para automatizaciones personalizadas, como publicar un mensaje en Slack desde CI. La clave `url` contiene el enlace completo a la previsualización; `qrCodeURL` apunta a una imagen de código QR para abrir la previsualización en un dispositivo:

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
