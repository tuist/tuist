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

Reemplaza `App` por el nombre de tu app, la ruta del archivo de aplicación o la distribución ejecutable y su opción `--executable`. Las notas de la versión son texto plano opcional, de hasta 10.000 caracteres. La primera línea no vacía aparece como un fragmento de una sola línea en las listas de previsualizaciones, de modo que los números de compilación y otra información identificativa son visibles de un vistazo. Las líneas largas se truncan; las notas completas aparecen en las páginas de detalle. Las búsquedas coinciden con los nombres visibles y las notas de la versión completas, incluidas las líneas que no se muestran en el fragmento. Se admiten notas multilínea, por ejemplo `--release-notes "$(< release-notes.txt)"`. No cambian el nombre visible de la app ni su canal.

### Compatibilidad {#preview-metadata-compatibility}

Las notas de la versión son metadatos aditivos, no forman parte de la identidad de una previsualización. Las cargas desde clientes antiguos y nuevos siguen agrupándose en la misma previsualización entre plataformas. Se conservan las primeras notas no vacías: una carga posterior puede rellenar notas que antes faltaban, pero no puede sobrescribir notas existentes. Omitir `release_notes`, enviar `null` o enviar una cadena vacía o solo con espacios en blanco nunca borra las notas. Las previsualizaciones existentes no se rellenan retroactivamente y siguen siendo válidas sin notas.

El parámetro de consulta opcional `track` de la API de listado coincide con el nombre completo de un canal, sin distinguir mayúsculas y minúsculas, de forma coherente con el almacenamiento existente de canales. Omítelo o envía un valor vacío (`?track=`) para listar todos los canales. Los nombres de canal siguen siendo cadenas abiertas, no una lista fija de valores. `GET /api/projects/:account_handle/:project_handle/previews/tracks` devuelve `{total_count, tracks: [{name, count}]}` con canales nombrados ordenados y agrupados sin distinguir mayúsculas y minúsculas, bajo la misma autorización de lectura de previsualizaciones que el listado de compilaciones. Los recuentos cubren todo el proyecto independientemente de la paginación, la búsqueda y el canal seleccionado; el total incluye previsualizaciones sin canal. Solo se cuentan las previsualizaciones listables con un identificador de bundle. La API de listado también acepta el parámetro opcional `search` para una subcadena literal, sin distinguir mayúsculas y minúsculas, del nombre visible o de las notas de la versión completas, combinado con el canal antes de la paginación. El filtrado existente por `display_name` sigue siendo exacto.

Los clientes antiguos pueden seguir cargando y listando previsualizaciones sin enviar ninguno de estos campos. Los clientes nuevos aceptan respuestas antiguas que omiten el canal o las notas e ignoran propiedades de respuesta desconocidas añadidas por servidores futuros. Las integraciones con la API deben ignorar igualmente las propiedades de respuesta desconocidas para que los metadatos aditivos sigan siendo compatibles.

Las implementaciones autoalojadas necesitan una versión del servidor que admita notas de la versión y filtrado por canal, junto con un cliente actualizado, para usar estas funcionalidades. Los servidores más antiguos pueden ignorar las notas o los parámetros de consulta desconocidos.

## Comentarios en solicitudes de pull/fusión {#pullmerge-request-comments}

> [!WARNING]
> **Integración con plataforma Git requerida**
>
> Para obtener comentarios automáticos en solicitudes de pull/fusión, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto remoto</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.

Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, añade <.localized_link href="/cli/share">`tuist share`</.localized_link> después de una compilación exitosa de la aplicación en CI. Tuist publicará un enlace de previsualización directamente en tus solicitudes de pull/fusión, para que los revisores puedan probar sin compilar localmente:

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
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
